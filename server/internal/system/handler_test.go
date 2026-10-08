package system

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"testing"
	"time"

	"github.com/vvangz/JikeLog/server/internal/apigen"
	"github.com/vvangz/JikeLog/server/internal/version"
)

func newHandler(timeout time.Duration, checks ...Checker) *Handler {
	return NewHandler(Config{
		Name:         "jikelog-api",
		Logger:       slog.New(slog.NewTextHandler(io.Discard, nil)),
		CheckTimeout: timeout,
		Checks:       checks,
	})
}

func ok(name string) Checker {
	return NewCheck(name, func(context.Context) error { return nil })
}

func failing(name string) Checker {
	return NewCheck(name, func(context.Context) error { return errors.New("dial tcp 10.0.0.5:5432: refused") })
}

func slow(name string) Checker {
	return NewCheck(name, func(ctx context.Context) error {
		<-ctx.Done()
		return ctx.Err()
	})
}

func TestGetHealthzAlwaysUp(t *testing.T) {
	resp, err := newHandler(time.Second, failing("postgres")).GetHealthz(context.Background(), apigen.GetHealthzRequestObject{})
	if err != nil {
		t.Fatal(err)
	}
	body, isOK := resp.(apigen.GetHealthz200JSONResponse)
	if !isOK || !body.Success || body.Data.Status != apigen.HealthStatusUp {
		t.Fatalf("resp = %#v", resp)
	}
	if len(body.Data.Checks) != 0 {
		t.Error("存活探针不应检查外部依赖")
	}
}

func TestGetReadyzAllUp(t *testing.T) {
	resp, err := newHandler(time.Second, ok("postgres"), ok("redis")).GetReadyz(context.Background(), apigen.GetReadyzRequestObject{})
	if err != nil {
		t.Fatal(err)
	}
	body, isOK := resp.(apigen.GetReadyz200JSONResponse)
	if !isOK || !body.Success || body.Data.Status != apigen.HealthStatusUp || len(body.Data.Checks) != 2 {
		t.Fatalf("resp = %#v", resp)
	}
	if body.Data.Checks[0].Name != "postgres" || body.Data.Checks[1].Name != "redis" {
		t.Error("检查结果应保持注册顺序")
	}
}

func TestGetReadyzReportsDownWithoutLeakingDetails(t *testing.T) {
	h := newHandler(50*time.Millisecond, ok("redis"), failing("postgres"), slow("oss"))
	resp, err := h.GetReadyz(context.Background(), apigen.GetReadyzRequestObject{})
	if err != nil {
		t.Fatal(err)
	}
	body, isOK := resp.(apigen.GetReadyz503JSONResponse)
	if !isOK {
		t.Fatalf("resp = %#v, want 503", resp)
	}
	if body.Success || body.Error == nil || body.Error.Code != CodeDependencyUnavailable {
		t.Fatalf("envelope = %#v", body)
	}
	want := map[string]struct {
		status apigen.HealthCheckStatus
		err    string
	}{
		"redis":    {apigen.HealthCheckStatusUp, ""},
		"postgres": {apigen.HealthCheckStatusDown, "unavailable"},
		"oss":      {apigen.HealthCheckStatusDown, "timeout"},
	}
	for _, c := range body.Data.Checks {
		w := want[c.Name]
		got := ""
		if c.Error != nil {
			got = *c.Error
		}
		if c.Status != w.status || got != w.err {
			t.Errorf("%s = (%s, %q), want (%s, %q)", c.Name, c.Status, got, w.status, w.err)
		}
	}
}

func TestGetReadyzWithNoChecksIsUp(t *testing.T) {
	resp, _ := newHandler(time.Second).GetReadyz(context.Background(), apigen.GetReadyzRequestObject{})
	if _, isOK := resp.(apigen.GetReadyz200JSONResponse); !isOK {
		t.Fatalf("resp = %#v", resp)
	}
}

func TestGetSystemInfo(t *testing.T) {
	fixed := time.Date(2026, 10, 8, 9, 0, 0, 0, time.UTC)
	h := NewHandler(Config{Name: "jikelog-api", Now: func() time.Time { return fixed }})

	resp, err := h.GetSystemInfo(context.Background(), apigen.GetSystemInfoRequestObject{})
	if err != nil {
		t.Fatal(err)
	}
	body, isOK := resp.(apigen.GetSystemInfo200JSONResponse)
	if !isOK || !body.Success {
		t.Fatalf("resp = %#v", resp)
	}
	d := body.Data
	if d.Name != "jikelog-api" || d.Version != version.Version || d.Commit != version.Commit || !d.ServerTime.Equal(fixed) {
		t.Errorf("data = %+v", d)
	}
}

func TestNewHandlerDefaults(t *testing.T) {
	h := NewHandler(Config{})
	if h.cfg.Logger == nil || h.cfg.Now == nil || h.cfg.CheckTimeout <= 0 {
		t.Errorf("默认值未填充: %+v", h.cfg)
	}
}

func TestGetReadyzEnforcesTimeoutForUncooperativeCheck(t *testing.T) {
	stuck := NewCheck("stuck", func(context.Context) error {
		time.Sleep(2 * time.Second) // 忽略 ctx 的检查项
		return nil
	})
	start := time.Now()
	resp, _ := newHandler(50*time.Millisecond, stuck).GetReadyz(context.Background(), apigen.GetReadyzRequestObject{})
	if elapsed := time.Since(start); elapsed > time.Second {
		t.Fatalf("GetReadyz 耗时 %v，超时未生效", elapsed)
	}
	body, isOK := resp.(apigen.GetReadyz503JSONResponse)
	if !isOK || *body.Data.Checks[0].Error != "timeout" {
		t.Fatalf("resp = %#v", resp)
	}
}

func TestGetReadyzIsolatesPanickingCheck(t *testing.T) {
	boom := NewCheck("boom", func(context.Context) error { panic("driver bug") })
	resp, err := newHandler(time.Second, boom, ok("redis")).GetReadyz(context.Background(), apigen.GetReadyzRequestObject{})
	if err != nil {
		t.Fatal(err)
	}
	body, isOK := resp.(apigen.GetReadyz503JSONResponse)
	if !isOK || body.Data.Checks[0].Status != apigen.HealthCheckStatusDown || *body.Data.Checks[0].Error != "unavailable" {
		t.Fatalf("resp = %#v", resp)
	}
}

func TestGetReadyzCachesResultWithinTTL(t *testing.T) {
	calls := 0
	counting := NewCheck("postgres", func(context.Context) error { calls++; return nil })
	now := time.Date(2026, 10, 8, 0, 0, 0, 0, time.UTC)
	h := NewHandler(Config{Checks: []Checker{counting}, ReadyCacheTTL: time.Second, Now: func() time.Time { return now }})

	for range 3 {
		_, _ = h.GetReadyz(context.Background(), apigen.GetReadyzRequestObject{})
	}
	if calls != 1 {
		t.Fatalf("TTL 内检查执行了 %d 次，want 1", calls)
	}
	now = now.Add(2 * time.Second)
	_, _ = h.GetReadyz(context.Background(), apigen.GetReadyzRequestObject{})
	if calls != 2 {
		t.Fatalf("TTL 过期后检查执行了 %d 次，want 2", calls)
	}
}
