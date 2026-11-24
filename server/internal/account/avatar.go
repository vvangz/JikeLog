package account

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"image"
	_ "image/jpeg" // 注册 JPEG 尺寸解码
	_ "image/png"  // 注册 PNG 尺寸解码
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
	"github.com/vvangz/JikeLog/server/internal/platform/storage"
)

const (
	// CodeAvatarNotFound 表示当前用户未设置自定义头像或头像对象不存在。
	CodeAvatarNotFound = "AVATAR_NOT_FOUND"
	// MaxAvatarBytes 限制头像原图解码后的最大字节数（2 MiB）。
	MaxAvatarBytes     = 2 << 20
	maxAvatarDimension = 4096
	avatarUploadLimit  = 20
	avatarUploadWindow = time.Hour
)

var (
	errAvatarNotFound    = httpx.NewError(http.StatusNotFound, CodeAvatarNotFound, "尚未设置自定义头像")
	errAvatarStoreUnset  = httpx.NewError(http.StatusServiceUnavailable, "AVATAR_STORAGE_UNAVAILABLE", "头像存储暂不可用")
	errAvatarTooLarge    = httpx.Validation(map[string]string{"data": "头像图片不能超过 2 MiB"})
	errAvatarInvalidData = httpx.Validation(map[string]string{"data": "头像图片数据无效，请重新选择 JPEG、PNG 或 WebP 图片"})
	errAvatarDimExceeded = httpx.Validation(map[string]string{"data": "头像图片尺寸过大，宽高均不能超过 4096 像素"})
)

// AvatarStore 抽象头像所需的对象存储能力（由 *storage.Store 实现）。
type AvatarStore interface {
	Put(ctx context.Context, key string, r io.Reader, size int64, contentType string) error
	Open(ctx context.Context, key string) (io.ReadCloser, error)
	Delete(ctx context.Context, key string) error
}

// AvatarData 表示从对象存储读取到的头像内容与元数据。
type AvatarData struct {
	Bytes       []byte
	ContentType string
	ETag        string
}

// UploadAvatar 校验并保存自定义头像，返回更新后的用户记录。
func (s *Service) UploadAvatar(ctx context.Context, p auth.Principal, contentType, b64Data string) (dbgen.User, error) {
	if s.avatars == nil {
		return dbgen.User{}, errAvatarStoreUnset
	}
	r, err := s.limiter.Hit(ctx, "avatar:upload:"+p.UserID.String(), avatarUploadLimit, avatarUploadWindow)
	if err != nil {
		return dbgen.User{}, err
	}
	if !r.Allowed {
		return dbgen.User{}, httpx.TooManyRequests(httpx.CodeRateLimited, "更换头像过于频繁，请稍后再试", r.RetryAfter)
	}

	cleaned := strings.TrimSpace(b64Data)
	if cleaned == "" {
		return dbgen.User{}, errAvatarInvalidData
	}
	if base64.StdEncoding.DecodedLen(len(cleaned)) > MaxAvatarBytes+3 {
		return dbgen.User{}, errAvatarTooLarge
	}
	raw, err := base64.StdEncoding.DecodeString(cleaned)
	if err != nil {
		return dbgen.User{}, errAvatarInvalidData
	}
	mime, ext, err := validateAvatarImage(contentType, raw)
	if err != nil {
		return dbgen.User{}, err
	}

	u, err := s.currentUser(ctx, p)
	if err != nil {
		return dbgen.User{}, err
	}
	oldKey := u.AvatarKey

	id, err := uuid.NewV7()
	if err != nil {
		return dbgen.User{}, fmt.Errorf("生成头像标识失败: %w", err)
	}
	newKey := "u/" + u.ID.String() + "/avatar/" + id.String() + ext
	sum := sha256.Sum256(raw)
	etag := hex.EncodeToString(sum[:8])

	if err := s.avatars.Put(ctx, newKey, bytes.NewReader(raw), int64(len(raw)), mime); err != nil {
		return dbgen.User{}, fmt.Errorf("保存头像对象失败: %w", err)
	}

	updated, err := s.tx.Queries().UpdateUserAvatar(ctx, dbgen.UpdateUserAvatarParams{
		ID:         u.ID,
		AvatarKey:  &newKey,
		AvatarMime: &mime,
		AvatarEtag: &etag,
	})
	if err != nil {
		// 写库失败时尽力清理已上传的新对象，避免残留孤儿文件
		_ = s.avatars.Delete(context.WithoutCancel(ctx), newKey)
		if db.IsNotFound(err) {
			return dbgen.User{}, httpx.Unauthorized("账号不存在或已注销")
		}
		return dbgen.User{}, fmt.Errorf("更新用户头像记录失败: %w", err)
	}

	if oldKey != nil && *oldKey != "" && *oldKey != newKey {
		_ = s.avatars.Delete(context.WithoutCancel(ctx), *oldKey)
	}
	return updated, nil
}

