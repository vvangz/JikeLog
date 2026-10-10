// Package pusher 向 App 发送系统通知（ADR-008）：极光推送，或在未开通推送的环境只记日志。
package pusher

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"time"
)

// MaxTokens 为一次推送的设备数上限（极光单次最多 1000 个 registration_id）。
const MaxTokens = 1000

// ChannelReminders 为 App 中提醒通知的 Android 通知渠道 ID（App 启动时创建）。
const ChannelReminders = "memo_reminders"

// openApp 为点按通知后打开 App 的 Intent（极光要求 API 推送显式指定）。
const openApp = "intent:#Intent;action=android.intent.action.MAIN;end"

// ErrNoTarget 表示推送标识均已失效，没有可送达的设备（重试无意义）。
var ErrNoTarget = errors.New("没有可送达的设备")

// Message 为一条通知。
type Message struct {
	Tokens []string
	Title  string
	Body   string
	// Extras 随通知送达 App，用于点按后打开对应内容。
	Extras map[string]string
	// TTL 为设备离线时通知的保留时长。
	TTL time.Duration
}

// Pusher 发送通知。
type Pusher interface {
	Push(ctx context.Context, m Message) error
}

// retryable 包装可以稍后重试的错误（网络错误、限流、通道服务端错误）。
type retryable struct{ err error }

func (r retryable) Error() string { return r.err.Error() }
func (r retryable) Unwrap() error { return r.err }

// Retryable 把错误标记为可以稍后重试。
func Retryable(err error) error { return retryable{err} }

// IsRetryable 报告错误是否值得稍后重试。
func IsRetryable(err error) bool {
	var r retryable
	return errors.As(err, &r)
}

// Log 只把推送写入日志（不记录标题与正文），用于没有开通推送服务的环境。
type Log struct {
	Logger *slog.Logger
}

// Push 记录一条推送。
func (l Log) Push(ctx context.Context, m Message) error {
	l.Logger.InfoContext(ctx, "push (log only)", "devices", len(m.Tokens))
	return nil
}

// JPushConfig 为极光推送配置。
type JPushConfig struct {
	AppKey       string
	MasterSecret string
	Endpoint     string
}

// JPush 通过极光推送 REST API v3 发送通知。
type JPush struct {
	cfg    JPushConfig
	client *http.Client
}

// NewJPush 创建极光推送客户端。client 为空时使用 10 秒超时的默认客户端。
func NewJPush(cfg JPushConfig, client *http.Client) *JPush {
	if client == nil {
		client = &http.Client{Timeout: 10 * time.Second}
	}
	return &JPush{cfg: cfg, client: client}
}

type jpushRequest struct {
	Platform     []string          `json:"platform"`
	Audience     jpushAudience     `json:"audience"`
	Notification jpushNotification `json:"notification"`
	Options      jpushOptions      `json:"options"`
}

type jpushAudience struct {
	RegistrationID []string `json:"registration_id"`
}

type jpushNotification struct {
	Android jpushAndroid `json:"android"`
}

type jpushAndroid struct {
	Alert     string            `json:"alert"`
	Title     string            `json:"title"`
	ChannelID string            `json:"channel_id"`
	Intent    map[string]string `json:"intent"`
	Extras    map[string]string `json:"extras,omitempty"`
}

type jpushOptions struct {
	TimeToLive int64 `json:"time_to_live"`
	// Classification 为 1 表示系统消息（提醒），厂商通道按重要通知下发。
	Classification int `json:"classification"`
}

type jpushError struct {
	Error struct {
		Code    int    `json:"code"`
		Message string `json:"message"`
	} `json:"error"`
}

// jpushNoTarget 为极光"没有满足条件的推送目标"错误码。
const jpushNoTarget = 1011

// Push 发送一条 Android 通知。
func (j *JPush) Push(ctx context.Context, m Message) error {
	if len(m.Tokens) > MaxTokens {
		return fmt.Errorf("一次最多推送 %d 台设备", MaxTokens)
	}
	body, err := json.Marshal(jpushRequest{
		Platform: []string{"android"},
		Audience: jpushAudience{RegistrationID: m.Tokens},
		Notification: jpushNotification{Android: jpushAndroid{
			Alert: m.Body, Title: m.Title, ChannelID: ChannelReminders,
			Intent: map[string]string{"url": openApp}, Extras: m.Extras,
		}},
		Options: jpushOptions{TimeToLive: int64(m.TTL / time.Second), Classification: 1},
	})
	if err != nil {
		return fmt.Errorf("编码推送请求失败: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, j.cfg.Endpoint, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("创建推送请求失败: %w", err)
	}
	req.SetBasicAuth(j.cfg.AppKey, j.cfg.MasterSecret)
	req.Header.Set("Content-Type", "application/json")
	resp, err := j.client.Do(req)
	if err != nil {
		return retryable{fmt.Errorf("调用极光推送失败: %w", err)}
	}
	defer func() { _ = resp.Body.Close() }()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 64<<10))
	if resp.StatusCode == http.StatusOK {
		return nil
	}
	var je jpushError
	_ = json.Unmarshal(raw, &je)
	err = fmt.Errorf("极光推送返回 HTTP %d（错误码 %d：%s）", resp.StatusCode, je.Error.Code, je.Error.Message)
	switch {
	case je.Error.Code == jpushNoTarget:
		return fmt.Errorf("%w: %w", ErrNoTarget, err)
	case resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode >= http.StatusInternalServerError:
		return retryable{err}
	default:
		return err
	}
}
