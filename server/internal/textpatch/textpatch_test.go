package textpatch

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type sharedCase struct {
	Name     string  `json:"name"`
	Base     string  `json:"base"`
	Hunks    []Hunk  `json:"hunks"`
	Current  string  `json:"current"`
	Expected *string `json:"expected"`
}

// 与 Dart 端共用的用例，保证两端对同一补丁的应用结果一致。
func TestApplySharedCases(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "testdata", "textpatch", "cases.json"))
	if err != nil {
		t.Fatal(err)
	}
	var file struct {
		Cases []sharedCase `json:"cases"`
	}
	if err := json.Unmarshal(raw, &file); err != nil {
		t.Fatal(err)
	}
	if len(file.Cases) == 0 {
		t.Fatal("没有读到用例")
	}
	for _, c := range file.Cases {
		t.Run(c.Name, func(t *testing.T) {
			got, ok := Apply(c.Current, c.Hunks, nil)
			if c.Expected == nil {
				if ok {
					t.Fatalf("应当失败，却得到 %q", got)
				}
				if got != c.Current {
					t.Fatalf("失败时应原样返回当前文本，得到 %q", got)
				}
				return
			}
			if !ok {
				t.Fatalf("应用失败，期望 %q", *c.Expected)
			}
			if got != *c.Expected {
				t.Fatalf("得到 %q，期望 %q", got, *c.Expected)
			}
			// 应用到基准文本本身也必须成功（补丁自洽）
			if _, ok := Apply(c.Base, c.Hunks, nil); !ok && c.Name != "后一个片段不能落在前一个片段的修改之前" {
				t.Fatal("补丁无法应用到自己的基准文本")
			}
		})
	}
}

func TestApplyEmptyPatchReturnsText(t *testing.T) {
	got, ok := Apply("不变", nil, nil)
	if !ok || got != "不变" {
		t.Fatalf("got %q ok=%v", got, ok)
	}
}

func TestParse(t *testing.T) {
	hunks, err := Parse(`[{"p":1,"b":"a","d":"","i":"X","a":"b"}]`, 100)
	if err != nil || len(hunks) != 1 || hunks[0].Ins != "X" {
		t.Fatalf("hunks=%v err=%v", hunks, err)
	}

	bad := []struct {
		name, in string
	}{
		{"非 JSON", `not json`},
		{"负位置", `[{"p":-1,"b":"","d":"","i":"x","a":""}]`},
		{"位置递减", `[{"p":5,"b":"","d":"","i":"x","a":""},{"p":2,"b":"","d":"","i":"y","a":""}]`},
		{"空片段", `[{"p":0,"b":"a","d":"","i":"","a":"b"}]`},
		{"超长", `[{"p":0,"b":"","d":"","i":"` + strings.Repeat("长", 101) + `","a":""}]`},
	}
	for _, c := range bad {
		t.Run(c.name, func(t *testing.T) {
			if _, err := Parse(c.in, 100); err == nil {
				t.Fatal("应当报错")
			}
		})
	}
}

func TestParseRejectsTooManyHunks(t *testing.T) {
	parts := make([]string, maxHunks+1)
	for i := range parts {
		parts[i] = `{"p":0,"b":"","d":"","i":"x","a":""}`
	}
	if _, err := Parse("["+strings.Join(parts, ",")+"]", 1<<20); err == nil {
		t.Fatal("片段过多应当报错")
	}
}

// 构造的病态输入（长串重复字符）也必须在线性时间内完成，避免被用来消耗 CPU。
func TestApplyPathologicalInputIsFast(t *testing.T) {
	text := strings.Repeat("a", 100_000)
	hunks := []Hunk{{Pos: 50_000, Before: strings.Repeat("a", maxContext), Del: strings.Repeat("a", 50_000) + "b", Ins: "x"}}
	done := make(chan struct{})
	go func() {
		defer close(done)
		if _, ok := Apply(text, hunks, nil); ok {
			t.Error("不应匹配")
		}
	}()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("应用补丁超时")
	}
}

func TestParseRejectsLongContext(t *testing.T) {
	in := `[{"p":0,"b":"` + strings.Repeat("a", maxContext+1) + `","d":"","i":"x","a":""}]`
	if _, err := Parse(in, 1<<20); err == nil {
		t.Fatal("上下文过长应当报错")
	}
}

// 只在提示位置前后 searchWindow 之内查找；更远的匹配视为对方改动过大，按冲突处理。
func TestApplySearchesOnlyNearHint(t *testing.T) {
	text := "目标" + strings.Repeat("x", searchWindow+10)
	far := []Hunk{{Pos: searchWindow + 5, Del: "目标", Ins: "改"}}
	if _, ok := Apply(text, far, nil); ok {
		t.Fatal("超出搜索范围不应匹配")
	}
	near := []Hunk{{Pos: 3, Del: "目标", Ins: "改"}}
	if got, ok := Apply(text, near, nil); !ok || !strings.HasPrefix(got, "改x") {
		t.Fatalf("附近的匹配应成功：ok=%v", ok)
	}
}

// 同一请求内的多次 Apply 共享预算，耗尽后一律失败。
func TestApplyStopsWhenBudgetExhausted(t *testing.T) {
	text := strings.Repeat("a", 1000) + "b"
	hunks := []Hunk{{Pos: 1000, Del: "b", Ins: "c"}}
	budget := NewBudget(5000)
	_, ok1 := Apply(text, hunks, budget)
	ok2 := true
	for range 10 {
		if _, ok2 = Apply(text, hunks, budget); !ok2 {
			break
		}
	}
	if !ok1 || ok2 {
		t.Fatalf("第一次应成功、预算耗尽后应失败：ok1=%v ok2=%v", ok1, ok2)
	}
}
