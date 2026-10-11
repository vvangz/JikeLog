package main

import (
	"strings"
	"testing"
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
