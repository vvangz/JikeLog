package config

import (
	"encoding/base64"
	"errors"
	"fmt"
	"net/netip"
	"net/url"
	"slices"
	"strings"
	"time"
)

const (
	minJWTSecretLen = 32
	maxAccessTTL    = time.Hour
)

var (
	validEnvs         = []string{EnvDevelopment, EnvTest, EnvStaging, EnvProduction}
	validLogLevels    = []string{"debug", "info", "warn", "error"}
	validLogFormats   = []string{"json", "text"}
	validSMSProviders = []string{SMSProviderMock, SMSProviderAliyun}
	validCaptchas     = []string{CaptchaProviderNone, CaptchaProviderAliyun}
	validKMS          = []string{KMSProviderLocal, KMSProviderAliyun}
)

// Validate 校验配置取值，返回所有错误的合并结果。错误信息不包含密钥、密码等敏感值。
func (c Config) Validate() error {
	var errs []error
	if !slices.Contains(validEnvs, c.Env) {
		errs = append(errs, fmt.Errorf("JIKELOG_ENV=%q 不合法，可选 %v", c.Env, validEnvs))
	}
	errs = append(errs, c.validateHTTP()...)
	if !slices.Contains(validLogLevels, c.Log.Level) {
		errs = append(errs, fmt.Errorf("JIKELOG_LOG_LEVEL=%q 不合法，可选 %v", c.Log.Level, validLogLevels))
	}
	if !slices.Contains(validLogFormats, c.Log.Format) {
		errs = append(errs, fmt.Errorf("JIKELOG_LOG_FORMAT=%q 不合法，可选 %v", c.Log.Format, validLogFormats))
	}
	errs = append(errs, c.validateStores()...)
	errs = append(errs, c.validateAuth()...)
	errs = append(errs, c.validateCrypto()...)
	errs = append(errs, c.validateStorage()...)
	return errors.Join(errs...)
}

