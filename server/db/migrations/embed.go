// Package migrations 内嵌数据库迁移脚本（goose 格式），由 cmd/migrate 与测试使用。
// 新增迁移：按序号新建 000NN_<描述>.sql，包含 -- +goose Up / Down 两段，然后执行 scripts/gen-db.sh。
package migrations

import "embed"

// FS 包含本目录下全部 .sql 迁移脚本。
//
//go:embed *.sql
var FS embed.FS
