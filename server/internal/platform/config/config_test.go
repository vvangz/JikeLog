package config

import (
	"maps"
	"strings"
	"testing"
	"time"
)

// required 为通过校验所需的最少变量。
func required() map[string]string {
	return map[string]string{
		"JIKELOG_DB_URL":          "postgres://u:p@127.0.0.1:5432/jikelog",
		"JIKELOG_REDIS_URL":       "redis://:p@127.0.0.1:6379/0",
		"JIKELOG_AUTH_JWT_SECRET": strings.Repeat("s", 32),
	}
}

func with(extra map[string]string) map[string]string {
	env := required()
	maps.Copy(env, extra)
	return env
}

func TestLoadFromDefaults(t *testing.T) {
	cfg, err := LoadFrom(required())
	if err != nil {
		t.Fatalf("LoadFrom() error = %v", err)
	}
	if cfg.Env != EnvDevelopment {
		t.Errorf("Env = %q, want %q", cfg.Env, EnvDevelopment)
	}
	if cfg.HTTP.Addr != "127.0.0.1:8080" {
		t.Errorf("HTTP.Addr = %q, want 127.0.0.1:8080（默认只监听本机）", cfg.HTTP.Addr)
	}
	if cfg.HTTP.ShutdownTimeout != 8*time.Second {
		t.Errorf("ShutdownTimeout = %v, want 8s（需小于 Docker 默认 10s 停止宽限）", cfg.HTTP.ShutdownTimeout)
	}
	if cfg.Log.Level != "info" || cfg.Log.Format != "json" {
		t.Errorf("Log = %+v, want info/json", cfg.Log)
	}
	if len(cfg.HTTP.TrustedProxies) != 0 {
		t.Errorf("TrustedProxies = %v, want empty（默认不信任任何代理头）", cfg.HTTP.TrustedProxies)
	}
	if cfg.DB.MaxConns != 20 {
		t.Errorf("DB.MaxConns = %d, want 20", cfg.DB.MaxConns)
	}
	if cfg.Auth.AccessTTL != 15*time.Minute || cfg.Auth.RefreshTTL != 30*24*time.Hour {
		t.Errorf("Auth TTL = %v / %v, want 15m / 720h", cfg.Auth.AccessTTL, cfg.Auth.RefreshTTL)
	}
	if cfg.SMS.Provider != SMSProviderMock {
		t.Errorf("SMS.Provider = %q, want mock", cfg.SMS.Provider)
	}
	if len(cfg.HTTP.CORSOrigins) != 0 {
		t.Errorf("CORSOrigins = %v, want empty（默认不允许跨域）", cfg.HTTP.CORSOrigins)
	}
}

func TestLoadFromOverrides(t *testing.T) {
	cfg, err := LoadFrom(with(map[string]string{
		"JIKELOG_ENV":                   "staging",
		"JIKELOG_HTTP_ADDR":             "127.0.0.1:9000",
		"JIKELOG_HTTP_SHUTDOWN_TIMEOUT": "3s",
		"JIKELOG_HTTP_TRUSTED_PROXIES":  " 10.0.0.1, 10.0.0.2 ,",
		"JIKELOG_LOG_LEVEL":             "debug",
		"JIKELOG_LOG_FORMAT":            "text",
		"JIKELOG_HTTP_CORS_ORIGINS":     "https://admin.example.com, http://localhost:5173",
		"JIKELOG_DB_MAX_CONNS":          "5",
	}))
	if err != nil {
		t.Fatalf("LoadFrom() error = %v", err)
	}
	if cfg.IsProduction() || cfg.Env != EnvStaging {
		t.Errorf("Env = %q, want staging", cfg.Env)
	}
	if got := cfg.HTTP.CORSOrigins; len(got) != 2 || got[1] != "http://localhost:5173" {
		t.Errorf("CORSOrigins = %v", got)
	}
	if cfg.DB.MaxConns != 5 {
		t.Errorf("DB.MaxConns = %d, want 5", cfg.DB.MaxConns)
	}
	if cfg.HTTP.Addr != "127.0.0.1:9000" || cfg.HTTP.ShutdownTimeout != 3*time.Second {
		t.Errorf("HTTP = %+v", cfg.HTTP)
	}
	if got := cfg.HTTP.TrustedProxies; len(got) != 2 || got[1] != "10.0.0.2" {
		t.Errorf("TrustedProxies = %v", got)
	}
	if cfg.Log.Level != "debug" || cfg.Log.Format != "text" {
		t.Errorf("Log = %+v", cfg.Log)
	}
}

