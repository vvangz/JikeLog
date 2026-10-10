// Package config 从环境变量加载并校验服务配置，所有变量以 JIKELOG_ 为前缀。
package config

import (
	"fmt"
	"strings"
	"time"

	"github.com/caarlos0/env/v11"
)

// 运行环境。
const (
	EnvDevelopment = "development"
	EnvTest        = "test"
	EnvStaging     = "staging"
	EnvProduction  = "production"
)

// 短信通道。
const (
	// SMSProviderMock 只把验证码写入日志，仅用于开发与测试，生产环境禁止使用。
	SMSProviderMock   = "mock"
	SMSProviderAliyun = "aliyun"
)

// 人机验证通道。
const (
	// CaptchaProviderNone 不做人机验证，仅用于开发与测试。
	CaptchaProviderNone   = "none"
	CaptchaProviderAliyun = "aliyun"
)

// KMS 通道。
const (
	// KMSProviderLocal 用环境变量中的主密钥包裹数据密钥，仅用于开发与测试。
	KMSProviderLocal  = "local"
	KMSProviderAliyun = "aliyun"
)

// 开发示例密钥：由固定字符串派生、随仓库公开（deploy/.env.example），staging / production 禁止使用。
const (
	DevE2EPrivateKey = "n8u4Sv4wcSFZAL1k17mtV7bg+ZhRoPOKQn/w5YPLLlM="
	DevKMSMasterKey  = "v4jRZ7eVOKo/cCE83/e8RMzA3QKJmK4Dqj4hg52Fik4="
)

const envPrefix = "JIKELOG_"

// Config 为服务完整配置。
type Config struct {
	Env     string  `env:"ENV" envDefault:"development"`
	HTTP    HTTP    `envPrefix:"HTTP_"`
	Log     Log     `envPrefix:"LOG_"`
	DB      DB      `envPrefix:"DB_"`
	Redis   Redis   `envPrefix:"REDIS_"`
	Auth    Auth    `envPrefix:"AUTH_"`
	SMS     SMS     `envPrefix:"SMS_"`
	Captcha Captcha `envPrefix:"CAPTCHA_"`
	E2E     E2E     `envPrefix:"E2E_"`
	KMS     KMS     `envPrefix:"KMS_"`
	Storage Storage `envPrefix:"STORAGE_"`
	// Attachment 为附件限制。
	Attachment Attachment `envPrefix:"ATTACHMENT_"`
}

// HTTP 为 HTTP 服务配置。
type HTTP struct {
	// Addr 默认只监听本机；容器内通过环境变量设为 ":8080"。
	Addr         string        `env:"ADDR" envDefault:"127.0.0.1:8080"`
	ReadTimeout  time.Duration `env:"READ_TIMEOUT" envDefault:"15s"`
	WriteTimeout time.Duration `env:"WRITE_TIMEOUT" envDefault:"30s"`
	IdleTimeout  time.Duration `env:"IDLE_TIMEOUT" envDefault:"60s"`
	// ShutdownTimeout 需小于容器编排的停止宽限期（Docker 默认 10s），否则会被 SIGKILL 打断。
	ShutdownTimeout time.Duration `env:"SHUTDOWN_TIMEOUT" envDefault:"8s"`
	// TrustedProxies 为可信反向代理地址；为空时不信任 X-Forwarded-For，防止伪造客户端 IP。
	TrustedProxies []string `env:"TRUSTED_PROXIES" envSeparator:","`
	// CORSOrigins 为允许跨域访问的来源（如管理后台域名）；为空时不返回任何 CORS 头。
	CORSOrigins []string `env:"CORS_ORIGINS" envSeparator:","`
}

// Log 为日志配置。
type Log struct {
	Level  string `env:"LEVEL" envDefault:"info"`
	Format string `env:"FORMAT" envDefault:"json"`
}

// DB 为 PostgreSQL 配置。
type DB struct {
	// URL 形如 postgres://user:pass@host:5432/db?sslmode=require
	URL      string `env:"URL"`
	MaxConns int32  `env:"MAX_CONNS" envDefault:"20"`
}

// Redis 为 Redis 配置。
type Redis struct {
	// URL 形如 redis://:pass@host:6379/0，TLS 连接使用 rediss://
	URL string `env:"URL"`
}

