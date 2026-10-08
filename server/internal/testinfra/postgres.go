// Package testinfra 为集成测试提供真实的 PostgreSQL：
// 每个测试二进制只启动一个容器并迁移一个模板库，每个测试从模板克隆出独立数据库，互不干扰。
//
// 设置 JIKELOG_TEST_PG_URL（指向可创建数据库的超级用户连接）时复用已有实例，不启动容器；
// 未设置且本机没有 Docker 时，相关测试会被跳过而不是失败；CI 设置 JIKELOG_TEST_REQUIRE_DOCKER=1，必定执行。
//
// 使用 Postgres 的测试包需要在 TestMain 中调用 Main，以便测试结束后停止容器。
package testinfra

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net/url"
	"os"
	"runtime"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/moby/moby/client"
	"github.com/testcontainers/testcontainers-go"
	tcpostgres "github.com/testcontainers/testcontainers-go/modules/postgres"

	"github.com/vvangz/JikeLog/server/internal/platform/config"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
)

const (
	pgImage      = "postgres:17-alpine"
	templateName = "jikelog_template"
	envPGURL     = "JIKELOG_TEST_PG_URL"
	envRequire   = "JIKELOG_TEST_REQUIRE_DOCKER"
)

var (
	pgOnce      sync.Once
	pgAdmin     string // 管理连接 URL（指向 postgres 库）
	pgErr       error
	pgSkipped   bool
	pgContainer testcontainers.Container
)

// Main 运行测试并在结束后停止本包启动的容器。用法：func TestMain(m *testing.M) { testinfra.Main(m) }
func Main(m *testing.M) {
	code := m.Run()
	if pgContainer != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		_ = pgContainer.Terminate(ctx)
		cancel()
	}
	os.Exit(code)
}

// Postgres 返回一个已迁移、仅供当前测试使用的数据库连接池，测试结束时自动删除该库。
func Postgres(t testing.TB) *pgxpool.Pool {
	t.Helper()
	pgOnce.Do(setupPostgres)
	if pgSkipped {
		t.Skip("未检测到 Docker 且未设置 " + envPGURL + "，跳过数据库集成测试")
	}
	if pgErr != nil {
		t.Fatalf("准备测试数据库失败: %v", pgErr)
	}

	ctx := context.Background()
	name := "t_" + randomHex(8)
	admin, err := pgx.Connect(ctx, pgAdmin)
	if err != nil {
		t.Fatalf("连接测试数据库实例失败: %v", err)
	}
	defer func() { _ = admin.Close(ctx) }()
	if _, err := admin.Exec(ctx, fmt.Sprintf("CREATE DATABASE %s TEMPLATE %s", name, templateName)); err != nil {
		t.Fatalf("创建测试数据库失败: %v", err)
	}

	pool, err := db.Open(ctx, config.DB{URL: withDatabase(pgAdmin, name), MaxConns: 10})
	if err != nil {
		t.Fatalf("连接测试数据库失败: %v", err)
	}
	t.Cleanup(func() {
		pool.Close()
		c, err := pgx.Connect(context.Background(), pgAdmin)
		if err != nil {
			return
		}
		defer func() { _ = c.Close(context.Background()) }()
		_, _ = c.Exec(context.Background(), fmt.Sprintf("DROP DATABASE IF EXISTS %s WITH (FORCE)", name))
	})
	return pool
}

func setupPostgres() {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()

	pgAdmin = os.Getenv(envPGURL)
	if pgAdmin == "" {
		if runtime.GOOS == "windows" {
			configureWindowsDocker()
		}
		if err := retry(3, time.Second, func() error { return dockerAvailable(ctx) }); err != nil {
			if os.Getenv(envRequire) == "1" {
				pgErr = fmt.Errorf("%s=1 但 Docker 不可用: %w", envRequire, err)
				return
			}
			pgSkipped = true
			return
		}
		ctr, err := tcpostgres.Run(ctx, pgImage,
			tcpostgres.WithDatabase("postgres"),
			tcpostgres.WithUsername("postgres"),
			tcpostgres.WithPassword("postgres"),
			tcpostgres.BasicWaitStrategies(),
		)
		if err != nil {
			pgErr = fmt.Errorf("启动 PostgreSQL 容器失败: %w", err)
			return
		}
		pgContainer = ctr
		pgAdmin, pgErr = ctr.ConnectionString(ctx, "sslmode=disable")
		if pgErr != nil {
			return
		}
	}
	pgErr = createTemplate(ctx)
}

func createTemplate(ctx context.Context) error {
	admin, err := pgx.Connect(ctx, pgAdmin)
	if err != nil {
		return fmt.Errorf("连接 PostgreSQL 失败: %w", err)
	}
	defer func() { _ = admin.Close(ctx) }()
	if _, err := admin.Exec(ctx, "DROP DATABASE IF EXISTS "+templateName+" WITH (FORCE)"); err != nil {
		return fmt.Errorf("清理模板库失败: %w", err)
	}
	if _, err := admin.Exec(ctx, "CREATE DATABASE "+templateName); err != nil {
		return fmt.Errorf("创建模板库失败: %w", err)
	}
	pool, err := db.Open(ctx, config.DB{URL: withDatabase(pgAdmin, templateName), MaxConns: 2})
	if err != nil {
		return err
	}
	// 模板库在被克隆时不能有活动连接，迁移完立即关闭
	defer pool.Close()
	_, err = db.Migrate(ctx, pool)
	return err
}

func dockerAvailable(ctx context.Context) (err error) {
	defer func() {
		if r := recover(); r != nil { // testcontainers 在找不到 Docker 时可能 panic
			err = fmt.Errorf("docker 客户端异常: %v", r)
		}
	}()
	cli, err := testcontainers.NewDockerClientWithOpts(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = cli.Close() }()
	_, err = cli.Info(ctx, client.InfoOptions{})
	return err
}

// configureWindowsDocker 适配 Docker Desktop for Windows，必须在首次调用 testcontainers 之前执行（其配置只读取一次）：
//   - Ryuk 无法就绪，关闭后容器改由 Main 在测试结束时显式停止；
//   - 多个测试包并行时 Docker 主机自动探测偶尔会落到不支持的 rootless 策略，直接指定命名管道。
func configureWindowsDocker() {
	if os.Getenv("TESTCONTAINERS_RYUK_DISABLED") == "" {
		_ = os.Setenv("TESTCONTAINERS_RYUK_DISABLED", "true")
	}
	if os.Getenv("DOCKER_HOST") == "" {
		_ = os.Setenv("DOCKER_HOST", "npipe:////./pipe/docker_engine")
	}
}

// retry 在多个测试包并行访问 Docker 时容忍偶发的连接失败。
func retry(attempts int, wait time.Duration, fn func() error) error {
	var err error
	for i := range attempts {
		if err = fn(); err == nil {
			return nil
		}
		if i < attempts-1 {
			time.Sleep(wait)
		}
	}
	return err
}

func withDatabase(raw, name string) string {
	u, err := url.Parse(raw)
	if err != nil {
		return raw
	}
	u.Path = "/" + name
	return u.String()
}

func randomHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
