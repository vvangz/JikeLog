// Package logging 基于 log/slog 构建结构化日志器。
package logging

import (
	"fmt"
	"io"
	"log/slog"
)

// New 按级别（debug/info/warn/error）与格式（json/text）创建日志器。
func New(level, format string, w io.Writer) (*slog.Logger, error) {
	var lv slog.Level
	if err := lv.UnmarshalText([]byte(level)); err != nil {
		return nil, fmt.Errorf("日志级别 %q 不合法: %w", level, err)
	}
	opts := &slog.HandlerOptions{Level: lv}
	switch format {
	case "json":
		return slog.New(slog.NewJSONHandler(w, opts)), nil
	case "text":
		return slog.New(slog.NewTextHandler(w, opts)), nil
	default:
		return nil, fmt.Errorf("日志格式 %q 不合法，可选 json/text", format)
	}
}
