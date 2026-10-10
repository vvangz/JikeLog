package syncer

import (
	"errors"
	"reflect"
	"testing"

	"github.com/vvangz/JikeLog/server/internal/textpatch"
)

const (
	c1 = Clock("1791553544001-0000-aaaaaaaaaaaaaaaa")
	c2 = Clock("1791553544002-0000-bbbbbbbbbbbbbbbb")
	c3 = Clock("1791553544003-0000-aaaaaaaaaaaaaaaa")
	c4 = Clock("1791553544004-0000-bbbbbbbbbbbbbbbb")
)

var worklog = Registry[EntityWorklog]

func serverState() *State {
	return &State{
		Fields: map[string]Value{"date": "2026-10-09", "location": "公司", "content": "上午：周会。\n下午：写代码。"},
		Clocks: map[string]Clock{"date": c1, "location": c1, "content": c1},
	}
}

func TestMergeCreate(t *testing.T) {
	out, err := Merge(worklog, nil, Change{
		Fields: map[string]Value{"date": "2026-10-09", "content": "新日志"},
		Clocks: map[string]Clock{"date": c1, "content": c1},
	})
	if err != nil {
		t.Fatal(err)
	}
	if out.Status != StatusApplied || !out.Changed || out.Next.Fields["content"] != "新日志" || out.Next.Clocks["date"] != c1 {
		t.Fatalf("out=%+v", out)
	}
}

func TestMergeCreateRequiresRequiredFields(t *testing.T) {
	_, err := Merge(worklog, nil, Change{
		Fields: map[string]Value{"content": "缺少日期"},
		Clocks: map[string]Clock{"content": c1},
	})
	var fe FieldErrors
	if !errors.As(err, &fe) || fe["date"] == "" {
		t.Fatalf("err=%v", err)
	}
}

func TestMergeDeletedBeforeFirstSyncIsNoop(t *testing.T) {
	out, err := Merge(worklog, nil, Change{Deleted: true})
	if err != nil || out.Changed || out.Status != StatusApplied {
		t.Fatalf("out=%+v err=%v", out, err)
	}
}

func TestMergeFastForward(t *testing.T) {
	out, err := Merge(worklog, serverState(), Change{
		Fields:     map[string]Value{"location": "家"},
		Clocks:     map[string]Clock{"location": c2},
		BaseClocks: map[string]Clock{"location": c1},
	})
	if err != nil {
		t.Fatal(err)
	}
	if out.Status != StatusApplied || !out.Changed || out.Next.Fields["location"] != "家" || out.Next.Clocks["location"] != c2 {
		t.Fatalf("out=%+v", out)
	}
	if out.Next.Fields["content"] != "上午：周会。\n下午：写代码。" {
		t.Fatal("未修改的字段应保留")
	}
	if len(out.Losers) != 0 {
		t.Fatal("快进不应产生冲突快照")
	}
}

func TestMergeRetryIsIdempotent(t *testing.T) {
	cur := serverState()
	cur.Fields["location"], cur.Clocks["location"] = "家", c2
	out, err := Merge(worklog, cur, Change{
		Fields:     map[string]Value{"location": "家"},
		Clocks:     map[string]Clock{"location": c2},
		BaseClocks: map[string]Clock{"location": c1},
	})
	if err != nil || out.Changed || out.Status != StatusApplied {
		t.Fatalf("重试不应产生新版本：out=%+v err=%v", out, err)
	}
}

func TestMergeTextPatchWhenBothChanged(t *testing.T) {
	cur := serverState()
	cur.Fields["content"], cur.Clocks["content"] = "上午：周会。\n下午：写代码和评审。", c2
	ch := Change{
		Fields:     map[string]Value{"content": "上午：周会，定排期。\n下午：写代码。"},
		Clocks:     map[string]Clock{"content": c3},
		BaseClocks: map[string]Clock{"content": c1},
		Patches: map[string][]textpatch.Hunk{"content": {
			{Pos: 5, Before: "上午：周会", Ins: "，定排期", After: "。\n下午"},
		}},
	}
	out, err := Merge(worklog, cur, ch)
	if err != nil {
		t.Fatal(err)
	}
	want := "上午：周会，定排期。\n下午：写代码和评审。"
	// 合并结果是新的文本，使用新的时钟（大于双方），双方的时钟都记为已吸收
	merged := Clock("1791553544003-0001-" + serverNode)
	if out.Status != StatusMerged || out.Next.Fields["content"] != want || out.Next.Clocks["content"] != merged {
		t.Fatalf("out=%+v", out)
	}
	if !reflect.DeepEqual(out.Next.Absorbed["content"], []Clock{c2, c3}) {
		t.Fatalf("absorbed=%v", out.Next.Absorbed["content"])
	}
	if len(out.Losers) != 0 {
		t.Fatal("合并成功不应产生冲突快照")
	}

	// 合并结果已吸收客户端时钟：同一推送重试时不能再应用一次补丁
	again, err := Merge(worklog, &out.Next, ch)
	if err != nil || again.Changed || again.Next.Fields["content"] != want {
		t.Fatalf("重试应为空操作：%+v err=%v", again, err)
	}
}

