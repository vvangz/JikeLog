// Package version 提供服务版本信息。
package version

// Version 为产品版本号，由 Release Please 在发布时自动更新。
const Version = "0.2.0" // x-release-please-version

// Commit 与 BuildTime 在构建时通过 -ldflags "-X" 注入。
var (
	Commit    = "dev"
	BuildTime = "unknown"
)
