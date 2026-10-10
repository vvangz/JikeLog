package pusher

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

var msg = Message{
	Tokens: []string{"reg-1", "reg-2"},
	Title:  "备忘提醒",
	Body:   "10:00 有一条备忘",
	Extras: map[string]string{"memoId": "m1"},
	TTL:    time.Hour,
}

func TestJPushSendsNotification(t *testing.T) {
	var got map[string]any
	var auth string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth = r.Header.Get("Authorization")
		body, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(body, &got)
		_, _ = w.Write([]byte(`{"sendno":"0","msg_id":"18100287008546343"}`))
	}))
	defer srv.Close()

	p := NewJPush(JPushConfig{AppKey: "key", MasterSecret: "secret", Endpoint: srv.URL}, srv.Client())
	if err := p.Push(context.Background(), msg); err != nil {
		t.Fatal(err)
	}
	if auth != "Basic "+base64.StdEncoding.EncodeToString([]byte("key:secret")) {
		t.Errorf("auth = %q", auth)
	}
	audience := got["audience"].(map[string]any)["registration_id"].([]any)
	if len(audience) != 2 || audience[0] != "reg-1" {
		t.Errorf("audience = %v", audience)
	}
	android := got["notification"].(map[string]any)["android"].(map[string]any)
	if android["title"] != "备忘提醒" || android["alert"] != "10:00 有一条备忘" || android["channel_id"] != ChannelReminders {
		t.Errorf("android = %v", android)
	}
	if android["extras"].(map[string]any)["memoId"] != "m1" || android["intent"] == nil {
		t.Errorf("android = %v", android)
	}
	options := got["options"].(map[string]any)
	if options["time_to_live"] != float64(3600) || options["classification"] != float64(1) {
		t.Errorf("options = %v", options)
	}
}

func TestJPushErrors(t *testing.T) {
	cases := []struct {
		name      string
		status    int
		body      string
		retryable bool
		noTarget  bool
	}{
		{"没有可推送的设备", 400, `{"error":{"code":1011,"message":"cannot find user by this audience"}}`, false, true},
		{"鉴权失败", 401, `{"error":{"code":1004,"message":"Authen failed"}}`, false, false},
		{"频率超限", 429, `{"error":{"code":2002,"message":"Request times is more than limit"}}`, true, false},
		{"服务端错误", 502, `bad gateway`, true, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.WriteHeader(c.status)
				_, _ = w.Write([]byte(c.body))
			}))
			defer srv.Close()
			err := NewJPush(JPushConfig{AppKey: "k", MasterSecret: "secret", Endpoint: srv.URL}, srv.Client()).Push(context.Background(), msg)
			if err == nil {
				t.Fatal("want error")
			}
			if IsRetryable(err) != c.retryable || errors.Is(err, ErrNoTarget) != c.noTarget {
				t.Fatalf("err = %v retryable=%v", err, IsRetryable(err))
			}
			if strings.Contains(err.Error(), "secret") {
				t.Fatal("错误信息不应包含密钥")
			}
		})
	}
}

func TestJPushNetworkErrorIsRetryable(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
	url := srv.URL
	srv.Close()
	err := NewJPush(JPushConfig{AppKey: "k", MasterSecret: "s", Endpoint: url}, nil).Push(context.Background(), msg)
	if err == nil || !IsRetryable(err) {
		t.Fatalf("err = %v", err)
	}
}

func TestJPushRejectsTooManyTokens(t *testing.T) {
	tokens := make([]string, MaxTokens+1)
	err := NewJPush(JPushConfig{AppKey: "k", MasterSecret: "s", Endpoint: "https://x"}, nil).Push(context.Background(), Message{Tokens: tokens})
	if err == nil {
		t.Fatal("want error")
	}
}

func TestLogPusherOmitsContent(t *testing.T) {
	var buf strings.Builder
	l := Log{Logger: slog.New(slog.NewTextHandler(&buf, nil))}
	if err := l.Push(context.Background(), msg); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(buf.String(), "10:00") || !strings.Contains(buf.String(), "devices=2") {
		t.Fatalf("log = %s", buf.String())
	}
}
