package auth

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
)

// refreshGrace 内重复使用刚被轮换的 Refresh Token 视为网络重试或并发刷新，而非泄露。
const refreshGrace = 30 * time.Second

// Refresh 轮换 Refresh Token 并签发新的 Access Token。
//
//   - 出示当前令牌：正常轮换，结果缓存 refreshGrace（见 RefreshReplay），上一枚令牌留作宽限。
//   - 出示上一枚令牌且在宽限期内：返回第一次换发的同一结果（幂等），客户端无论保留哪次响应都有效；
//     缓存丢失时退化为再换发一次。
//   - 出示上一枚令牌但已超过宽限期：令牌可能被窃取，该设备立即下线。
func (s *Service) Refresh(ctx context.Context, raw, ip string) (TokenPair, error) {
	if err := s.limitIP(ctx, bucketRefresh, ip); err != nil {
		return TokenPair{}, err
	}
	var (
		pair     TokenPair
		deviceID uuid.UUID
	)
	err := s.d.Tx.InTx(ctx, func(q *dbgen.Queries) error {
		dev, err := q.GetDeviceByRefreshHashForUpdate(ctx, HashToken(raw))
		if db.IsNotFound(err) {
			return errRefreshInvalid
		}
		if err != nil {
			return fmt.Errorf("查询设备会话失败: %w", err)
		}
		deviceID = dev.ID
		rotated, err := s.rotate(ctx, q, dev, raw, ip)
		pair = rotated
		return err
	})
	if errors.Is(err, errReused) {
		s.d.Logger.WarnContext(ctx, "refresh token reuse detected, revoking device", "device_id", deviceID)
		if err := s.revokeReusedDevice(ctx, deviceID); err != nil {
			return TokenPair{}, err
		}
		return TokenPair{}, errRefreshInvalid
	}
	return pair, err
}

func (s *Service) rotate(ctx context.Context, q *dbgen.Queries, dev dbgen.Device, raw, ip string) (TokenPair, error) {
	now := s.now()
	params := dbgen.SetDeviceRefreshParams{ID: dev.ID, LastIp: ip}
	switch {
	case bytes.Equal(HashToken(raw), dev.RefreshHash):
		if dev.RefreshExpiresAt == nil || !now.Before(*dev.RefreshExpiresAt) {
			return TokenPair{}, errRefreshInvalid
		}
		params.RefreshPrevHash = dev.RefreshHash
		params.RefreshRotatedAt = &now
	case dev.RefreshRotatedAt != nil && now.Sub(*dev.RefreshRotatedAt) <= refreshGrace:
		cached, ok, err := s.d.Replay.Load(ctx, raw)
		if err != nil {
			s.d.Logger.WarnContext(ctx, "refresh replay cache unavailable", "error", err)
		}
		if ok {
			return cached, nil
		}
		// 缓存丢失：再换发一次，宽限起点不变，不能借此无限延长
		params.RefreshPrevHash = dev.RefreshPrevHash
		params.RefreshRotatedAt = dev.RefreshRotatedAt
	default:
		return TokenPair{}, errReused
	}
	pair, err := s.issueRotated(ctx, q, dev, params, now)
	if err != nil {
		return TokenPair{}, err
	}
	// 在提交前写入缓存：并发的第二个请求会在行锁释放后读到它
	if err := s.d.Replay.Save(ctx, raw, pair); err != nil {
		s.d.Logger.WarnContext(ctx, "refresh replay cache save failed", "error", err)
	}
	return pair, nil
}

func (s *Service) issueRotated(ctx context.Context, q *dbgen.Queries, dev dbgen.Device, params dbgen.SetDeviceRefreshParams, now time.Time) (TokenPair, error) {
	raw, hash, err := NewRefreshToken()
	if err != nil {
		return TokenPair{}, err
	}
	refreshExp := now.Add(s.d.RefreshTTL)
	params.RefreshHash = hash
	params.RefreshExpiresAt = &refreshExp
	if err := q.SetDeviceRefresh(ctx, params); err != nil {
		return TokenPair{}, fmt.Errorf("轮换令牌失败: %w", err)
	}
	access, accessExp, err := s.d.Tokens.IssueAccess(dev.UserID, dev.ID, now)
	if err != nil {
		return TokenPair{}, err
	}
	return TokenPair{AccessToken: access, AccessExpiresAt: accessExp, RefreshToken: raw, RefreshExpiresAt: refreshExp}, nil
}

// revokeReusedDevice 让疑似令牌泄露的设备下线。即使客户端已断开也要完成。
func (s *Service) revokeReusedDevice(ctx context.Context, deviceID uuid.UUID) error {
	ctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
	defer cancel()
	q := s.d.Tx.Queries()
	dev, err := q.GetDeviceByID(ctx, deviceID)
	if err != nil {
		return fmt.Errorf("查询设备失败: %w", err)
	}
	if _, err := q.RevokeDevice(ctx, dbgen.RevokeDeviceParams{ID: dev.ID, UserID: dev.UserID, Now: s.now()}); err != nil {
		return fmt.Errorf("下线设备失败: %w", err)
	}
	return nil
}

// Logout 注销当前设备会话，当前 Access Token 随即失效。
func (s *Service) Logout(ctx context.Context, p Principal) error {
	_, err := s.d.Tx.Queries().RevokeDevice(ctx, dbgen.RevokeDeviceParams{ID: p.DeviceID, UserID: p.UserID, Now: s.now()})
	if err != nil {
		return fmt.Errorf("退出登录失败: %w", err)
	}
	return nil
}
