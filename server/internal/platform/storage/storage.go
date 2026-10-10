// Package storage 封装 S3 兼容对象存储（生产为阿里云 OSS，开发为 RustFS）：
// 预签名直传直下，附件流量不经过 API 服务器。
package storage

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"

	"github.com/vvangz/JikeLog/server/internal/platform/config"
)

// ErrNotFound 表示对象不存在（客户端尚未上传）。
var ErrNotFound = errors.New("对象不存在")

// Upload 为预签名上传参数：客户端必须用 PUT 并原样带上 Headers。
type Upload struct {
	URL     string
	Headers map[string]string
	Expires time.Time
}

// Store 为对象存储。
type Store struct {
	bucket string
	// internal 用于服务端自身的访问（查询、删除）；public 只用于签名，生成客户端可访问的地址。
	internal *minio.Client
	public   *minio.Client
	now      func() time.Time
}

// New 由配置创建 Store。
func New(cfg config.Storage) (*Store, error) {
	internal, err := newClient(cfg.Endpoint, cfg)
	if err != nil {
		return nil, err
	}
	public, err := newClient(cfg.PresignEndpoint(), cfg)
	if err != nil {
		return nil, err
	}
	return &Store{bucket: cfg.Bucket, internal: internal, public: public, now: time.Now}, nil
}

func newClient(endpoint string, cfg config.Storage) (*minio.Client, error) {
	u, err := url.Parse(endpoint)
	if err != nil {
		return nil, fmt.Errorf("对象存储地址不合法: %w", err)
	}
	lookup := minio.BucketLookupDNS
	if cfg.PathStyle {
		lookup = minio.BucketLookupPath
	}
	c, err := minio.New(u.Host, &minio.Options{
		Creds:        credentials.NewStaticV4(cfg.AccessKey, cfg.SecretKey, ""),
		Secure:       u.Scheme == "https",
		Region:       cfg.Region, // 显式指定，签名时不再请求桶所在区域
		BucketLookup: lookup,
	})
	if err != nil {
		return nil, fmt.Errorf("创建对象存储客户端失败: %w", err)
	}
	return c, nil
}

// EnsureBucket 在桶不存在时创建（仅开发环境调用；生产环境的桶与权限由运维预先配置）。
func (s *Store) EnsureBucket(ctx context.Context) error {
	ok, err := s.internal.BucketExists(ctx, s.bucket)
	if err != nil {
		return fmt.Errorf("检查存储桶失败: %w", err)
	}
	if ok {
		return nil
	}
	if err := s.internal.MakeBucket(ctx, s.bucket, minio.MakeBucketOptions{}); err != nil {
		return fmt.Errorf("创建存储桶失败: %w", err)
	}
	return nil
}

// PresignPut 生成直传地址。Content-Length 与 Content-Type 纳入签名，客户端上传的大小必须与申请一致。
func (s *Store) PresignPut(ctx context.Context, key string, size int64, contentType string, ttl time.Duration) (Upload, error) {
	headers := http.Header{}
	headers.Set("Content-Type", contentType)
	headers.Set("Content-Length", strconv.FormatInt(size, 10))
	u, err := s.public.PresignHeader(ctx, http.MethodPut, s.bucket, key, ttl, nil, headers)
	if err != nil {
		return Upload{}, fmt.Errorf("生成上传地址失败: %w", err)
	}
	return Upload{
		URL:     u.String(),
		Headers: map[string]string{"Content-Type": contentType, "Content-Length": strconv.FormatInt(size, 10)},
		Expires: s.now().Add(ttl),
	}, nil
}

// PresignGet 生成下载地址，响应以附件形式返回（不在浏览器中内联渲染）。
func (s *Store) PresignGet(ctx context.Context, key string, ttl time.Duration) (string, time.Time, error) {
	params := url.Values{}
	params.Set("response-content-disposition", "attachment")
	u, err := s.public.PresignedGetObject(ctx, s.bucket, key, ttl, params)
	if err != nil {
		return "", time.Time{}, fmt.Errorf("生成下载地址失败: %w", err)
	}
	return u.String(), s.now().Add(ttl), nil
}

// Size 返回对象大小；对象不存在时返回 ErrNotFound。
func (s *Store) Size(ctx context.Context, key string) (int64, error) {
	info, err := s.internal.StatObject(ctx, s.bucket, key, minio.StatObjectOptions{})
	if err != nil {
		if minio.ToErrorResponse(err).Code == "NoSuchKey" || minio.ToErrorResponse(err).StatusCode == http.StatusNotFound {
			return 0, ErrNotFound
		}
		return 0, fmt.Errorf("查询对象失败: %w", err)
	}
	return info.Size, nil
}

// Delete 删除对象；对象不存在不算错误。
func (s *Store) Delete(ctx context.Context, key string) error {
	if err := s.internal.RemoveObject(ctx, s.bucket, key, minio.RemoveObjectOptions{}); err != nil {
		return fmt.Errorf("删除对象失败: %w", err)
	}
	return nil
}

// DeletePrefix 删除某个前缀下的全部对象（注销账号时清理该账号的附件）。
func (s *Store) DeletePrefix(ctx context.Context, prefix string) error {
	objects := s.internal.ListObjects(ctx, s.bucket, minio.ListObjectsOptions{Prefix: prefix, Recursive: true})
	for res := range s.internal.RemoveObjects(ctx, s.bucket, objects, minio.RemoveObjectsOptions{}) {
		if res.Err != nil {
			return fmt.Errorf("删除对象 %s 失败: %w", res.ObjectName, res.Err)
		}
	}
	return nil
}
