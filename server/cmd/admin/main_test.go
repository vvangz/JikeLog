package main

import (
	"errors"
	"strings"
	"testing"

	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
)

func TestReadPassword(t *testing.T) {
	pw, err := readPassword(strings.NewReader("Secret12345\r\nignored\n"))
	if err != nil || pw != "Secret12345" {
		t.Fatalf("%q %v", pw, err)
	}
	if pw, _ := readPassword(strings.NewReader("NoNewline1")); pw != "NoNewline1" {
		t.Fatalf("%q", pw)
	}
	if _, err := readPassword(strings.NewReader("\n")); err == nil {
		t.Fatal("空密码应报错")
	}
}

func TestRunRequiresUsername(t *testing.T) {
	if err := run(nil, strings.NewReader(""), nil); err == nil {
		t.Fatal("没有子命令应报错")
	}
	if err := run([]string{"create"}, strings.NewReader("x\n"), nil); err == nil || !strings.Contains(err.Error(), "用法") {
		t.Fatalf("缺少用户名应提示用法：%v", err)
	}
}

func TestDescribeShowsReasons(t *testing.T) {
	err := describe(httpx.Validation(map[string]string{"password": "密码需要同时包含字母和数字"}))
	if err.Error() != "失败：密码需要同时包含字母和数字" {
		t.Fatalf("%v", err)
	}
	if got := describe(httpx.NewError(409, "USERNAME_TAKEN", "用户名已被使用")).Error(); got != "失败：用户名已被使用" {
		t.Fatalf("%v", got)
	}
	if got := describe(errors.New("连接失败")).Error(); got != "失败：连接失败" {
		t.Fatalf("%v", got)
	}
}
