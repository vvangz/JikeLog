// Package reminder 在备忘录提醒时刻向需要的设备发送推送（ADR-008）。
//
// 待发提醒由同步推送事务写入 memo_reminders（见 syncer.scheduleMemo）。调度器定期领取到期的提醒：
// 已同步到这一版备忘录、且能在本地按时提醒的设备由本地闹钟负责，不再推送，避免重复提醒。
package reminder

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"time"
	_ "time/tzdata" // 运行镜像不一定带时区数据库，按设备时区显示推送中的时间

	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/platform/db"
	"github.com/vvangz/JikeLog/server/internal/platform/pusher"
	"github.com/vvangz/JikeLog/server/internal/syncer"
)

const (
	// PollInterval 为检查到期提醒的间隔，推送最多因此延后这么久。
	PollInterval = 10 * time.Second
	// batchSize 为每次领取的提醒数，领取不满时本轮结束。
	batchSize = 20
	// lease 为领取后独占的时长：发送失败或实例崩溃时，到期后由任一实例重试。
	lease = 5 * time.Minute
	// leaseMargin：领取期限只剩这么多时不再发送本批剩余的提醒（交给到期后的重新领取），
	// 避免其他实例已重新领取时重复推送。
	leaseMargin = time.Minute
	// maxAttempts 为一条提醒最多尝试发送的次数。
	maxAttempts = 3
	// staleAfter 之后才领取到的提醒（服务长时间停机）不再发送，过时的提醒只会打扰用户。
	staleAfter = time.Hour
	// pushTTL 为设备离线时推送的保留时长。
	pushTTL = time.Hour
	// defaultTimeZone 用于没有上报时区的设备。
	defaultTimeZone = "Asia/Shanghai"
)

// Deps 为 Dispatcher 的依赖。
type Deps struct {
	Tx     db.TxRunner
	Pusher pusher.Pusher
	Logger *slog.Logger
	// Now 为空时使用 time.Now。
	Now func() time.Time
}

// Dispatcher 发送到期的备忘录提醒。多个实例可以同时运行，领取时互不重复。
type Dispatcher struct {
	d Deps
}

// NewDispatcher 创建 Dispatcher。
func NewDispatcher(d Deps) *Dispatcher {
	if d.Now == nil {
		d.Now = time.Now
	}
	return &Dispatcher{d: d}
}

// Run 每隔 PollInterval 发送到期的提醒，直到 ctx 取消。
func (r *Dispatcher) Run(ctx context.Context) {
	ticker := time.NewTicker(PollInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if _, err := r.Tick(ctx); err != nil && ctx.Err() == nil {
				r.d.Logger.WarnContext(ctx, "reminder dispatch failed", "error", err)
			}
		}
	}
}

// Tick 处理当前全部到期的提醒，返回处理的条数。
func (r *Dispatcher) Tick(ctx context.Context) (int, error) {
	total := 0
	for {
		claimed := r.d.Now()
		due, err := r.claim(ctx)
		if err != nil {
			return total, err
		}
		for _, row := range due {
			if r.d.Now().Sub(claimed) > lease-leaseMargin {
				return total, nil // 推送通道太慢：剩余的提醒在领取期限过后重新领取
			}
			if err := r.dispatch(ctx, row); err != nil {
				return total, err
			}
		}
		total += len(due)
		if len(due) < batchSize {
			return total, nil
		}
	}
}

func (r *Dispatcher) claim(ctx context.Context) ([]dbgen.ClaimDueRemindersRow, error) {
	now := r.d.Now()
	var due []dbgen.ClaimDueRemindersRow
	err := r.d.Tx.InTx(ctx, func(q *dbgen.Queries) error {
		var err error
		due, err = q.ClaimDueReminders(ctx, dbgen.ClaimDueRemindersParams{LeaseUntil: now.Add(lease), Now: now, MaxRows: batchSize})
		return err
	})
	if err != nil {
		return nil, fmt.Errorf("领取到期提醒失败: %w", err)
	}
	return due, nil
}

// dispatch 发送一条提醒。只有数据库错误会返回；推送失败按重试策略处理。
func (r *Dispatcher) dispatch(ctx context.Context, row dbgen.ClaimDueRemindersRow) error {
	log := r.d.Logger.With("memo_id", row.MemoID, "offset_min", row.OffsetMin)
	if r.d.Now().Sub(row.FireAt) > staleAfter {
		log.WarnContext(ctx, "reminder dropped: too late", "fire_at", row.FireAt)
		return r.finish(ctx, row)
	}
	if row.Attempts > maxAttempts {
		// 之前的尝试中途崩溃（没有记录结果），不再继续
		log.WarnContext(ctx, "reminder dropped: too many attempts", "attempts", row.Attempts)
		return r.finish(ctx, row)
	}
	q := r.d.Tx.Queries()
	rec, err := q.GetRecord(ctx, dbgen.GetRecordParams{ID: row.MemoID, UserID: row.UserID})
	if db.IsNotFound(err) {
		return r.finish(ctx, row)
	}
	if err != nil {
		return fmt.Errorf("读取备忘录失败: %w", err)
	}
	memo, err := parseMemo(rec)
	if err != nil {
		log.ErrorContext(ctx, "reminder dropped: memo corrupt", "error", err)
		return r.finish(ctx, row)
	}
	if rec.Deleted {
		return r.finish(ctx, row)
	}
	targets, err := q.ListReminderTargets(ctx, dbgen.ListReminderTargetsParams{
		UserID: row.UserID, MemoSeq: rec.ServerSeq, FireAt: row.FireAt,
	})
	if err != nil {
		return fmt.Errorf("查询推送设备失败: %w", err)
	}
	if err := r.send(ctx, row, memo, targets); err != nil {
		if pusher.IsRetryable(err) && row.Attempts < maxAttempts {
			log.WarnContext(ctx, "reminder push failed, will retry", "attempt", row.Attempts, "error", err)
			return nil // 领取期限过后重试
		}
		log.ErrorContext(ctx, "reminder push failed", "attempt", row.Attempts, "error", err)
	}
	return r.finish(ctx, row)
}