func TestMergeRetryAfterMergeWithNewerServerClock(t *testing.T) {
	// 服务端时钟更新于客户端时钟时，合并结果保留服务端时钟；重试仍须识别为已吸收
	cur := serverState()
	cur.Fields["content"], cur.Clocks["content"] = "上午：周会。\n下午：写代码和评审。", c4
	ch := Change{
		Fields:     map[string]Value{"content": "上午：周会，定排期。\n下午：写代码。"},
		Clocks:     map[string]Clock{"content": c3},
		BaseClocks: map[string]Clock{"content": c1},
		Patches: map[string][]textpatch.Hunk{"content": {
			{Pos: 5, Before: "上午：周会", Ins: "，定排期", After: "。\n下午"},
		}},
	}
	out, err := Merge(worklog, cur, ch)
	if err != nil || out.Status != StatusMerged || out.Next.Clocks["content"] != Clock("1791553544004-0001-"+serverNode) {
		t.Fatalf("out=%+v err=%v", out, err)
	}
	again, err := Merge(worklog, &out.Next, ch)
	if err != nil || again.Changed {
		t.Fatalf("重试应为空操作：%+v err=%v", again, err)
	}
}

func TestMergeLastWriterWinsWhenPatchFails(t *testing.T) {
	cur := serverState()
	cur.Fields["content"], cur.Clocks["content"] = "全部重写", c2
	ch := Change{
		Fields:     map[string]Value{"content": "客户端版本"},
		Clocks:     map[string]Clock{"content": c3},
		BaseClocks: map[string]Clock{"content": c1},
		Patches: map[string][]textpatch.Hunk{"content": {
			{Pos: 0, Del: "上午：周会。\n下午：写代码。", Ins: "客户端版本"},
		}},
	}
	out, err := Merge(worklog, cur, ch)
	if err != nil {
		t.Fatal(err)
	}
	if out.Status != StatusConflict || out.Next.Fields["content"] != "客户端版本" || out.Next.Clocks["content"] != c3 {
		t.Fatalf("客户端时钟更新应胜出：%+v", out)
	}
	if len(out.Losers) != 1 || out.Losers[0]["content"] != "全部重写" || out.Losers[0]["date"] != "2026-10-09" {
		t.Fatalf("应保存服务端败方的完整快照：%+v", out.Losers)
	}
}

func TestMergeServerWinsAndClientLoserIsKept(t *testing.T) {
	cur := serverState()
	cur.Fields["location"], cur.Clocks["location"] = "客户现场", c4
	ch := Change{
		Fields:     map[string]Value{"location": "家"},
		Clocks:     map[string]Clock{"location": c3},
		BaseClocks: map[string]Clock{"location": c1},
	}
	out, err := Merge(worklog, cur, ch)
	if err != nil {
		t.Fatal(err)
	}
	if out.Status != StatusConflict || out.Next.Fields["location"] != "客户现场" {
		t.Fatalf("服务端时钟更新应胜出：%+v", out)
	}
	if len(out.Losers) != 1 || out.Losers[0]["location"] != "家" || out.Losers[0]["content"] != cur.Fields["content"] {
		t.Fatalf("应保存客户端败方的完整快照：%+v", out.Losers)
	}
	if !out.Changed {
		t.Fatal("吸收客户端时钟需要持久化")
	}
	again, err := Merge(worklog, &out.Next, ch)
	if err != nil || again.Changed || len(again.Losers) != 0 {
		t.Fatalf("重试不应重复记录冲突：%+v", again)
	}
}

func TestMergeDelete(t *testing.T) {
	out, err := Merge(worklog, serverState(), Change{Deleted: true})
	if err != nil || !out.Changed || !out.Next.Deleted || !out.DeletedNow {
		t.Fatalf("out=%+v err=%v", out, err)
	}
	if out.Next.Fields["content"] == nil {
		t.Fatal("墓碑保留最后内容，便于从修订历史恢复")
	}
	again, _ := Merge(worklog, &out.Next, Change{Deleted: true})
	if again.Changed {
		t.Fatal("重复删除应为空操作")
	}
}

