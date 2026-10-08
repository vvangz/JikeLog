package auth

import (
	"bytes"
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
)

// Refresh 轮换 Refresh Token 并签发新的 Access Token。
//
//   - 出示当前令牌：正常轮换，上一枚令牌保留用于宽限。
//   - 出示上一枚令牌且在宽限期内：视为客户端没收到上次响应而重试，再换发一次（宽限起点不变，不能无限延长）。
//   - 出示上一枚令牌但已超过宽限期：令牌可能被窃取，该设备立即下线。
func (s *Service) Refresh(ctx context.Context, raw, ip string) (TokenPair, error) {
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
		pair, err = s.rotate(ctx, q, dev, HashToken(raw), ip)
		return err
	})
	if errors.Is(err, errReused) {
		s.d.Logger.WarnContext(ctx, "refresh token reuse detected, revoking device", "device_id", deviceID)
		if err := s.revokeDevice(ctx, deviceID); err != nil {
			return TokenPair{}, err
		}
		return TokenPair{}, errRefreshInvalid
	}
	return pair, err
}

func (s *Service) rotate(ctx context.Context, q *dbgen.Queries, dev dbgen.Device, presented []byte, ip string) (TokenPair, error) {
	now := s.d.Now()
	params := dbgen.SetDeviceRefreshParams{ID: dev.ID, LastIp: ip}
	switch {
	case bytes.Equal(presented, dev.RefreshHash):
		if dev.RefreshExpiresAt == nil || !now.Before(*dev.RefreshExpiresAt) {
			return TokenPair{}, errRefreshInvalid
		}
		params.RefreshPrevHash = dev.RefreshHash
		params.RefreshRotatedAt = &now
	case dev.RefreshRotatedAt != nil && now.Sub(*dev.RefreshRotatedAt) <= refreshGrace:
		params.RefreshPrevHash = dev.RefreshPrevHash
		params.RefreshRotatedAt = dev.RefreshRotatedAt
	default:
		return TokenPair{}, errReused
	}
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
	access, accessExp, err := s.d.Tokens.IssueAccess(dev.UserID, dev.ID)
	if err != nil {
		return TokenPair{}, err
	}
	return TokenPair{AccessToken: access, AccessExpiresAt: accessExp, RefreshToken: raw, RefreshExpiresAt: refreshExp}, nil
}

func (s *Service) revokeDevice(ctx context.Context, deviceID uuid.UUID) error {
	dev, err := s.d.Tx.Queries().GetDeviceByID(ctx, deviceID)
	if err != nil {
		return fmt.Errorf("查询设备失败: %w", err)
	}
	ids, err := s.d.Tx.Queries().RevokeDevice(ctx, dbgen.RevokeDeviceParams{ID: dev.ID, UserID: dev.UserID})
	if err != nil {
		return fmt.Errorf("下线设备失败: %w", err)
	}
	return s.RevokeDevices(ctx, ids)
}

// Logout 注销当前设备会话。
func (s *Service) Logout(ctx context.Context, p Principal) error {
	ids, err := s.d.Tx.Queries().RevokeDevice(ctx, dbgen.RevokeDeviceParams{ID: p.DeviceID, UserID: p.UserID})
	if err != nil {
		return fmt.Errorf("退出登录失败: %w", err)
	}
	// 即使设备已被下线（ids 为空），也要让当前这枚 Access Token 立即失效
	return s.RevokeDevices(ctx, append(ids, p.DeviceID))
}

// SetPassword 更新密码并让其他设备全部下线；keep 为需要保留的当前设备，nil 表示全部下线。
func (s *Service) SetPassword(ctx context.Context, userID uuid.UUID, password string, keep *uuid.UUID) error {
	hash, err := s.d.Hasher.Hash(ctx, password)
	if err != nil {
		return err
	}
	var revoked []uuid.UUID
	err = s.d.Tx.InTx(ctx, func(q *dbgen.Queries) error {
		if err := q.UpdateUserPassword(ctx, dbgen.UpdateUserPasswordParams{ID: userID, PasswordHash: hash}); err != nil {
			return fmt.Errorf("更新密码失败: %w", err)
		}
		if keep != nil {
			revoked, err = q.RevokeOtherDevices(ctx, dbgen.RevokeOtherDevicesParams{UserID: userID, KeepID: *keep})
		} else {
			revoked, err = q.RevokeAllDevices(ctx, userID)
		}
		if err != nil {
			return fmt.Errorf("下线其他设备失败: %w", err)
		}
		return nil
	})
	if err != nil {
		return err
	}
	return s.RevokeDevices(ctx, revoked)
}

// CheckUserPassword 校验指定用户的当前密码。
func (s *Service) CheckUserPassword(ctx context.Context, user dbgen.User, password string) (bool, error) {
	ok, _, err := s.d.Hasher.Verify(ctx, password, user.PasswordHash)
	return ok, err
}
