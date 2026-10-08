// Package config 从环境变量加载并校验服务配置，所有变量以 JIKELOG_ 为前缀。
package config

import (
	"errors"
	"fmt"
	"net/netip"
	"slices"
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

const envPrefix = "JIKELOG_"

var (
	validEnvs       = []string{EnvDevelopment, EnvTest, EnvStaging, EnvProduction}
	validLogLevels  = []string{"debug", "info", "warn", "error"}
	validLogFormats = []string{"json", "text"}
)

// Config 为服务完整配置。
type Config struct {
	Env  string `env:"ENV" envDefault:"development"`
	HTTP HTTP   `envPrefix:"HTTP_"`
	Log  Log    `envPrefix:"LOG_"`
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
}

// Log 为日志配置。
type Log struct {
	Level  string `env:"LEVEL" envDefault:"info"`
	Format string `env:"FORMAT" envDefault:"json"`
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
	if err := cfg.Validate(); err != nil {
		return Config{}, fmt.Errorf("配置校验失败: %w", err)
	}
	return cfg, nil
}

// Validate 校验配置取值，返回所有错误的合并结果。
func (c Config) Validate() error {
	var errs []error
	if !slices.Contains(validEnvs, c.Env) {
		errs = append(errs, fmt.Errorf("JIKELOG_ENV=%q 不合法，可选 %v", c.Env, validEnvs))
	}
	if strings.TrimSpace(c.HTTP.Addr) == "" {
		errs = append(errs, errors.New("JIKELOG_HTTP_ADDR 不能为空"))
	}
	timeouts := []struct {
		name string
		d    time.Duration
	}{
		{"READ_TIMEOUT", c.HTTP.ReadTimeout}, {"WRITE_TIMEOUT", c.HTTP.WriteTimeout},
		{"IDLE_TIMEOUT", c.HTTP.IdleTimeout}, {"SHUTDOWN_TIMEOUT", c.HTTP.ShutdownTimeout},
	}
	for _, t := range timeouts {
		if t.d <= 0 {
			errs = append(errs, fmt.Errorf("JIKELOG_HTTP_%s 必须大于 0", t.name))
		}
	}
	errs = append(errs, c.validateTrustedProxies()...)
	if !slices.Contains(validLogLevels, c.Log.Level) {
		errs = append(errs, fmt.Errorf("JIKELOG_LOG_LEVEL=%q 不合法，可选 %v", c.Log.Level, validLogLevels))
	}
	if !slices.Contains(validLogFormats, c.Log.Format) {
		errs = append(errs, fmt.Errorf("JIKELOG_LOG_FORMAT=%q 不合法，可选 %v", c.Log.Format, validLogFormats))
	}
	return errors.Join(errs...)
}

// validateTrustedProxies 校验每项为 IP 或 CIDR；生产环境禁止前缀为 0 的网段（等于信任所有来源）。
func (c Config) validateTrustedProxies() []error {
	var errs []error
	for _, p := range c.HTTP.TrustedProxies {
		prefix, err := parseIPOrPrefix(p)
		if err != nil {
			errs = append(errs, fmt.Errorf("JIKELOG_HTTP_TRUSTED_PROXIES 中 %q 不是合法的 IP 或 CIDR", p))
			continue
		}
		if c.IsProduction() && prefix.Bits() == 0 {
			errs = append(errs, fmt.Errorf("生产环境不允许 JIKELOG_HTTP_TRUSTED_PROXIES 包含 %s（会让任何客户端伪造来源 IP）", p))
		}
	}
	return errs
}

func parseIPOrPrefix(s string) (netip.Prefix, error) {
	if addr, err := netip.ParseAddr(s); err == nil {
		return netip.PrefixFrom(addr, addr.BitLen()), nil
	}
	return netip.ParsePrefix(s)
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