func TestMergeEditAfterDeleteLoses(t *testing.T) {
	cur := serverState()
	cur.Deleted = true
	out, err := Merge(worklog, cur, Change{
		Fields:     map[string]Value{"content": "离线时的修改"},
		Clocks:     map[string]Clock{"content": c4},
		BaseClocks: map[string]Clock{"content": c1},
	})
	if err != nil {
		t.Fatal(err)
	}
	if out.Status != StatusConflict || !out.Next.Deleted {
		t.Fatalf("删除应胜出：%+v", out)
	}
	if len(out.Losers) != 1 || out.Losers[0]["content"] != "离线时的修改" || out.Losers[0]["date"] != "2026-10-09" {
		t.Fatalf("应保存被丢弃的编辑：%+v", out.Losers)
	}
}

func TestMergeRejectsInvalidChanges(t *testing.T) {
	cases := []struct {
		name   string
		entity Entity
		cur    *State
		ch     Change
		field  string
	}{
		{"未知字段", worklog, serverState(), Change{
			Fields: map[string]Value{"title": "x"}, Clocks: map[string]Clock{"title": c2},
		}, "title"},
		{"缺少时钟", worklog, serverState(), Change{
			Fields: map[string]Value{"location": "x"},
		}, "location"},
		{"必填字段清空", worklog, serverState(), Change{
			Fields: map[string]Value{"date": nil}, Clocks: map[string]Clock{"date": c2},
		}, "date"},
		{"服务端字段", Registry[EntityAttachment], &State{Fields: map[string]Value{}, Clocks: map[string]Clock{}}, Change{
			Fields: map[string]Value{"size": int64(1)}, Clocks: map[string]Clock{"size": c2},
		}, "size"},
		{"补丁用于非长文本字段", worklog, serverState(), Change{
			Fields: map[string]Value{"location": "x"}, Clocks: map[string]Clock{"location": c2},
			Patches: map[string][]textpatch.Hunk{"location": {{Ins: "x"}}},
		}, "location"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := Merge(c.entity, c.cur, c.ch)
			var fe FieldErrors
			if !errors.As(err, &fe) || fe[c.field] == "" {
				t.Fatalf("err=%v", err)
			}
		})
	}
}

func TestMergeServerCreatedEntityAllowsDeleteOnly(t *testing.T) {
	att := Registry[EntityAttachment]
	cur := &State{Fields: map[string]Value{"fileName": "a.pdf"}, Clocks: map[string]Clock{"fileName": c1}}
	out, err := Merge(att, cur, Change{Deleted: true})
	if err != nil || !out.Next.Deleted {
		t.Fatalf("应允许删除：%+v err=%v", out, err)
	}
	if _, err := Merge(att, nil, Change{Fields: map[string]Value{}, Clocks: map[string]Clock{}}); err == nil {
		t.Fatal("客户端不能创建附件记录")
	}
}

func TestAbsorbedClocksAreBounded(t *testing.T) {
	cur := serverState()
	cur.Clocks["location"] = Clock("1791553599999-0000-cccccccccccccccc")
	for i := range maxAbsorbed + 5 {
		clk := Clock("1791553544" + string(rune('0'+i/100%10)) + string(rune('0'+i/10%10)) + string(rune('0'+i%10)) + "-0000-aaaaaaaaaaaaaaaa")
		out, err := Merge(worklog, cur, Change{
			Fields:     map[string]Value{"location": "x"},
			Clocks:     map[string]Clock{"location": clk},
			BaseClocks: map[string]Clock{"location": c1},
		})
		if err != nil {
			t.Fatal(err)
		}
		cur = &out.Next
	}
	if got := len(cur.Absorbed["location"]); got != maxAbsorbed {
		t.Fatalf("absorbed=%d", got)
	}
}

func TestCloneDoesNotAlias(t *testing.T) {
	cur := serverState()
	out, _ := Merge(worklog, cur, Change{
		Fields: map[string]Value{"location": "家"}, Clocks: map[string]Clock{"location": c2},
		BaseClocks: map[string]Clock{"location": c1},
	})
	if cur.Fields["location"] != "公司" || cur.Clocks["location"] != c1 {
		t.Fatal("Merge 不能修改传入的状态")
	}
	if reflect.ValueOf(out.Next.Fields).Pointer() == reflect.ValueOf(cur.Fields).Pointer() {
		t.Fatal("返回的状态不能与输入共享 map")
	}
}

