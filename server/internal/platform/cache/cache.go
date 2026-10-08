// Package cache 创建 Redis 客户端。业务键统一以 KeyPrefix 开头，便于与同实例上的其他数据区分。
package cache

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/vvangz/JikeLog/server/internal/platform/config"
)

// KeyPrefix 为本服务所有 Redis 键的前缀。
const KeyPrefix = "jk:"

const connectTimeout = 5 * time.Second

// Open 创建 Redis 客户端并确认可连接。
func Open(ctx context.Context, cfg config.Redis) (*redis.Client, error) {
	opts, err := redis.ParseURL(cfg.URL)
	if err != nil {
		// 不回显 URL：其中可能带密码
		return nil, errors.New("解析 JIKELOG_REDIS_URL 失败")
	}
	opts.DialTimeout = connectTimeout
	rdb := redis.NewClient(opts)
	pingCtx, cancel := context.WithTimeout(ctx, connectTimeout)
	defer cancel()
	if err := rdb.Ping(pingCtx).Err(); err != nil {
		_ = rdb.Close()
		return nil, fmt.Errorf("连接 Redis 失败: %w", err)
	}
	return rdb, nil
}
