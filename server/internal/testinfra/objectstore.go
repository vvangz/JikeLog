package testinfra

import (
	"context"
	"fmt"
	"os"
	"runtime"
	"sync"
	"testing"
	"time"

	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"

	"github.com/vvangz/JikeLog/server/internal/platform/config"
)

// 与 deploy/docker-compose.dev.yml 使用同一个 S3 兼容实现。
const (
	objImage     = "rustfs/rustfs:1.0.1"
	objAccessKey = "jikelog-test"
	objSecretKey = "jikelog-test-secret" //nolint:gosec // 仅用于测试容器
	// envS3Endpoint 指向已有的 S3 兼容服务时不启动容器（访问密钥同上）。
	envS3Endpoint = "JIKELOG_TEST_S3_ENDPOINT"
)

var (
	objOnce      sync.Once
	objEndpoint  string
	objErr       error
	objSkipped   bool
	objContainer testcontainers.Container
)

// ObjectStore 返回指向测试对象存储的配置，每个测试使用独立的存储桶（由调用方创建）。
func ObjectStore(t testing.TB) config.Storage {
	t.Helper()
	objOnce.Do(setupObjectStore)
	if objSkipped {
		t.Skip("未检测到 Docker 且未设置 " + envS3Endpoint + "，跳过对象存储集成测试")
	}
	if objErr != nil {
		t.Fatalf("准备测试对象存储失败: %v", objErr)
	}
	return config.Storage{
		Endpoint: objEndpoint, Region: "us-east-1", Bucket: "t-" + randomHex(6),
		AccessKey: objAccessKey, SecretKey: objSecretKey, PathStyle: true,
	}
}

func setupObjectStore() {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()
	if objEndpoint = os.Getenv(envS3Endpoint); objEndpoint != "" {
		return
	}
	if runtime.GOOS == "windows" {
		configureWindowsDocker()
	}
	if err := retry(3, time.Second, func() error { return dockerAvailable(ctx) }); err != nil {
		if os.Getenv(envRequire) == "1" {
			objErr = fmt.Errorf("%s=1 但 Docker 不可用: %w", envRequire, err)
			return
		}
		objSkipped = true
		return
	}
	// Windows 上随机映射的端口偶尔落在系统保留范围内（无法连接），失败时换一个端口重试
	var ctr testcontainers.Container
	err := retry(3, time.Second, func() error {
		c, err := testcontainers.Run(ctx, objImage,
			testcontainers.WithEnv(map[string]string{"RUSTFS_ACCESS_KEY": objAccessKey, "RUSTFS_SECRET_KEY": objSecretKey}),
			testcontainers.WithExposedPorts("9000/tcp"),
			testcontainers.WithWaitStrategy(wait.ForListeningPort("9000/tcp").WithStartupTimeout(time.Minute)),
		)
		if err != nil && c != nil {
			_ = c.Terminate(ctx)
		}
		ctr = c
		return err
	})
	if err != nil {
		objErr = fmt.Errorf("启动对象存储容器失败: %w", err)
		return
	}
	objContainer = ctr
	host, err := ctr.PortEndpoint(ctx, "9000/tcp", "http")
	if err != nil {
		objErr = fmt.Errorf("获取对象存储地址失败: %w", err)
		return
	}
	objEndpoint = host
}
