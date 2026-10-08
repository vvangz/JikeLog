package logging

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"
)

func TestNewJSON(t *testing.T) {
	var buf bytes.Buffer
	logger, err := New("info", "json", &buf)
	if err != nil {
		t.Fatalf("New() error = %v", err)
	}
	logger.Debug("hidden")
	logger.Info("hello", "k", "v")

	lines := strings.Split(strings.TrimSpace(buf.String()), "\n")
	if len(lines) != 1 {
		t.Fatalf("got %d lines, want 1（debug 应被过滤）: %q", len(lines), buf.String())
	}
	var rec map[string]any
	if err := json.Unmarshal([]byte(lines[0]), &rec); err != nil {
		t.Fatalf("输出不是 JSON: %v", err)
	}
	if rec["msg"] != "hello" || rec["k"] != "v" {
		t.Errorf("record = %v", rec)
	}
}

func TestNewText(t *testing.T) {
	var buf bytes.Buffer
	logger, err := New("debug", "text", &buf)
	if err != nil {
		t.Fatalf("New() error = %v", err)
	}
	logger.Debug("visible")
	if !strings.Contains(buf.String(), "msg=visible") {
		t.Errorf("text 输出 = %q", buf.String())
	}
}

func TestNewRejectsInvalid(t *testing.T) {
	if _, err := New("loud", "json", &bytes.Buffer{}); err == nil {
		t.Error("非法级别应报错")
	}
	if _, err := New("info", "yaml", &bytes.Buffer{}); err == nil {
		t.Error("非法格式应报错")
	}
}
