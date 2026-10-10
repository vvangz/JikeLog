package syncer

import (
	"encoding/json"
	"fmt"
	"slices"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
)

// Kind 为字段值类型。
type Kind int

const (
	// KindString 为普通字符串（整体覆盖）。
	KindString Kind = iota
	// KindText 为长文本，两端并发修改时可用文本补丁合并。
	KindText
	// KindDate 为日期，格式 YYYY-MM-DD。
	KindDate
	// KindInt 为整数。
	KindInt
	// KindUUID 为 UUID 字符串。
	KindUUID
	// KindFlag 为开关，只能是 0 或 1。
	KindFlag
	// KindTime 为时刻：Unix 毫秒（UTC），范围为 2000–2199 年。
	KindTime
	// KindOffsets 为提前提醒的分钟数列表：升序、不重复、逗号分隔，如 "0,15,1440"；空串表示不提醒。
	KindOffsets
)

// Field 为字段定义。
type Field struct {
	Kind Kind
	// MaxLen 为字符串类字段的最大码点数。
	MaxLen   int
	Required bool
	// Sensitive 字段在传输时做应用层加密、落库时做信封加密（ADR-006）。
	Sensitive bool
	// ServerOnly 字段只能由服务端写入（如附件大小、校验和），客户端推送时拒绝。
	ServerOnly bool
	// Choices 非空时，字符串字段只能取其中之一。
	Choices []string
}

// Entity 为同步实体定义。
type Entity struct {
	Name   string
	Fields map[string]Field
	// ServerCreated 为 true 时客户端不能创建或修改该实体，只能删除（如附件，由上传流程创建）。
	ServerCreated bool
	// Attachable 为 true 时可以为该实体的记录添加附件。
	Attachable bool
}

// 实体名称。
const (
	EntityWorklog    = "worklog"
	EntityAttachment = "attachment"
	EntityNote       = "note"
	EntityNoteFolder = "note_folder"
	EntityMemo       = "memo"
)

// 字段长度上限。
const (
	maxLocationLen = 100
	maxContentLen  = 100_000
	maxFileNameLen = 255

	maxTitleLen      = 200
	maxFolderNameLen = 50
	// 标签与关联的工作日志为多行文本，每行一个（ADR-007）。
	maxTagsLen     = 2_000
	maxWorklogsLen = 8_000

	maxMemoLen = 5_000
)

// 备忘录提醒：最多 MaxReminders 个，每个最多提前 MaxReminderOffset 分钟（与用户设置中的默认提醒一致）。
const (
	MaxReminders      = 5
	MaxReminderOffset = 30 * 24 * 60
)

// KindTime 的取值范围：2000-01-01 至 2200-01-01（UTC，不含）。
const (
	minTimeMillis = 946_684_800_000
	maxTimeMillis = 7_258_118_400_000
)

// 笔记格式：两种格式的正文都是 Markdown，只决定默认用哪种编辑方式打开（ADR-007）。
var noteFormats = []string{"markdown", "rich"}

// Registry 为全部同步实体，新模块在此登记即可接入同步（ADR-005）。
var Registry = map[string]Entity{
	EntityWorklog: {
		Name:       EntityWorklog,
		Attachable: true,
		Fields: map[string]Field{
			"date":     {Kind: KindDate, Required: true},
			"location": {Kind: KindString, MaxLen: maxLocationLen, Sensitive: true},
			"content":  {Kind: KindText, MaxLen: maxContentLen, Sensitive: true},
		},
	},
	EntityAttachment: {
		Name:          EntityAttachment,
		ServerCreated: true,
		Fields: map[string]Field{
			"ownerEntity": {Kind: KindString, MaxLen: 32, Required: true, ServerOnly: true},
			"ownerId":     {Kind: KindUUID, Required: true, ServerOnly: true},
			"fileName":    {Kind: KindString, MaxLen: maxFileNameLen, Required: true, Sensitive: true, ServerOnly: true},
			"mime":        {Kind: KindString, MaxLen: 127, Required: true, ServerOnly: true},
			"size":        {Kind: KindInt, Required: true, ServerOnly: true},
			"sha256":      {Kind: KindString, MaxLen: 64, Required: true, ServerOnly: true},
		},
	},
	EntityNoteFolder: {
		Name: EntityNoteFolder,
		Fields: map[string]Field{
			"name":     {Kind: KindString, MaxLen: maxFolderNameLen, Required: true, Sensitive: true},
			"parentId": {Kind: KindUUID},
		},
	},
	EntityNote: {
		Name:       EntityNote,
		Attachable: true,
		Fields: map[string]Field{
			"title":    {Kind: KindString, MaxLen: maxTitleLen, Sensitive: true},
			"body":     {Kind: KindText, MaxLen: maxContentLen, Sensitive: true},
			"format":   {Kind: KindString, Required: true, Choices: noteFormats},
			"folderId": {Kind: KindUUID},
			"favorite": {Kind: KindFlag},
			"pinned":   {Kind: KindFlag},
			"tags":     {Kind: KindText, MaxLen: maxTagsLen, Sensitive: true},
			"worklogs": {Kind: KindText, MaxLen: maxWorklogsLen},
		},
	},
	// 备忘录（ADR-008）：时间与提醒不加密，服务端据此按时推送。
	EntityMemo: {
		Name: EntityMemo,
		Fields: map[string]Field{
			"content":   {Kind: KindText, MaxLen: maxMemoLen, Required: true, Sensitive: true},
			"at":        {Kind: KindTime, Required: true},
			"allDay":    {Kind: KindFlag},
			"reminders": {Kind: KindOffsets},
			"done":      {Kind: KindFlag},
		},
	},
}