func (c Config) validateHTTP() []error {
	var errs []error
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
	if c.IsProduction() && len(c.HTTP.TrustedProxies) == 0 {
		errs = append(errs, errors.New("生产环境必须设置 JIKELOG_HTTP_TRUSTED_PROXIES（反向代理地址），否则所有请求的客户端 IP 都相同，限流会误伤全部用户"))
	}
	errs = append(errs, c.validateCORSOrigins()...)
	return errs
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

// validateCORSOrigins 要求每项都是不带路径的 scheme://host[:port]；不允许通配符，生产环境只允许 https。
func (c Config) validateCORSOrigins() []error {
	var errs []error
	for _, o := range c.HTTP.CORSOrigins {
		if !isOrigin(o) {
			errs = append(errs, fmt.Errorf("JIKELOG_HTTP_CORS_ORIGINS 中 %q 不是合法来源（形如 https://admin.example.com）", o))
			continue
		}
		if c.IsProduction() && !strings.HasPrefix(o, "https://") {
			errs = append(errs, fmt.Errorf("生产环境 JIKELOG_HTTP_CORS_ORIGINS 只允许 https 来源：%q", o))
		}
	}
	return errs
}

func isOrigin(o string) bool {
	u, err := url.Parse(o)
	return err == nil && (u.Scheme == "http" || u.Scheme == "https") && u.Host != "" &&
		u.Path == "" && u.RawQuery == "" && u.Fragment == "" && u.User == nil
}

func (c Config) validateStores() []error {
	var errs []error
	if c.DB.URL == "" {
		errs = append(errs, errors.New("JIKELOG_DB_URL 不能为空"))
	} else if !hasScheme(c.DB.URL, "postgres", "postgresql") {
		errs = append(errs, errors.New("JIKELOG_DB_URL 必须是 postgres://user:pass@host:port/db 形式"))
	}
	if c.DB.MaxConns <= 0 {
		errs = append(errs, errors.New("JIKELOG_DB_MAX_CONNS 必须大于 0"))
	}
	if c.Redis.URL == "" {
		errs = append(errs, errors.New("JIKELOG_REDIS_URL 不能为空"))
	} else if !hasScheme(c.Redis.URL, "redis", "rediss") {
		errs = append(errs, errors.New("JIKELOG_REDIS_URL 必须是 redis:// 或 rediss:// 形式"))
	}
	return errs
}

func (c Config) validateAuth() []error {
	var errs []error
	switch {
	case c.Auth.JWTSecret == "":
		errs = append(errs, errors.New("JIKELOG_AUTH_JWT_SECRET 不能为空"))
	case len(c.Auth.JWTSecret) < minJWTSecretLen:
		errs = append(errs, fmt.Errorf("JIKELOG_AUTH_JWT_SECRET 至少 %d 字节", minJWTSecretLen))
	case c.IsDeployed() && strings.Contains(c.Auth.JWTSecret, "change-me"):
		errs = append(errs, errors.New("staging / production 环境不能使用示例中的 JIKELOG_AUTH_JWT_SECRET（仓库公开，任何人都能用它伪造令牌）"))
	}
	if c.Auth.JWTPreviousSecret != "" && len(c.Auth.JWTPreviousSecret) < minJWTSecretLen {
		errs = append(errs, fmt.Errorf("JIKELOG_AUTH_JWT_PREVIOUS_SECRET 至少 %d 字节", minJWTSecretLen))
	}
	if c.Auth.AccessTTL <= 0 || c.Auth.AccessTTL > maxAccessTTL {
		errs = append(errs, fmt.Errorf("JIKELOG_AUTH_ACCESS_TTL 必须在 (0, %v] 之间", maxAccessTTL))
	}
	if c.Auth.RefreshTTL <= c.Auth.AccessTTL {
		errs = append(errs, errors.New("JIKELOG_AUTH_REFRESH_TTL 必须大于 JIKELOG_AUTH_ACCESS_TTL"))
	}
	if !slices.Contains(validSMSProviders, c.SMS.Provider) {
		errs = append(errs, fmt.Errorf("JIKELOG_SMS_PROVIDER=%q 不合法，可选 %v", c.SMS.Provider, validSMSProviders))
	}
	if c.IsDeployed() && c.SMS.Provider == SMSProviderMock {
		errs = append(errs, errors.New("staging / production 环境不能使用模拟短信通道（JIKELOG_SMS_PROVIDER=mock）"))
	}
	if !slices.Contains(validCaptchas, c.Captcha.Provider) {
		errs = append(errs, fmt.Errorf("JIKELOG_CAPTCHA_PROVIDER=%q 不合法，可选 %v", c.Captcha.Provider, validCaptchas))
	}
	if c.IsDeployed() && c.Captcha.Provider == CaptchaProviderNone {
		errs = append(errs, errors.New("staging / production 环境必须启用人机验证（JIKELOG_CAPTCHA_PROVIDER）"))
	}
	return errs
}

func (c Config) validateCrypto() []error {
	var errs []error
	switch {
	case c.E2E.PrivateKey == "":
		errs = append(errs, errors.New("JIKELOG_E2E_PRIVATE_KEY 不能为空（工作日志传输加密私钥）"))
	case !isKey32(c.E2E.PrivateKey):
		errs = append(errs, errors.New("JIKELOG_E2E_PRIVATE_KEY 必须是 base64 编码的 32 字节"))
	case c.IsDeployed() && c.E2E.PrivateKey == DevE2EPrivateKey:
		errs = append(errs, errors.New("staging / production 环境不能使用示例中的 JIKELOG_E2E_PRIVATE_KEY"))
	}
	if c.E2E.PreviousPrivateKey != "" && !isKey32(c.E2E.PreviousPrivateKey) {
		errs = append(errs, errors.New("JIKELOG_E2E_PREVIOUS_PRIVATE_KEY 必须是 base64 编码的 32 字节"))
	}
	if !slices.Contains(validKMS, c.KMS.Provider) {
		errs = append(errs, fmt.Errorf("JIKELOG_KMS_PROVIDER=%q 不合法，可选 %v", c.KMS.Provider, validKMS))
	}
	if c.KMS.Provider == KMSProviderLocal {
		switch {
		case !isKey32(c.KMS.LocalMasterKey):
			errs = append(errs, errors.New("JIKELOG_KMS_LOCAL_MASTER_KEY 必须是 base64 编码的 32 字节"))
		case c.IsDeployed() && c.KMS.LocalMasterKey == DevKMSMasterKey:
			errs = append(errs, errors.New("staging / production 环境不能使用示例中的 JIKELOG_KMS_LOCAL_MASTER_KEY"))
		}
	}
	return errs
}

func (c Config) validateStorage() []error {
	var errs []error
	s := c.Storage
	if !isOrigin(s.Endpoint) {
		errs = append(errs, errors.New("JIKELOG_STORAGE_ENDPOINT 必须是 http(s)://host[:port] 形式"))
	}
	if s.PublicEndpoint != "" && !isOrigin(s.PublicEndpoint) {
		errs = append(errs, errors.New("JIKELOG_STORAGE_PUBLIC_ENDPOINT 必须是 http(s)://host[:port] 形式"))
	}
	if c.IsProduction() && !strings.HasPrefix(s.PresignEndpoint(), "https://") {
		errs = append(errs, errors.New("生产环境对象存储的公开地址必须使用 https"))
	}
	if strings.TrimSpace(s.Bucket) == "" {
		errs = append(errs, errors.New("JIKELOG_STORAGE_BUCKET 不能为空"))
	}
	if s.AccessKey == "" || s.SecretKey == "" {
		errs = append(errs, errors.New("JIKELOG_STORAGE_ACCESS_KEY 与 JIKELOG_STORAGE_SECRET_KEY 不能为空"))
	}
	if c.Attachment.MaxSize <= 0 {
		errs = append(errs, errors.New("JIKELOG_ATTACHMENT_MAX_SIZE 必须大于 0"))
	}
	if c.Attachment.Quota < c.Attachment.MaxSize {
		errs = append(errs, errors.New("JIKELOG_ATTACHMENT_QUOTA 不能小于单个附件上限"))
	}
	return errs
}

// isKey32 报告 s 是否为 base64 编码的 32 字节密钥；不回显内容。
func isKey32(s string) bool {
	raw, err := base64.StdEncoding.DecodeString(s)
	return err == nil && len(raw) == 32
}

// hasScheme 只检查协议与主机，错误信息中不回显整串 URL（可能含密码）。
func hasScheme(raw string, schemes ...string) bool {
	u, err := url.Parse(raw)
	return err == nil && slices.Contains(schemes, u.Scheme) && u.Host != ""
}

func parseIPOrPrefix(s string) (netip.Prefix, error) {
	if addr, err := netip.ParseAddr(s); err == nil {
		return netip.PrefixFrom(addr, addr.BitLen()), nil
	}
	return netip.ParsePrefix(s)
}
