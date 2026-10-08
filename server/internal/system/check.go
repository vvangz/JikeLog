// Package system 提供健康检查（存活/就绪探针）与系统信息接口。
package system

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/vvangz/JikeLog/server/internal/apigen"
)

// Checker 为一个外部依赖（数据库、缓存、对象存储等）的就绪检查。
type Checker interface {
	Name() string
	Check(ctx context.Context) error
}

type funcCheck struct {
	name string
	fn   func(context.Context) error
}

func (f funcCheck) Name() string                    { return f.name }
func (f funcCheck) Check(ctx context.Context) error { return f.fn(ctx) }

// NewCheck 用函数构造检查项。
func NewCheck(name string, fn func(context.Context) error) Checker {
	return funcCheck{name: name, fn: fn}
}

// 对外只暴露粗粒度原因，详细错误仅写日志，避免泄露内网地址等信息。
const (
	reasonUnavailable = "unavailable"
	reasonTimeout     = "timeout"
)

// runChecks 并发执行所有检查，结果按注册顺序返回。
//
// 检查使用独立于请求的 context：超时返回后检查 goroutine 可能仍在运行，
// 不能持有会被 gin 回收复用的 *gin.Context。
func runChecks(logger *slog.Logger, timeout time.Duration, checks []Checker, requestID string) []apigen.HealthCheck {
	results := make([]apigen.HealthCheck, len(checks))
	var wg sync.WaitGroup
	for i, c := range checks {
		wg.Add(1)
		go func() {
			defer wg.Done()
			results[i] = runOne(logger, timeout, c, requestID)
		}()
	}
	wg.Wait()
	return results
}

// runOne 在超时内等待检查结果；检查项忽略 ctx 或发生 panic 都不会拖住或击垮请求。
func runOne(logger *slog.Logger, timeout time.Duration, c Checker, requestID string) apigen.HealthCheck {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	done := make(chan error, 1) // 带缓冲：超时返回后检查结束时不会阻塞
	go func() {
		defer func() {
			if r := recover(); r != nil {
				done <- fmt.Errorf("check panicked: %v", r)
			}
		}()
		done <- c.Check(ctx)
	}()

	var err error
	select {
	case err = <-done:
	case <-ctx.Done():
		err = ctx.Err()
	}
	if err == nil {
		return apigen.HealthCheck{Name: c.Name(), Status: apigen.HealthCheckStatusUp}
	}
	logger.Warn("readiness check failed", "check", c.Name(), "request_id", requestID, "error", err)
	reason := reasonUnavailable
	if errors.Is(err, context.DeadlineExceeded) {
		reason = reasonTimeout
	}
	return apigen.HealthCheck{Name: c.Name(), Status: apigen.HealthCheckStatusDown, Error: &reason}
}