// Auth 为认证配置。
type Auth struct {
	// JWTSecret 为 Access Token 的 HMAC 签名密钥，至少 32 字节。
	JWTSecret string `env:"JWT_SECRET"`
	// JWTPreviousSecret 为轮换前的旧密钥，仅用于验签，让轮换期内签发的旧 token 继续有效。
	JWTPreviousSecret string        `env:"JWT_PREVIOUS_SECRET"`
	AccessTTL         time.Duration `env:"ACCESS_TTL" envDefault:"15m"`
	RefreshTTL        time.Duration `env:"REFRESH_TTL" envDefault:"720h"`
}

// SMS 为短信配置。
type SMS struct {
	Provider string `env:"PROVIDER" envDefault:"mock"`
}

// Captcha 为人机验证配置（发送短信前校验）。
type Captcha struct {
	Provider string `env:"PROVIDER" envDefault:"none"`
}

// E2E 为工作日志应用层传输加密配置（ADR-006）。
type E2E struct {
	// PrivateKey 为服务端静态 X25519 私钥（base64，32 字节），对应公钥编译进 App。
	PrivateKey string `env:"PRIVATE_KEY"`
	// PreviousPrivateKey 为轮换前的旧私钥，新旧版本 App 共存期间两把都可用。
	PreviousPrivateKey string `env:"PREVIOUS_PRIVATE_KEY"`
}

// KMS 为落库加密主密钥配置。
type KMS struct {
	Provider string `env:"PROVIDER" envDefault:"local"`
	// LocalMasterKey 为本地主密钥（base64，32 字节），Provider=local 时使用。
	LocalMasterKey string `env:"LOCAL_MASTER_KEY"`
}

// Storage 为 S3 兼容对象存储配置（生产为阿里云 OSS，开发为 RustFS）。
type Storage struct {
	// Endpoint 为服务端访问对象存储的地址，形如 https://oss-cn-beijing-internal.aliyuncs.com。
	Endpoint string `env:"ENDPOINT"`
	// PublicEndpoint 为客户端直传直下使用的地址，用于生成预签名 URL；为空时与 Endpoint 相同。
	PublicEndpoint string `env:"PUBLIC_ENDPOINT"`
	Region         string `env:"REGION" envDefault:"us-east-1"`
	Bucket         string `env:"BUCKET" envDefault:"jikelog"`
	AccessKey      string `env:"ACCESS_KEY"`
	SecretKey      string `env:"SECRET_KEY"`
	// PathStyle 为 true 时使用路径风格（RustFS、MinIO）；阿里云 OSS 需设为 false（虚拟主机风格）。
	PathStyle bool `env:"PATH_STYLE" envDefault:"true"`
}

// PresignEndpoint 返回生成预签名 URL 使用的地址。
func (s Storage) PresignEndpoint() string {
	if s.PublicEndpoint != "" {
		return s.PublicEndpoint
	}
	return s.Endpoint
}

// Attachment 为附件限制。
type Attachment struct {
	// MaxSize 为单个附件的最大字节数，默认 100MB。
	MaxSize int64 `env:"MAX_SIZE" envDefault:"104857600"`
	// Quota 为每个账号的附件总量上限，默认 2GB。
	Quota int64 `env:"QUOTA" envDefault:"2147483648"`
}

// Load 从进程环境变量加载配置。
func Load() (Config, error) {
	return parse(env.Options{Prefix: envPrefix})
}

// LoadFrom 从给定的变量表加载配置，便于测试。
func LoadFrom(environ map[string]string) (Config, error) {
	return parse(env.Options{Prefix: envPrefix, Environment: environ})
}

func parse(opts env.Options) (Config, error) {
	var cfg Config
	if err := env.ParseWithOptions(&cfg, opts); err != nil {
		return Config{}, fmt.Errorf("解析配置失败: %w", err)
	}
	cfg.HTTP.TrustedProxies = normalizeList(cfg.HTTP.TrustedProxies)
	cfg.HTTP.CORSOrigins = normalizeList(cfg.HTTP.CORSOrigins)
	if err := cfg.Validate(); err != nil {
		return Config{}, fmt.Errorf("配置校验失败: %w", err)
	}
	return cfg, nil
}

// normalizeList 去掉逗号分隔列表中的空白与空项。
func normalizeList(items []string) []string {
	out := make([]string, 0, len(items))
	for _, it := range items {
		if t := strings.TrimSpace(it); t != "" {
			out = append(out, t)
		}
	}
	return out
}

// IsProduction 报告是否为生产环境。
func (c Config) IsProduction() bool { return c.Env == EnvProduction }

// IsDeployed 报告是否为对外部署的环境（staging 与 production）：
// 这类环境禁止使用示例密钥、模拟短信与空人机验证。
func (c Config) IsDeployed() bool { return c.Env == EnvStaging || c.Env == EnvProduction }
