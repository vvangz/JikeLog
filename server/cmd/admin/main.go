// Command admin 管理 Web 管理后台的管理员账号（ADR-011）：创建第一个超级管理员，或在忘记密码时重置。
//
//	jikelog-admin create -username root -role super_admin   # 密码从标准输入读取
//	jikelog-admin reset-password -username root
//
// 密码从标准输入读取第一行（不会留在命令历史中），例如 `read -s PW && echo "$PW" | jikelog-admin create ...`。
package main

import (
	"bufio"
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/signal"
	"sort"
	"strings"
	"syscall"

	"github.com/vvangz/JikeLog/server/internal/admin"
	"github.com/vvangz/JikeLog/server/internal/auth"
	"github.com/vvangz/JikeLog/server/internal/platform/config"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
)

const usage = `用法：
  jikelog-admin create -username <用户名> [-role super_admin|viewer]
  jikelog-admin reset-password -username <用户名>
密码从标准输入读取第一行。`

func main() {
	if err := run(os.Args[1:], os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(args []string, stdin io.Reader, stdout io.Writer) error {
	if len(args) == 0 {
		return errors.New(usage)
	}
	fs := flag.NewFlagSet(args[0], flag.ContinueOnError)
	username := fs.String("username", "", "管理员用户名")
	role := fs.String("role", admin.RoleSuperAdmin, "角色：super_admin 或 viewer")
	if err := fs.Parse(args[1:]); err != nil {
		return err
	}
	if *username == "" {
		return errors.New(usage)
	}
	password, err := readPassword(stdin)
	if err != nil {
		return err
	}
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	pool, err := db.Open(ctx, cfg.DB)
	if err != nil {
		return err
	}
	defer pool.Close()
	svc := admin.NewService(admin.Deps{
		Tx: db.NewTxRunner(pool), Hasher: auth.NewHasher(auth.DefaultArgon2Params),
		Logger: slog.New(slog.NewTextHandler(io.Discard, nil)),
	})
	return execute(ctx, svc, args[0], *username, *role, password, stdout)
}

// execute 执行子命令（便于测试）。
func execute(ctx context.Context, svc *admin.Service, cmd, username, role, password string, stdout io.Writer) error {
	switch cmd {
	case "create":
		a, err := svc.CreateAdmin(ctx, nil, username, role, password, admin.Meta{})
		if err != nil {
			return describe(err)
		}
		_, err = fmt.Fprintf(stdout, "已创建管理员 %s（%s）\n", a.Username, a.Role)
		return err
	case "reset-password":
		a, err := svc.AdminByUsername(ctx, username)
		if err != nil {
			return describe(err)
		}
		if err := svc.ResetPassword(ctx, nil, a.ID, password, admin.Meta{}); err != nil {
			return describe(err)
		}
		_, err = fmt.Fprintf(stdout, "已重置 %s 的密码，原有登录全部失效\n", a.Username)
		return err
	default:
		return errors.New(usage)
	}
}

// describe 把错误转为命令行提示：参数校验错误列出具体原因（如密码不符合规则）。
func describe(err error) error {
	var he *httpx.Error
	if errors.As(err, &he) {
		if fields, ok := he.Details["fields"].(map[string]string); ok && len(fields) > 0 {
			reasons := make([]string, 0, len(fields))
			for _, r := range fields {
				reasons = append(reasons, r)
			}
			sort.Strings(reasons)
			return fmt.Errorf("失败：%s", strings.Join(reasons, "；"))
		}
		return fmt.Errorf("失败：%s", he.Message)
	}
	return fmt.Errorf("失败：%w", err)
}

func readPassword(r io.Reader) (string, error) {
	line, err := bufio.NewReader(r).ReadString('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		return "", fmt.Errorf("读取密码失败: %w", err)
	}
	pw := strings.TrimRight(line, "\r\n")
	if pw == "" {
		return "", errors.New("请从标准输入提供密码")
	}
	return pw, nil
}