// A 推送成功但没收到响应，随后 B 快进覆盖了该字段；A 重试时应识别为已处理，而不是冲突或重复应用补丁。
func TestRetryAfterAnotherDeviceOverwrote(t *testing.T) {
	cur := serverState()
	pushA := Change{
		Fields: map[string]Value{"location": "A 的地点"}, Clocks: map[string]Clock{"location": c2},
		BaseClocks: map[string]Clock{"location": c1},
	}
	afterA, _ := Merge(worklog, cur, pushA)
	afterB, _ := Merge(worklog, &afterA.Next, Change{
		Fields: map[string]Value{"location": "B 的地点"}, Clocks: map[string]Clock{"location": c3},
		BaseClocks: map[string]Clock{"location": c2},
	})
	retry, err := Merge(worklog, &afterB.Next, pushA)
	if err != nil || retry.Changed || len(retry.Losers) != 0 {
		t.Fatalf("重试应为空操作：%+v err=%v", retry, err)
	}
	if retry.Status != StatusMerged || retry.Next.Fields["location"] != "B 的地点" {
		t.Fatalf("应返回服务端记录让客户端以服务端为准：%+v", retry)
	}
}

func TestFastForwardRejectsBackwardClock(t *testing.T) {
	cur := serverState()
	cur.Clocks["location"] = c3
	out, err := Merge(worklog, cur, Change{
		Fields: map[string]Value{"location": "旧时钟"}, Clocks: map[string]Clock{"location": c2},
		BaseClocks: map[string]Clock{"location": c3},
	})
	if err != nil || out.Status != StatusConflict || out.Next.Fields["location"] != "公司" || out.Next.Clocks["location"] != c3 {
		t.Fatalf("时钟倒退时不能快进：%+v err=%v", out, err)
	}
}

func TestRejectsUnknownClockKeys(t *testing.T) {
	cur := serverState()
	cur.Deleted = true
	_, err := Merge(worklog, cur, Change{
		Fields: map[string]Value{}, Clocks: map[string]Clock{"x1": c2}, BaseClocks: map[string]Clock{"x2": c1},
	})
	var fe FieldErrors
	if !errors.As(err, &fe) || fe["x1"] == "" || fe["x2"] == "" {
		t.Fatalf("err=%v", err)
	}
}

// 推送被合并后，客户端在推送的值上继续编辑：以推送的时钟为基准再次推送时必须走补丁合并，
// 不能因为"服务端时钟 = 基准时钟"而快进，抹掉合并进来的对方修改。
func TestEditAfterMergedPushIsMergedAgain(t *testing.T) {
	cur := serverState()
	cur.Fields["content"], cur.Clocks["content"] = "上午：周会。\n下午：写代码和评审。", c2
	first := Change{
		Fields:     map[string]Value{"content": "上午：周会，定排期。\n下午：写代码。"},
		Clocks:     map[string]Clock{"content": c3},
		BaseClocks: map[string]Clock{"content": c1},
		Patches: map[string][]textpatch.Hunk{"content": {
			{Pos: 5, Before: "上午：周会", Ins: "，定排期", After: "。\n下午"},
		}},
	}
	out, _ := Merge(worklog, cur, first)
	second := Change{
		Fields:     map[string]Value{"content": "早上：打卡。\n上午：周会，定排期。\n下午：写代码。"},
		Clocks:     map[string]Clock{"content": c4},
		BaseClocks: map[string]Clock{"content": c3},
		Patches: map[string][]textpatch.Hunk{"content": {
			{Pos: 0, Ins: "早上：打卡。\n", After: "上午：周会，定"},
		}},
	}
	out2, err := Merge(worklog, &out.Next, second)
	want := "早上：打卡。\n上午：周会，定排期。\n下午：写代码和评审。"
	if err != nil || out2.Status != StatusMerged || out2.Next.Fields["content"] != want {
		t.Fatalf("out=%+v err=%v", out2, err)
	}
}

func TestClockAfter(t *testing.T) {
	if got := clockAfter(c3); got != Clock("1791553544003-0001-"+serverNode) {
		t.Fatalf("got %s", got)
	}
	if got := clockAfter(Clock("1791553544003-ffff-aaaaaaaaaaaaaaaa")); got != Clock("1791553544004-0000-"+serverNode) {
		t.Fatalf("计数溢出时进位到下一毫秒：%s", got)
	}
}
