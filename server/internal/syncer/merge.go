package syncer

import (
	"maps"
	"slices"
	"sort"
	"strings"
	"unicode/utf8"

	"github.com/vvangz/JikeLog/server/internal/textpatch"
)

// maxAbsorbed 为每个字段记住的"已吸收客户端时钟"数量上限。
const maxAbsorbed = 16

// State 为记录的明文状态。
type State struct {
	Fields map[string]Value
	Clocks map[string]Clock
	// Absorbed 记录已经并入当前值（补丁合并）或在冲突中落败的客户端时钟。
	// 同一推送重试时据此识别为已处理，避免重复应用补丁或重复记录冲突。
	Absorbed map[string][]Clock
	Deleted  bool
}

// Change 为客户端推送的一条变更（已解密、已解析）。
type Change struct {
	Deleted bool
	Fields  map[string]Value
	Clocks  map[string]Clock
	// BaseClocks 为客户端修改前最后一次从服务端拿到的字段时钟。
	BaseClocks map[string]Clock
	Patches    map[string][]textpatch.Hunk
	// Budget 为补丁应用的计算量预算，同一请求内的变更共享；为 nil 时每次使用默认预算。
	Budget *textpatch.Budget
}

// Status 为一条变更的处理结果。
type Status string

// 处理结果。
const (
	StatusApplied  Status = "applied"
	StatusMerged   Status = "merged"
	StatusConflict Status = "conflict"
	StatusRejected Status = "rejected"
)

// Outcome 为合并结果。
type Outcome struct {
	Status Status
	// Changed 为 true 时需要写入新版本。
	Changed bool
	// Edited 表示字段值或时钟有变化（只吸收了客户端时钟时为 false），用于决定是否保存编辑前修订。
	Edited bool
	Next   State
	// Losers 为冲突中落败一方的完整快照，写入修订历史供用户查看和恢复。
	Losers []map[string]Value
	// DeletedNow 表示本次把记录删除（需保存删除前的快照）。
	DeletedNow bool
}

// FieldErrors 为逐字段的校验错误（字段名 → 提示）。
type FieldErrors map[string]string

func (e FieldErrors) Error() string {
	keys := slices.Sorted(maps.Keys(e))
	parts := make([]string, len(keys))
	for i, k := range keys {
		parts[i] = k + ": " + e[k]
	}
	return "字段校验失败：" + strings.Join(parts, "; ")
}

// Merge 按 ADR-005 的规则把变更合并到当前状态。cur 为 nil 表示记录不存在。不修改入参。
func Merge(e Entity, cur *State, ch Change) (Outcome, error) {
	if err := validate(e, cur, ch); err != nil {
		return Outcome{}, err
	}
	switch {
	case cur == nil && ch.Deleted:
		// 离线创建后又删除，从未同步过：无需保存
		return Outcome{Status: StatusApplied}, nil
	case cur == nil:
		return Outcome{Status: StatusApplied, Changed: true, Edited: true, Next: State{
			Fields: maps.Clone(ch.Fields), Clocks: maps.Clone(ch.Clocks), Absorbed: map[string][]Clock{},
		}}, nil
	case cur.Deleted && ch.Deleted:
		return Outcome{Status: StatusApplied, Next: clone(*cur)}, nil
	case cur.Deleted:
		return editAfterDelete(cur, ch), nil
	case ch.Deleted:
		next := clone(*cur)
		next.Deleted = true
		return Outcome{Status: StatusApplied, Changed: true, Next: next, DeletedNow: true}, nil
	}
	return mergeFields(e, cur, ch), nil
}

// editAfterDelete 处理"删除胜过编辑"：编辑存为冲突快照；已吸收过的重试不再重复记录。
func editAfterDelete(cur *State, ch Change) Outcome {
	next := clone(*cur)
	fresh := false
	for f, cc := range ch.Clocks {
		if cc != cur.Clocks[f] && !slices.Contains(cur.Absorbed[f], cc) {
			fresh = true
			absorb(&next, f, cc)
		}
	}
	out := Outcome{Status: StatusConflict, Next: next, Changed: fresh}
	if fresh {
		out.Losers = []map[string]Value{overlay(cur.Fields, ch.Fields)}
	}
	return out
}

