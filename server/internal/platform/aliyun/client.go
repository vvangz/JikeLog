// Package aliyun 调用阿里云 RPC 风格 OpenAPI（V3 签名 ACS3-HMAC-SHA256）。
// 只实现短信认证与验证码 2.0 用到的最小子集，避免引入官方 SDK 的大量依赖。
package aliyun

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"
)

const (
	algorithm   = "ACS3-HMAC-SHA256"
	formType    = "application/x-www-form-urlencoded"
	maxRespBody = 64 << 10
	// maxErrBody 为错误信息中附带的响应原文长度（网关错误页等没有 Code 时用于排查）
	maxErrBody = 256
)

// Credentials 为 RAM 用户的 AccessKey。
type Credentials struct {
	AccessKeyID     string
	AccessKeySecret string
}

// APIError 为阿里云返回的业务错误或 HTTP 错误。
type APIError struct {
	HTTPStatus int
	Code       string
	Message    string
	RequestID  string
}

func (e *APIError) Error() string {
	return fmt.Sprintf("阿里云接口返回 HTTP %d（%s：%s，RequestId=%s）", e.HTTPStatus, e.Code, e.Message, e.RequestID)
}

// ServerSide 报告错误是否源于阿里云服务端（5xx）。
func (e *APIError) ServerSide() bool { return e.HTTPStatus >= http.StatusInternalServerError }

// transportError 表示请求没有得到阿里云的完整响应（连接失败、超时、读取中断）。
type transportError struct{ err error }

func (t transportError) Error() string { return t.err.Error() }
func (t transportError) Unwrap() error { return t.err }

// IsTransport 报告错误是否为网络层失败（没有得到阿里云的完整响应）。
func IsTransport(err error) bool {
	var t transportError
	return errors.As(err, &t)
}

// Client 调用阿里云 RPC 风格 OpenAPI。
type Client struct {
	creds  Credentials
	client *http.Client
	now    func() time.Time
	// scheme 仅供测试替换为 http
	scheme string
}

// NewClient 创建客户端。client 为空时使用 5 秒超时的默认客户端（验证码接口在用户等待的请求链路上）。
func NewClient(creds Credentials, client *http.Client) *Client {
	if client == nil {
		client = &http.Client{Timeout: 5 * time.Second}
	}
	return &Client{creds: creds, client: client, now: time.Now, scheme: "https"}
}

// Request 为一次 RPC 调用。
type Request struct {
	Host    string
	Action  string
	Version string
	// Params 以表单形式放在请求体中（RPC 接口不建议使用 JSON 请求体）
	Params url.Values
}

// Call 发起调用，成功（HTTP 200）时把响应体解码到 out。
func (c *Client) Call(ctx context.Context, r Request, out any) error {
	body := []byte(encodeRFC3986(r.Params))
	nonce, err := randomNonce()
	if err != nil {
		return err
	}
	headers := map[string]string{
		"host":                  r.Host,
		"content-type":          formType,
		"x-acs-action":          r.Action,
		"x-acs-version":         r.Version,
		"x-acs-date":            c.now().UTC().Format("2006-01-02T15:04:05Z"),
		"x-acs-signature-nonce": nonce,
		"x-acs-content-sha256":  sha256Hex(body),
	}
	auth := authorization(c.creds, http.MethodPost, "/", "", headers, body)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.scheme+"://"+r.Host+"/", bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("创建阿里云请求失败: %w", err)
	}
	for k, v := range headers {
		if k != "host" {
			req.Header.Set(k, v)
		}
	}
	req.Header.Set("Authorization", auth)
	resp, err := c.client.Do(req)
	if err != nil {
		return transportError{fmt.Errorf("调用阿里云 %s 失败: %w", r.Action, err)}
	}
	defer func() { _ = resp.Body.Close() }()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, maxRespBody))
	if err != nil {
		return transportError{fmt.Errorf("读取阿里云 %s 响应失败: %w", r.Action, err)}
	}
	if resp.StatusCode != http.StatusOK {
		var e struct {
			Code, Message string
			RequestID     string `json:"RequestId"`
		}
		_ = json.Unmarshal(raw, &e)
		if e.Code == "" && e.Message == "" {
			e.Message = string(raw[:min(len(raw), maxErrBody)])
		}
		return &APIError{HTTPStatus: resp.StatusCode, Code: e.Code, Message: e.Message, RequestID: e.RequestID}
	}
	if err := json.Unmarshal(raw, out); err != nil {
		return fmt.Errorf("解析阿里云 %s 响应失败: %w", r.Action, err)
	}
	return nil
}

// authorization 按 V3 签名规则计算 Authorization 头。headers 的键须为小写，且只包含参与签名的头
// （host、content-type 与 x-acs-*）。
func authorization(creds Credentials, method, uri, query string, headers map[string]string, body []byte) string {
	names := make([]string, 0, len(headers))
	for k := range headers {
		names = append(names, k)
	}
	sort.Strings(names)
	var canonHeaders strings.Builder
	for _, k := range names {
		canonHeaders.WriteString(k + ":" + strings.TrimSpace(headers[k]) + "\n")
	}
	signed := strings.Join(names, ";")
	canonical := strings.Join([]string{method, uri, query, canonHeaders.String(), signed, sha256Hex(body)}, "\n")
	toSign := algorithm + "\n" + sha256Hex([]byte(canonical))
	mac := hmac.New(sha256.New, []byte(creds.AccessKeySecret))
	mac.Write([]byte(toSign))
	sig := hex.EncodeToString(mac.Sum(nil))
	return fmt.Sprintf("%s Credential=%s,SignedHeaders=%s,Signature=%s", algorithm, creds.AccessKeyID, signed, sig)
}

// encodeRFC3986 按名称升序编码参数：空格为 %20，只保留字母、数字与 -_.~ 不编码。
func encodeRFC3986(v url.Values) string {
	keys := make([]string, 0, len(v))
	for k := range v {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var b strings.Builder
	for _, k := range keys {
		for _, val := range v[k] {
			if b.Len() > 0 {
				b.WriteByte('&')
			}
			b.WriteString(percentEncode(k) + "=" + percentEncode(val))
		}
	}
	return b.String()
}

// rfc3986 修正 url.QueryEscape 与 RFC3986 的差异：QueryEscape 把空格编码为 +、不编码 *。
var rfc3986 = strings.NewReplacer("+", "%20", "*", "%2A")

func percentEncode(s string) string { return rfc3986.Replace(url.QueryEscape(s)) }

func sha256Hex(b []byte) string {
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}

func randomNonce() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("生成签名随机数失败: %w", err)
	}
	return hex.EncodeToString(b), nil
}
