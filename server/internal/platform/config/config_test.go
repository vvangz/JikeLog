package config

import (
	"testing"
	"time"
)

func TestLoadFromDefaults(t *testing.T) {
	cfg, err := LoadFrom(map[string]string{})
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
}

func TestLoadFromOverrides(t *testing.T) {
	cfg, err := LoadFrom(map[string]string{
		"JIKELOG_ENV":                   "production",
		"JIKELOG_HTTP_ADDR":             "127.0.0.1:9000",
		"JIKELOG_HTTP_SHUTDOWN_TIMEOUT": "3s",
		"JIKELOG_HTTP_TRUSTED_PROXIES":  " 10.0.0.1, 10.0.0.2 ,",
		"JIKELOG_LOG_LEVEL":             "debug",
		"JIKELOG_LOG_FORMAT":            "text",
	})
	if err != nil {
		t.Fatalf("LoadFrom() error = %v", err)
	}
	if !cfg.IsProduction() {
		t.Error("IsProduction() = false, want true")
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
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if _, err := LoadFrom(tt.env); err == nil {
				t.Fatal("LoadFrom() error = nil, want error")
			}
		})
	}
}
