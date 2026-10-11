package admin

import (
	"context"
	"fmt"
	"strings"
	"time"
	_ "time/tzdata" // 运行镜像不一定带时区数据库

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
)

// statsTimeZone 为仪表盘统计"今天"所用的时区。
const statsTimeZone = "Asia/Shanghai"

// trendDays 为仪表盘新增用户趋势的天数（含今天）。
const trendDays = 30

// phoneSuffixLen 为按手机号搜索时的位数（只能是末 4 位）。
const phoneSuffixLen = 4

// Dashboard 为仪表盘数据。
type Dashboard struct {
	Stats     dbgen.AdminUserStatsRow
	Daily     []DailyCount
	Platforms []dbgen.AdminPlatformStatsRow
}

// DailyCount 为某一天的数量。
type DailyCount struct {
	Day   string
	Count int64
}

// Dashboard 统计用户与存储概况。
func (s *Service) Dashboard(ctx context.Context, p Principal, m Meta) (Dashboard, error) {
	loc, err := time.LoadLocation(statsTimeZone)
	if err != nil {
		return Dashboard{}, err
	}
	now := s.d.Now().In(loc)
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, loc)
	q := s.d.Tx.Queries()
	stats, err := q.AdminUserStats(ctx, dbgen.AdminUserStatsParams{
		Today: today, Week: now.AddDate(0, 0, -7), Month: now.AddDate(0, 0, -30),
	})
	if err != nil {
		return Dashboard{}, fmt.Errorf("统计用户失败: %w", err)
	}
	start := today.AddDate(0, 0, -(trendDays - 1))
	rows, err := q.AdminDailyNewUsers(ctx, dbgen.AdminDailyNewUsersParams{Tz: statsTimeZone, Since: start})
	if err != nil {
		return Dashboard{}, fmt.Errorf("统计新增用户失败: %w", err)
	}
	byDay := make(map[string]int64, len(rows))
	for _, r := range rows {
		byDay[r.Day] = r.Users
	}
	daily := make([]DailyCount, 0, trendDays)
	for d := start; !d.After(today); d = d.AddDate(0, 0, 1) {
		day := d.Format(time.DateOnly)
		daily = append(daily, DailyCount{Day: day, Count: byDay[day]})
	}
	platforms, err := q.AdminPlatformStats(ctx, now.AddDate(0, 0, -30))
	if err != nil {
		return Dashboard{}, fmt.Errorf("统计设备平台失败: %w", err)
	}
	if err := s.auditAs(ctx, p, ActionViewDashboard, m, "", "", nil); err != nil {
		return Dashboard{}, err
	}
	return Dashboard{Stats: stats, Daily: daily, Platforms: platforms}, nil
}

// UserPage 为一页用户。
type UserPage struct {
	Users []dbgen.AdminListUsersRow
	Total int64
	Page  int
	Size  int
}

// ListUsers 按用户名、昵称搜索用户；输入恰好 4 位数字时也匹配手机号末 4 位。
// 只接受 4 位：更长的数字后缀可以逐位试出完整手机号，而管理员不应看到完整号码。
func (s *Service) ListUsers(ctx context.Context, p Principal, query string, page, size int, m Meta) (UserPage, error) {
	page, size = pageOf(page, size)
	limit, offset := limitOffset(page, size)
	query = strings.TrimSpace(query)
	if len([]rune(query)) > 30 {
		query = string([]rune(query)[:30])
	}
	like := escapeLike(query)
	suffix := ""
	if len(query) == phoneSuffixLen && strings.IndexFunc(query, func(r rune) bool { return r < '0' || r > '9' }) < 0 {
		suffix = query
	}
	q := s.d.Tx.Queries()
	users, err := q.AdminListUsers(ctx, dbgen.AdminListUsersParams{
		Query: like, PhoneSuffix: suffix, MaxRows: limit, Skip: offset,
	})
	if err != nil {
		return UserPage{}, fmt.Errorf("查询用户失败: %w", err)
	}
	total, err := q.AdminCountUsers(ctx, dbgen.AdminCountUsersParams{Query: like, PhoneSuffix: suffix})
	if err != nil {
		return UserPage{}, fmt.Errorf("统计用户失败: %w", err)
	}
	if err := s.auditAs(ctx, p, ActionListUsers, m, "", "", map[string]any{"q": query, "page": page}); err != nil {
		return UserPage{}, err
	}
	return UserPage{Users: users, Total: total, Page: page, Size: size}, nil
}

// escapeLike 转义 LIKE 模式中的通配符，搜索词按字面匹配。
func escapeLike(s string) string {
	return strings.NewReplacer(`\`, `\\`, "%", `\%`, "_", `\_`).Replace(s)
}

// UserDetail 为用户详情：只有配置与元数据，不含任何内容。
type UserDetail struct {
	User       dbgen.User
	Settings   dbgen.UserSetting
	HasSetting bool
	Devices    []dbgen.AdminListUserDevicesRow
	ServerSeq  int64
	LastSync   *time.Time
	Used       int64
	Quota      int64
}

// GetUser 返回用户的配置信息。
func (s *Service) GetUser(ctx context.Context, p Principal, id uuid.UUID, m Meta) (UserDetail, error) {
	q := s.d.Tx.Queries()
	u, err := q.GetUserByID(ctx, id)
	if db.IsNotFound(err) {
		return UserDetail{}, errNotFound
	}
	if err != nil {
		return UserDetail{}, fmt.Errorf("查询用户失败: %w", err)
	}
	out := UserDetail{User: u, Quota: s.d.Quota}
	st, err := q.GetSettings(ctx, id)
	switch {
	case err == nil:
		out.Settings, out.HasSetting = st, true
	case !db.IsNotFound(err):
		return UserDetail{}, fmt.Errorf("查询设置失败: %w", err)
	}
	if out.Devices, err = q.AdminListUserDevices(ctx, id); err != nil {
		return UserDetail{}, fmt.Errorf("查询设备失败: %w", err)
	}
	if out.ServerSeq, err = q.GetSyncCursor(ctx, id); err != nil {
		return UserDetail{}, fmt.Errorf("查询同步状态失败: %w", err)
	}
	switch last, err := q.AdminLastSync(ctx, id); {
	case err == nil:
		out.LastSync = &last
	case !db.IsNotFound(err):
		return UserDetail{}, fmt.Errorf("查询同步状态失败: %w", err)
	}
	if out.Used, err = q.SumAttachmentBytes(ctx, id); err != nil {
		return UserDetail{}, fmt.Errorf("查询附件用量失败: %w", err)
	}
	if err := s.auditAs(ctx, p, ActionViewUser, m, "user", id.String(), nil); err != nil {
		return UserDetail{}, err
	}
	return out, nil
}

// MaskPhone 脱敏手机号：+8613812345678 → +86 138****5678；其他国家保留国家码前两位与末 4 位。
func MaskPhone(phone string) string {
	digits := strings.TrimPrefix(phone, "+")
	if strings.HasPrefix(digits, "86") && len(digits) == 13 {
		return "+86 " + digits[2:5] + "****" + digits[9:]
	}
	if len(digits) < 8 {
		return "+" + strings.Repeat("*", len(digits))
	}
	return "+" + digits[:2] + " ****" + digits[len(digits)-4:]
}
