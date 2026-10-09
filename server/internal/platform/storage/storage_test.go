package storage

import (
	"bytes"
	"context"
	"errors"
	"io"
	"net/http"
	"strconv"
	"testing"
	"time"

	"github.com/vvangz/JikeLog/server/internal/testinfra"
)

func TestMain(m *testing.M) { testinfra.Main(m) }

func newStore(t *testing.T) *Store {
	t.Helper()
	s, err := New(testinfra.ObjectStore(t))
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	if err := s.EnsureBucket(ctx); err != nil {
		t.Fatal(err)
	}
	if err := s.EnsureBucket(ctx); err != nil {
		t.Fatalf("重复调用应成功：%v", err)
	}
	return s
}

func put(t *testing.T, up Upload, body []byte) int {
	t.Helper()
	req, err := http.NewRequest(http.MethodPut, up.URL, bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	for k, v := range up.Headers {
		req.Header.Set(k, v)
	}
	req.ContentLength = int64(len(body))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	_ = resp.Body.Close()
	return resp.StatusCode
}

func TestUploadStatDownloadDelete(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	key := "u/user-1/att-1"
	if _, err := s.Size(ctx, key); !errors.Is(err, ErrNotFound) {
		t.Fatalf("未上传时应返回 ErrNotFound，err=%v", err)
	}
	body := []byte("附件内容 attachment body")
	up, err := s.PresignPut(ctx, key, int64(len(body)), "text/plain", time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if up.Headers["Content-Length"] != strconv.Itoa(len(body)) || up.Expires.IsZero() {
		t.Fatalf("headers=%v", up.Headers)
	}
	if code := put(t, up, body); code != http.StatusOK {
		t.Fatalf("上传失败：%d", code)
	}
	size, err := s.Size(ctx, key)
	if err != nil || size != int64(len(body)) {
		t.Fatalf("size=%d err=%v", size, err)
	}
	url, exp, err := s.PresignGet(ctx, key, time.Minute)
	if err != nil || exp.IsZero() {
		t.Fatal(err)
	}
	resp, err := http.Get(url)
	if err != nil {
		t.Fatal(err)
	}
	got, _ := io.ReadAll(resp.Body)
	_ = resp.Body.Close()
	if !bytes.Equal(got, body) || resp.Header.Get("Content-Disposition") != "attachment" {
		t.Fatalf("下载内容或 Content-Disposition 不符：%q %q", got, resp.Header.Get("Content-Disposition"))
	}
	if err := s.Delete(ctx, key); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Size(ctx, key); !errors.Is(err, ErrNotFound) {
		t.Fatal("删除后应不存在")
	}
}

func TestPresignedPutRejectsDifferentSizeOrType(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	up, err := s.PresignPut(ctx, "u/x/a", 10, "image/png", time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if code := put(t, up, []byte("more than ten bytes")); code == http.StatusOK {
		t.Fatal("大小与签名不符时应拒绝")
	}
	wrongType := up
	wrongType.Headers = map[string]string{"Content-Type": "text/html", "Content-Length": "10"}
	if code := put(t, wrongType, []byte("0123456789")); code == http.StatusOK {
		t.Fatal("类型与签名不符时应拒绝")
	}
}

func TestDeletePrefix(t *testing.T) {
	s := newStore(t)
	ctx := context.Background()
	for _, k := range []string{"u/a/1", "u/a/2", "u/b/1"} {
		up, _ := s.PresignPut(ctx, k, 1, "text/plain", time.Minute)
		if code := put(t, up, []byte("x")); code != http.StatusOK {
			t.Fatalf("上传 %s 失败：%d", k, code)
		}
	}
	if err := s.DeletePrefix(ctx, "u/a/"); err != nil {
		t.Fatal(err)
	}
	for k, want := range map[string]bool{"u/a/1": false, "u/a/2": false, "u/b/1": true} {
		_, err := s.Size(ctx, k)
		if exists := err == nil; exists != want {
			t.Errorf("%s exists=%v want %v (err=%v)", k, exists, want, err)
		}
	}
}
