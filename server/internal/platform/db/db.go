// Package db 提供 PostgreSQL 连接池、迁移与事务辅助。
package db

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"

	"github.com/vvangz/JikeLog/server/db/migrations"
	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/config"
)

const connectTimeout = 5 * time.Second

// Open 创建连接池并确认数据库可连接。
func Open(ctx context.Context, cfg config.DB) (*pgxpool.Pool, error) {
	pc, err := pgxpool.ParseConfig(cfg.URL)
	if err != nil {
		// 不回显 URL：其中可能带密码
		return nil, errors.New("解析 JIKELOG_DB_URL 失败")
	}
	pc.MaxConns = cfg.MaxConns
	pc.ConnConfig.ConnectTimeout = connectTimeout
	pool, err := pgxpool.NewWithConfig(ctx, pc)
	if err != nil {
		return nil, fmt.Errorf("创建数据库连接池失败: %w", err)
	}
	pingCtx, cancel := context.WithTimeout(ctx, connectTimeout)
	defer cancel()
	if err := pool.Ping(pingCtx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("连接数据库失败: %w", err)
	}
	return pool, nil
}

// Migrate 将内嵌的迁移脚本全部应用到数据库，返回本次应用的版本数。
func Migrate(ctx context.Context, pool *pgxpool.Pool) (int, error) {
	return migrateFS(ctx, pool, migrations.FS)
}

func migrateFS(ctx context.Context, pool *pgxpool.Pool, fsys fs.FS) (int, error) {
	sqlDB := stdlib.OpenDBFromPool(pool)
	defer func() { _ = sqlDB.Close() }()
	provider, err := goose.NewProvider(goose.DialectPostgres, sqlDB, fsys)
	if err != nil {
		return 0, fmt.Errorf("初始化迁移失败: %w", err)
	}
	results, err := provider.Up(ctx)
	if err != nil {
		return 0, fmt.Errorf("执行迁移失败: %w", err)
	}
	return len(results), nil
}

// TxRunner 在事务中执行函数，函数返回错误或 panic 时回滚。
type TxRunner struct {
	pool *pgxpool.Pool
}

// NewTxRunner 创建 TxRunner。
func NewTxRunner(pool *pgxpool.Pool) TxRunner { return TxRunner{pool: pool} }

// InTx 开启事务执行 fn；fn 成功则提交。
func (r TxRunner) InTx(ctx context.Context, fn func(q *dbgen.Queries) error) error {
	return pgx.BeginFunc(ctx, r.pool, func(tx pgx.Tx) error {
		return fn(dbgen.New(tx))
	})
}

// Queries 返回不在事务中的查询对象。
func (r TxRunner) Queries() *dbgen.Queries { return dbgen.New(r.pool) }

const codeUniqueViolation = "23505"

// IsUniqueViolation 报告 err 是否为指定唯一约束（索引）冲突；constraint 为空时匹配任意唯一约束。
func IsUniqueViolation(err error, constraint string) bool {
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) || pgErr.Code != codeUniqueViolation {
		return false
	}
	return constraint == "" || pgErr.ConstraintName == constraint
}

// IsNotFound 报告 err 是否为查询无结果。
func IsNotFound(err error) bool { return errors.Is(err, pgx.ErrNoRows) }
