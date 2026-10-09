// Package textpatch 实现带上下文的文本补丁，用于同步时合并两台设备对同一段长文本的并发修改。
//
// 补丁由客户端相对"最后同步的基准文本"生成（见 ADR-005），服务端把它应用到当前文本上：
// 在提示位置附近查找"前文+删除内容+后文"，找到就把删除内容替换为插入内容。
// 位置一律按 Unicode 码点计数，与 Dart 端（runes）一致；两端共用 testdata/textpatch 的用例。
package textpatch

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"
)

const (
	// maxHunks 为单个补丁的片段数上限，防止构造大量片段消耗 CPU。
	maxHunks = 200
	// maxContext 为前后文的最大码点数；客户端默认 4 个，为消除歧义最多扩展到 32 个。
	maxContext = 64
)

// Hunk 为补丁中的一个片段。Pos 为删除内容在基准文本中的起始码点位置，仅作定位提示。
type Hunk struct {
	Pos    int    `json:"p"`
	Before string `json:"b"`
	Del    string `json:"d"`
	Ins    string `json:"i"`
	After  string `json:"a"`
}

// Parse 解析并校验 JSON 形式的补丁。maxRunes 为每个文本片段的最大码点数（通常取字段长度上限）。
func Parse(s string, maxRunes int) ([]Hunk, error) {
	var hunks []Hunk
	if err := json.Unmarshal([]byte(s), &hunks); err != nil {
		return nil, errors.New("补丁格式错误")
	}
	if len(hunks) > maxHunks {
		return nil, fmt.Errorf("补丁片段不能超过 %d 个", maxHunks)
	}
	last := 0
	for i, h := range hunks {
		if h.Pos < 0 || h.Pos < last {
			return nil, errors.New("补丁片段位置必须非负且递增")
		}
		last = h.Pos
		if h.Del == "" && h.Ins == "" {
			return nil, fmt.Errorf("补丁第 %d 个片段没有任何修改", i+1)
		}
		if utf8.RuneCountInString(h.Before) > maxContext || utf8.RuneCountInString(h.After) > maxContext {
			return nil, errors.New("补丁上下文过长")
		}
		if utf8.RuneCountInString(h.Del) > maxRunes || utf8.RuneCountInString(h.Ins) > maxRunes {
			return nil, errors.New("补丁片段过长")
		}
	}
	return hunks, nil
}

// Apply 把补丁依次应用到 text 上。任一片段找不到匹配位置（对方改了同一处）时返回原文和 false。
func Apply(text string, hunks []Hunk) (string, bool) {
	out := text
	delta := 0   // 已应用片段造成的长度变化（码点），用于修正后续片段的提示位置
	minDel := 0  // 后续片段的删除起点不能早于上一个片段插入内容的末尾
	lastPos := 0 // 片段必须按位置递增
	for _, h := range hunks {
		if h.Pos < lastPos {
			return text, false
		}
		lastPos = h.Pos
		nb := utf8.RuneCountInString(h.Before)
		start := nearestMatch(out, h.Before+h.Del+h.After, h.Pos+delta-nb, minDel-nb)
		if start < 0 {
			return text, false
		}
		delStart := start + nb
		nd, ni := utf8.RuneCountInString(h.Del), utf8.RuneCountInString(h.Ins)
		bs := byteOffset(out, delStart)
		out = out[:bs] + h.Ins + out[bs+len(h.Del):]
		delta += ni - nd
		minDel = delStart + ni
	}
	return out, true
}

// nearestMatch 在 s 中查找 target，返回起点（码点）不小于 lowest 且离 expected 最近的位置；没有时返回 -1。
// 用 strings.Index 逐个查找出现位置，总代价与文本长度线性相关。
func nearestMatch(s, target string, expected, lowest int) int {
	lowest = max(lowest, 0)
	pos := byteOffset(s, lowest) // 当前搜索起点（字节）
	if pos < 0 {
		return -1
	}
	runeAt := lowest // pos 对应的码点位置
	best := -1
	for pos <= len(s) {
		i := strings.Index(s[pos:], target)
		if i < 0 {
			break
		}
		runeAt += utf8.RuneCountInString(s[pos : pos+i])
		if best >= 0 && runeAt-expected > abs(best-expected) {
			break // 之后的匹配只会更远
		}
		if best < 0 || abs(runeAt-expected) < abs(best-expected) {
			best = runeAt
		}
		// 从下一个码点继续查找（允许重叠匹配）
		_, size := utf8.DecodeRuneInString(s[pos+i:])
		if size == 0 {
			break // 已到末尾（target 为空串时）
		}
		pos += i + size
		runeAt++
	}
	return best
}

// byteOffset 返回第 n 个码点的字节偏移；n 超过码点总数时返回 -1。
func byteOffset(s string, n int) int {
	if n == 0 {
		return 0
	}
	count := 0
	for i := range s {
		if count == n {
			return i
		}
		count++
	}
	if count == n {
		return len(s)
	}
	return -1
}

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}