// Value 为字段值：string、int64 或 nil（清空）。
type Value = any

// DecodeValue 按字段定义解析 JSON 值。null 表示清空字段。
func (f Field) DecodeValue(raw json.RawMessage) (Value, error) {
	if string(raw) == "null" {
		if f.Required {
			return nil, fmt.Errorf("不能为空")
		}
		return nil, nil
	}
	if f.isInt() {
		var n int64
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, fmt.Errorf("必须是整数")
		}
		return f.checkInt(n)
	}
	var s string
	if err := json.Unmarshal(raw, &s); err != nil {
		return nil, fmt.Errorf("必须是字符串")
	}
	return f.checkString(s)
}

// CheckValue 校验已解码的值（用于服务端写入与解密后的敏感字段）。
func (f Field) CheckValue(v Value) (Value, error) {
	switch x := v.(type) {
	case nil:
		if f.Required {
			return nil, fmt.Errorf("不能为空")
		}
		return nil, nil
	case int64:
		if !f.isInt() {
			return nil, fmt.Errorf("必须是字符串")
		}
		return f.checkInt(x)
	case string:
		if f.isInt() {
			return nil, fmt.Errorf("必须是整数")
		}
		return f.checkString(x)
	default:
		return nil, fmt.Errorf("类型不支持")
	}
}

func (f Field) isInt() bool { return f.Kind == KindInt || f.Kind == KindFlag || f.Kind == KindTime }

func (f Field) checkInt(n int64) (Value, error) {
	if f.Kind == KindFlag && n != 0 && n != 1 {
		return nil, fmt.Errorf("只能是 0 或 1")
	}
	if f.Kind == KindTime && (n < minTimeMillis || n >= maxTimeMillis) {
		return nil, fmt.Errorf("时间超出范围")
	}
	return n, nil
}

func (f Field) checkString(s string) (Value, error) {
	if !utf8.ValidString(s) {
		return nil, fmt.Errorf("不是合法的 UTF-8 文本")
	}
	switch f.Kind {
	case KindDate:
		if _, err := time.Parse(time.DateOnly, s); err != nil {
			return nil, fmt.Errorf("日期格式应为 YYYY-MM-DD")
		}
	case KindUUID:
		if _, err := uuid.Parse(s); err != nil || len(s) != 36 {
			return nil, fmt.Errorf("必须是 UUID")
		}
	case KindOffsets:
		if err := checkOffsets(s); err != nil {
			return nil, err
		}
	default:
		if f.MaxLen > 0 && utf8.RuneCountInString(s) > f.MaxLen {
			return nil, fmt.Errorf("不能超过 %d 个字符", f.MaxLen)
		}
		if f.Required && s == "" {
			return nil, fmt.Errorf("不能为空")
		}
		if len(f.Choices) > 0 && !slices.Contains(f.Choices, s) {
			return nil, fmt.Errorf("只能是 %s 之一", strings.Join(f.Choices, "、"))
		}
	}
	return s, nil
}

// checkOffsets 校验提醒列表为规范形式（升序、不重复、无前导零），使各端写出的值逐字相同。
func checkOffsets(s string) error {
	if s == "" {
		return nil
	}
	parts := strings.Split(s, ",")
	if len(parts) > MaxReminders {
		return fmt.Errorf("最多设置 %d 个提醒", MaxReminders)
	}
	prev := -1
	for _, p := range parts {
		n, err := strconv.Atoi(p)
		if err != nil || strconv.Itoa(n) != p {
			return fmt.Errorf("提醒必须是分钟数")
		}
		if n < 0 || n > MaxReminderOffset {
			return fmt.Errorf("提前提醒范围为 0 分钟到 30 天")
		}
		if n <= prev {
			return fmt.Errorf("提醒必须升序且不重复")
		}
		prev = n
	}
	return nil
}

// ParseOffsets 解析已校验的提醒列表。
func ParseOffsets(s string) []int {
	if s == "" {
		return nil
	}
	parts := strings.Split(s, ",")
	out := make([]int, 0, len(parts))
	for _, p := range parts {
		if n, err := strconv.Atoi(p); err == nil {
			out = append(out, n)
		}
	}
	return out
}