func TestLoadFromRejectsInvalidValues(t *testing.T) {
	tests := []struct {
		name string
		env  map[string]string
	}{
		{"未知环境", map[string]string{"JIKELOG_ENV": "prod"}},
		{"未知日志级别", map[string]string{"JIKELOG_LOG_LEVEL": "verbose"}},
		{"未知日志格式", map[string]string{"JIKELOG_LOG_FORMAT": "xml"}},
		{"超时为零", map[string]string{"JIKELOG_HTTP_READ_TIMEOUT": "0s"}},
		{"超时无法解析", map[string]string{"JIKELOG_HTTP_WRITE_TIMEOUT": "abc"}},
		{"监听地址为空", map[string]string{"JIKELOG_HTTP_ADDR": " "}},
		{"生产环境信任全部 IPv4 代理", map[string]string{"JIKELOG_ENV": "production", "JIKELOG_HTTP_TRUSTED_PROXIES": "10.0.0.1,0.0.0.0/0"}},
		{"生产环境信任全部 IPv6 代理", map[string]string{"JIKELOG_ENV": "production", "JIKELOG_HTTP_TRUSTED_PROXIES": "::/0"}},
		{"生产环境信任前缀为 0 的网段", map[string]string{"JIKELOG_ENV": "production", "JIKELOG_HTTP_TRUSTED_PROXIES": "0.0.0.0/00"}},
		{"代理地址非法", map[string]string{"JIKELOG_HTTP_TRUSTED_PROXIES": "10.0.0.1,not-an-ip"}},
		{"跨域来源带路径", map[string]string{"JIKELOG_HTTP_CORS_ORIGINS": "https://a.example.com/admin"}},
		{"跨域来源为通配符", map[string]string{"JIKELOG_HTTP_CORS_ORIGINS": "*"}},
		{"生产环境允许 http 跨域来源", map[string]string{"JIKELOG_ENV": "production", "JIKELOG_SMS_PROVIDER": "aliyun", "JIKELOG_HTTP_CORS_ORIGINS": "http://a.example.com"}},
		{"缺少数据库地址", map[string]string{"JIKELOG_DB_URL": ""}},
		{"数据库地址协议错误", map[string]string{"JIKELOG_DB_URL": "mysql://u:p@h/db"}},
		{"连接池为零", map[string]string{"JIKELOG_DB_MAX_CONNS": "0"}},
		{"缺少 Redis 地址", map[string]string{"JIKELOG_REDIS_URL": ""}},
		{"Redis 地址协议错误", map[string]string{"JIKELOG_REDIS_URL": "http://h:6379"}},
		{"缺少 JWT 密钥", map[string]string{"JIKELOG_AUTH_JWT_SECRET": ""}},
		{"JWT 密钥过短", map[string]string{"JIKELOG_AUTH_JWT_SECRET": "short"}},
		{"上一把 JWT 密钥过短", map[string]string{"JIKELOG_AUTH_JWT_PREVIOUS_SECRET": "short"}},
		{"Access Token 有效期过长", map[string]string{"JIKELOG_AUTH_ACCESS_TTL": "2h"}},
		{"Refresh Token 短于 Access Token", map[string]string{"JIKELOG_AUTH_REFRESH_TTL": "10m"}},
		{"未知短信通道", map[string]string{"JIKELOG_SMS_PROVIDER": "twilio"}},
		{"生产环境使用模拟短信", map[string]string{"JIKELOG_ENV": "production"}},
		{"生产环境使用占位密钥", map[string]string{"JIKELOG_ENV": "production", "JIKELOG_SMS_PROVIDER": "aliyun", "JIKELOG_AUTH_JWT_SECRET": "change-me-local-only-change-me-local-only"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if _, err := LoadFrom(with(tt.env)); err == nil {
				t.Fatal("LoadFrom() error = nil, want error")
			}
		})
	}
}

func TestProductionConfigAccepted(t *testing.T) {
	_, err := LoadFrom(with(map[string]string{
		"JIKELOG_ENV":               "production",
		"JIKELOG_SMS_PROVIDER":      "aliyun",
		"JIKELOG_HTTP_CORS_ORIGINS": "https://admin.example.com",
	}))
	if err != nil {
		t.Fatalf("LoadFrom() error = %v", err)
	}
}

func TestValidateReportsAllErrors(t *testing.T) {
	_, err := LoadFrom(map[string]string{"JIKELOG_LOG_LEVEL": "verbose"})
	if err == nil {
		t.Fatal("want error")
	}
	for _, name := range []string{"JIKELOG_DB_URL", "JIKELOG_REDIS_URL", "JIKELOG_AUTH_JWT_SECRET", "JIKELOG_LOG_LEVEL"} {
		if !strings.Contains(err.Error(), name) {
			t.Errorf("错误信息未包含 %s：%v", name, err)
		}
	}
}

func TestErrorsDoNotLeakSecrets(t *testing.T) {
	secret := "short-secret-value"
	_, err := LoadFrom(with(map[string]string{
		"JIKELOG_AUTH_JWT_SECRET": secret,
		"JIKELOG_DB_URL":          "mysql://user:db-password@h/db",
		"JIKELOG_REDIS_URL":       "http://:redis-password@h",
	}))
	if err == nil {
		t.Fatal("want error")
	}
	for _, s := range []string{secret, "db-password", "redis-password"} {
		if strings.Contains(err.Error(), s) {
			t.Errorf("错误信息泄露了敏感值 %q：%v", s, err)
		}
	}
}