// send 按设备时区分组发送（推送文案中的时间按时区显示）。某一组可重试地失败时整条提醒重试，
// 已发送成功的组会再收到一次（多台设备时区不同且推送通道故障时才会发生，可以接受）。
func (r *Dispatcher) send(ctx context.Context, row dbgen.ClaimDueRemindersRow, memo memoTime, targets []dbgen.ListReminderTargetsRow) error {
	groups := map[string][]string{}
	provider := map[string]string{}
	for _, t := range targets {
		if t.PushToken != nil && t.PushProvider != nil {
			groups[t.TimeZone] = append(groups[t.TimeZone], *t.PushToken)
			provider[*t.PushToken] = *t.PushProvider
		}
	}
	var errs []error
	for tz, tokens := range groups {
		err := r.d.Pusher.Push(ctx, pusher.Message{
			Tokens: tokens,
			Title:  "备忘提醒",
			Body:   reminderBody(memo, int(row.OffsetMin), row.FireAt, location(tz)),
			Extras: map[string]string{"type": syncer.EntityMemo, "memoId": row.MemoID.String()},
			TTL:    pushTTL,
		})
		switch {
		case errors.Is(err, pusher.ErrNoTarget):
			r.clearTokens(ctx, tokens, provider)
		case err != nil:
			errs = append(errs, err)
		}
	}
	return errors.Join(errs...)
}

// clearTokens 清除推送通道报告已失效的标识（App 已卸载等），之后不再向它们推送。
func (r *Dispatcher) clearTokens(ctx context.Context, tokens []string, provider map[string]string) {
	q := r.d.Tx.Queries()
	for _, t := range tokens {
		pv := provider[t]
		if err := q.ClearPushByToken(ctx, dbgen.ClearPushByTokenParams{PushProvider: &pv, PushToken: &t}); err != nil {
			r.d.Logger.WarnContext(ctx, "clear invalid push token failed", "error", err)
		}
	}
}

func (r *Dispatcher) finish(ctx context.Context, row dbgen.ClaimDueRemindersRow) error {
	err := r.d.Tx.Queries().FinishReminder(ctx, dbgen.FinishReminderParams{MemoID: row.MemoID, OffsetMin: row.OffsetMin, FireAt: row.FireAt})
	if err != nil {
		return fmt.Errorf("删除已发送的提醒失败: %w", err)
	}
	return nil
}

// memoTime 为推送文案需要的备忘录字段（均不加密）。
type memoTime struct {
	At     time.Time
	AllDay bool
}

func parseMemo(rec dbgen.Record) (memoTime, error) {
	var f struct {
		At     *int64 `json:"at"`
		AllDay *int64 `json:"allDay"`
	}
	if err := json.Unmarshal(rec.Fields, &f); err != nil {
		return memoTime{}, fmt.Errorf("解析备忘录字段失败: %w", err)
	}
	if f.At == nil {
		return memoTime{}, errors.New("备忘录没有时间")
	}
	return memoTime{At: time.UnixMilli(*f.At), AllDay: f.AllDay != nil && *f.AllDay == 1}, nil
}

func location(tz string) *time.Location {
	if tz == "" {
		tz = defaultTimeZone
	}
	loc, err := time.LoadLocation(tz)
	if err != nil {
		return time.UTC
	}
	return loc
}

// reminderBody 生成推送正文。备忘内容是加密字段，不出现在推送中（第三方推送通道可见），
// 只说明时间，用户点按后在 App 内查看。
func reminderBody(m memoTime, offset int, fireAt time.Time, loc *time.Location) string {
	at := m.At.In(loc)
	day := at.Format("1月2日")
	if sameDay(at, fireAt.In(loc)) {
		day = "今天"
	} else if sameDay(at, fireAt.In(loc).AddDate(0, 0, 1)) {
		day = "明天"
	}
	switch {
	case m.AllDay:
		return day + "有一条全天备忘"
	case offset == 0:
		return at.Format("15:04") + " 的备忘到时间了"
	default:
		return day + " " + at.Format("15:04") + " 有一条备忘"
	}
}

func sameDay(a, b time.Time) bool {
	ay, am, ad := a.Date()
	by, bm, bd := b.Date()
	return ay == by && am == bm && ad == bd
}
