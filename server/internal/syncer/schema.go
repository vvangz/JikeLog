package syncer

import (
	"encoding/json"
	"fmt"
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
}

// Entity 为同步实体定义。
type Entity struct {
	Name   string
	Fields map[string]Field
	// ServerCreated 为 true 时客户端不能创建或修改该实体，只能删除（如附件，由上传流程创建）。
	ServerCreated bool
}

// 实体名称。
const (
	EntityWorklog    = "worklog"
	EntityAttachment = "attachment"
)

// 字段长度上限。
const (
	maxLocationLen = 100
	maxContentLen  = 100_000
	maxFileNameLen = 255
)

// Registry 为全部同步实体，新模块在此登记即可接入同步（ADR-005）。
var Registry = map[string]Entity{
	EntityWorklog: {
		Name: EntityWorklog,
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
	if f.Kind == KindInt {
		var n int64
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, fmt.Errorf("必须是整数")
		}
		return n, nil
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
		if f.Kind != KindInt {
			return nil, fmt.Errorf("必须是字符串")
		}
		return x, nil
	case string:
		if f.Kind == KindInt {
			return nil, fmt.Errorf("必须是整数")
		}
		return f.checkString(x)
	default:
		return nil, fmt.Errorf("类型不支持")
	}
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
	default:
		if f.MaxLen > 0 && utf8.RuneCountInString(s) > f.MaxLen {
			return nil, fmt.Errorf("不能超过 %d 个字符", f.MaxLen)
		}
		if f.Required && s == "" {
			return nil, fmt.Errorf("不能为空")
		}
	}
	return s, nil
}