func mergeFields(e Entity, cur *State, ch Change) Outcome {
	next := clone(*cur)
	status := StatusApplied
	changed, edited := false, false
	clientLost := map[string]Value{}
	serverLost := false
	for _, f := range slices.Sorted(maps.Keys(ch.Fields)) {
		cv, cc := ch.Fields[f], ch.Clocks[f]
		sc := cur.Clocks[f]
		switch {
		case cc == sc:
			continue // 已应用过（重试），客户端的值就是当前值
		case slices.Contains(cur.Absorbed[f], cc):
			// 曾被合并或在冲突中落败（重试）：返回服务端记录，让客户端以服务端为准
			status = maxStatus(status, StatusMerged)
			continue
		case sc == ch.BaseClocks[f] && cc > sc:
			// 服务端在此期间没改过这个字段：快进（时钟不能倒退）
			overwrite(&next, f, cv, cc, sc)
			edited = true
		case e.Fields[f].Kind == KindText && len(ch.Patches[f]) > 0 && tryPatch(&next, e.Fields[f], f, cur, ch):
			status = maxStatus(status, StatusMerged)
			edited = true
		case cc > sc:
			// 最后修改覆盖：客户端胜出，服务端原值进入冲突快照
			overwrite(&next, f, cv, cc, sc)
			serverLost = true
			edited = true
			status = StatusConflict
		default:
			// 服务端胜出：记住客户端时钟，客户端的值进入冲突快照
			absorb(&next, f, cc)
			clientLost[f] = cv
			status = StatusConflict
		}
		changed = true
	}
	out := Outcome{Status: status, Changed: changed, Edited: edited, Next: next}
	if serverLost {
		out.Losers = append(out.Losers, maps.Clone(cur.Fields))
	}
	if len(clientLost) > 0 {
		out.Losers = append(out.Losers, overlay(cur.Fields, clientLost))
	}
	return out
}

// tryPatch 把客户端补丁应用到服务端当前文本，成功时写入 next 并返回 true。
func tryPatch(next *State, spec Field, f string, cur *State, ch Change) bool {
	text, _ := cur.Fields[f].(string)
	merged, ok := textpatch.Apply(text, ch.Patches[f], ch.Budget)
	if !ok || (spec.MaxLen > 0 && utf8.RuneCountInString(merged) > spec.MaxLen) {
		return false
	}
	cc, sc := ch.Clocks[f], cur.Clocks[f]
	next.Fields[f] = merged
	next.Clocks[f] = MaxClock(sc, cc)
	if next.Clocks[f] != cc {
		absorb(next, f, cc)
	}
	return true
}

func validate(e Entity, cur *State, ch Change) error {
	errs := FieldErrors{}
	if e.ServerCreated && !ch.Deleted {
		for f := range ch.Fields {
			errs[f] = "该字段只能由服务端写入"
		}
		if len(errs) == 0 {
			errs["entity"] = "该类型只能由服务端创建，客户端只能删除"
		}
		return errs
	}
	for f, v := range ch.Fields {
		spec, ok := e.Fields[f]
		switch {
		case !ok:
			errs[f] = "未知字段"
		case spec.ServerOnly:
			errs[f] = "该字段只能由服务端写入"
		case ch.Clocks[f] == "":
			errs[f] = "缺少字段时钟"
		case v == nil && spec.Required:
			errs[f] = "不能为空"
		}
	}
	for _, clocks := range []map[string]Clock{ch.Clocks, ch.BaseClocks} {
		for f := range clocks {
			if _, ok := e.Fields[f]; !ok {
				errs[f] = "未知字段"
			}
		}
	}
	for f := range ch.Patches {
		if spec, ok := e.Fields[f]; !ok || spec.Kind != KindText {
			errs[f] = "该字段不支持补丁"
		} else if _, has := ch.Fields[f]; !has {
			errs[f] = "补丁必须与字段值一起提交"
		}
	}
	if cur == nil && !ch.Deleted {
		for f, spec := range e.Fields {
			if spec.Required && ch.Fields[f] == nil && errs[f] == "" {
				errs[f] = "不能为空"
			}
		}
	}
	if len(errs) > 0 {
		return errs
	}
	return nil
}

// overwrite 用客户端的值覆盖字段，并记住被覆盖值的时钟：写入那个值的设备重试推送时能被识别。
func overwrite(s *State, f string, v Value, c, replaced Clock) {
	s.Fields[f], s.Clocks[f] = v, c
	if replaced != "" {
		absorb(s, f, replaced)
	}
}

func absorb(s *State, f string, c Clock) {
	list := append(slices.Clone(s.Absorbed[f]), c)
	sort.Slice(list, func(i, j int) bool { return list[i] < list[j] })
	if len(list) > maxAbsorbed {
		list = list[len(list)-maxAbsorbed:]
	}
	s.Absorbed[f] = list
}

func maxStatus(a, b Status) Status {
	rank := map[Status]int{StatusApplied: 0, StatusMerged: 1, StatusConflict: 2}
	if rank[b] > rank[a] {
		return b
	}
	return a
}

func overlay(base, top map[string]Value) map[string]Value {
	out := maps.Clone(base)
	if out == nil {
		out = map[string]Value{}
	}
	maps.Copy(out, top)
	return out
}

func clone(s State) State {
	absorbed := make(map[string][]Clock, len(s.Absorbed))
	for k, v := range s.Absorbed {
		absorbed[k] = slices.Clone(v)
	}
	fields, clocks := maps.Clone(s.Fields), maps.Clone(s.Clocks)
	if fields == nil {
		fields = map[string]Value{}
	}
	if clocks == nil {
		clocks = map[string]Clock{}
	}
	return State{Fields: fields, Clocks: clocks, Absorbed: absorbed, Deleted: s.Deleted}
}