// GetAvatar 读取当前用户已上传的自定义头像二进制数据。
func (s *Service) GetAvatar(ctx context.Context, p auth.Principal) (AvatarData, error) {
	if s.avatars == nil {
		return AvatarData{}, errAvatarStoreUnset
	}
	u, err := s.currentUser(ctx, p)
	if err != nil {
		return AvatarData{}, err
	}
	if u.AvatarKey == nil || *u.AvatarKey == "" || u.AvatarMime == nil || u.AvatarEtag == nil {
		return AvatarData{}, errAvatarNotFound
	}
	rc, err := s.avatars.Open(ctx, *u.AvatarKey)
	if errors.Is(err, storage.ErrNotFound) {
		return AvatarData{}, errAvatarNotFound
	}
	if err != nil {
		return AvatarData{}, fmt.Errorf("读取头像对象失败: %w", err)
	}
	defer func() { _ = rc.Close() }()

	data, err := io.ReadAll(io.LimitReader(rc, MaxAvatarBytes+1))
	if err != nil {
		return AvatarData{}, fmt.Errorf("读取头像数据失败: %w", err)
	}
	if len(data) == 0 || len(data) > MaxAvatarBytes {
		return AvatarData{}, errAvatarNotFound
	}
	return AvatarData{Bytes: data, ContentType: *u.AvatarMime, ETag: *u.AvatarEtag}, nil
}

// DeleteAvatar 清除当前用户的自定义头像并尽力删除旧对象。
func (s *Service) DeleteAvatar(ctx context.Context, p auth.Principal) (dbgen.User, error) {
	u, err := s.currentUser(ctx, p)
	if err != nil {
		return dbgen.User{}, err
	}
	oldKey := u.AvatarKey
	updated, err := s.tx.Queries().ClearUserAvatar(ctx, u.ID)
	if db.IsNotFound(err) {
		return dbgen.User{}, httpx.Unauthorized("账号不存在或已注销")
	}
	if err != nil {
		return dbgen.User{}, fmt.Errorf("清除用户头像记录失败: %w", err)
	}
	if s.avatars != nil && oldKey != nil && *oldKey != "" {
		_ = s.avatars.Delete(context.WithoutCancel(ctx), *oldKey)
	}
	return updated, nil
}

// validateAvatarImage 严格按文件头魔数和尺寸头校验 JPEG / PNG / WebP，拒绝伪装或超大分辨率图片。
func validateAvatarImage(declaredMIME string, raw []byte) (mime string, ext string, err error) {
	if len(raw) == 0 {
		return "", "", errAvatarInvalidData
	}
	if len(raw) > MaxAvatarBytes {
		return "", "", errAvatarTooLarge
	}

	var w, h int
	switch {
	case isPNG(raw):
		cfg, fmtName, decErr := image.DecodeConfig(bytes.NewReader(raw))
		if decErr != nil || fmtName != "png" {
			return "", "", errAvatarInvalidData
		}
		mime, ext, w, h = "image/png", ".png", cfg.Width, cfg.Height
	case isJPEG(raw):
		cfg, fmtName, decErr := image.DecodeConfig(bytes.NewReader(raw))
		if decErr != nil || fmtName != "jpeg" {
			return "", "", errAvatarInvalidData
		}
		mime, ext, w, h = "image/jpeg", ".jpg", cfg.Width, cfg.Height
	case isWebP(raw):
		ww, hh, ok := parseWebPDimensions(raw)
		if !ok {
			return "", "", errAvatarInvalidData
		}
		mime, ext, w, h = "image/webp", ".webp", ww, hh
	default:
		return "", "", errAvatarInvalidData
	}

	if declaredMIME != mime {
		return "", "", httpx.Validation(map[string]string{"contentType": "图片格式与内容不匹配"})
	}
	if w <= 0 || h <= 0 || w > maxAvatarDimension || h > maxAvatarDimension {
		return "", "", errAvatarDimExceeded
	}
	return mime, ext, nil
}

func isPNG(b []byte) bool {
	return len(b) >= 8 && bytes.Equal(b[:8], []byte{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'})
}

func isJPEG(b []byte) bool {
	return len(b) >= 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff
}

func isWebP(b []byte) bool {
	return len(b) >= 16 && string(b[0:4]) == "RIFF" && string(b[8:12]) == "WEBP"
}

// parseWebPDimensions 解析 RIFF/WEBP 的 VP8 / VP8L / VP8X 尺寸头，无需额外第三方依赖。
func parseWebPDimensions(b []byte) (int, int, bool) {
	if len(b) < 20 {
		return 0, 0, false
	}
	chunk := string(b[12:16])
	switch chunk {
	case "VP8 ":
		// 帧头位于偏移 20：3 字节帧标签 + 3 字节同步码 (9d 01 2a) + 2 字节宽 + 2 字节高
		if len(b) < 30 || b[23] != 0x9d || b[24] != 0x01 || b[25] != 0x2a {
			return 0, 0, false
		}
		w := int(binary.LittleEndian.Uint16(b[26:28]) & 0x3fff)
		h := int(binary.LittleEndian.Uint16(b[28:30]) & 0x3fff)
		return w, h, w > 0 && h > 0
	case "VP8L":
		// 签名 0x2f 位于偏移 20，后跟 28 bit (14 bit width-1 + 14 bit height-1)
		if len(b) < 25 || b[20] != 0x2f {
			return 0, 0, false
		}
		bits := binary.LittleEndian.Uint32(b[21:25])
		w := int(bits&0x3fff) + 1
		h := int((bits>>14)&0x3fff) + 1
		return w, h, w > 0 && h > 0
	case "VP8X":
		// 偏移 24..26 为 24-bit width-1，偏移 27..29 为 24-bit height-1
		if len(b) < 30 {
			return 0, 0, false
		}
		w := (int(b[24]) | int(b[25])<<8 | int(b[26])<<16) + 1
		h := (int(b[27]) | int(b[28])<<8 | int(b[29])<<16) + 1
		return w, h, w > 0 && h > 0
	default:
		return 0, 0, false
	}
}
