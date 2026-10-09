package syncer

import (
	"encoding/json"
	"time"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/e2e"
	"github.com/vvangz/JikeLog/server/internal/textpatch"
)

// 单条变更被拒绝时的错误码。
const (
	CodeUnknownEntity = "UNKNOWN_ENTITY"
	CodeInvalidChange = "VALIDATION_FAILED"
	CodeClockSkew     = "CLOCK_SKEW"
	CodeIDConflict    = "ID_CONFLICT"
	CodeDecryptFailed = e2e.CodeDecryptFailed
)

// IncomingChange 为推送请求中的一条变更（未解密、未校验）。
type IncomingChange struct {
	Entity     string
	ID         uuid.UUID
	Deleted    bool
	Fields     map[string]json.RawMessage
	Clocks     map[string]string
	BaseClocks map[string]string
	// Patches 为长文本字段的补丁（JSON 字符串）；敏感字段的补丁为传输密文。
	Patches map[string]string
}

// ChangeError 为单条变更被拒绝的原因。
type ChangeError struct {
	Code    string
	Message string
	Fields  map[string]string
}

func invalid(fields map[string]string) *ChangeError {
	return &ChangeError{Code: CodeInvalidChange, Message: "字段校验失败", Fields: fields}
}

// decodeChange 校验并解密一条变更。返回的 error 表示整个请求无法继续（如缺少加密会话）。
func decodeChange(in IncomingChange, tr Transport, now time.Time) (Entity, Change, *ChangeError, error) {
	e, ok := Registry[in.Entity]
	if !ok {
		return Entity{}, Change{}, &ChangeError{Code: CodeUnknownEntity, Message: "未知的实体类型"}, nil
	}
	ch := Change{Deleted: in.Deleted, Fields: map[string]Value{}, Patches: map[string][]textpatch.Hunk{}}
	clocks, cerr := parseClocks(in.Clocks, now, true)
	if cerr != nil {
		return e, ch, cerr, nil
	}
	base, cerr := parseClocks(in.BaseClocks, now, false)
	if cerr != nil {
		return e, ch, cerr, nil
	}
	ch.Clocks, ch.BaseClocks = clocks, base
	errs := map[string]string{}
	for f, raw := range in.Fields {
		v, msg, err := decodeField(e, in.ID, f, raw, tr)
		if err != nil {
			return e, ch, nil, err
		}
		if msg != "" {
			errs[f] = msg
			continue
		}
		ch.Fields[f] = v
	}
	for f, p := range in.Patches {
		hunks, msg, err := decodePatch(e, in.ID, f, p, tr)
		if err != nil {
			return e, ch, nil, err
		}
		if msg != "" {
			errs[f] = msg
			continue
		}
		ch.Patches[f] = hunks
	}
	if len(errs) > 0 {
		if decryptFailed(errs) {
			return e, ch, &ChangeError{Code: CodeDecryptFailed, Message: "加密数据校验失败", Fields: errs}, nil
		}
		return e, ch, invalid(errs), nil
	}
	return e, ch, nil, nil
}

const msgDecrypt = "加密数据校验失败"

func decryptFailed(errs map[string]string) bool {
	for _, m := range errs {
		if m == msgDecrypt {
			return true
		}
	}
	return false
}

// decodeField 解码一个字段值；敏感字段先用传输会话解密。返回校验提示（非空表示该字段非法）。
func decodeField(e Entity, id uuid.UUID, f string, raw json.RawMessage, tr Transport) (Value, string, error) {
	spec, ok := e.Fields[f]
	if !ok {
		return nil, "未知字段", nil
	}
	if !spec.Sensitive || string(raw) == "null" {
		v, err := spec.DecodeValue(raw)
		if err != nil {
			return nil, err.Error(), nil
		}
		return v, "", nil
	}
	var enc string
	if json.Unmarshal(raw, &enc) != nil {
		return nil, "敏感字段必须加密传输", nil
	}
	if tr == nil {
		return nil, "", e2e.ErrSessionInvalid
	}
	plain, err := tr.Open(e2e.AAD(e.Name, id, f, e2e.KindValue), enc)
	if err != nil {
		return nil, msgDecrypt, nil
	}
	v, err := spec.CheckValue(plain)
	if err != nil {
		return nil, err.Error(), nil
	}
	return v, "", nil
}

func decodePatch(e Entity, id uuid.UUID, f, p string, tr Transport) ([]textpatch.Hunk, string, error) {
	spec, ok := e.Fields[f]
	if !ok || spec.Kind != KindText {
		return nil, "该字段不支持补丁", nil
	}
	plain := p
	if spec.Sensitive {
		if tr == nil {
			return nil, "", e2e.ErrSessionInvalid
		}
		var err error
		if plain, err = tr.Open(e2e.AAD(e.Name, id, f, e2e.KindPatch), p); err != nil {
			return nil, msgDecrypt, nil
		}
	}
	hunks, err := textpatch.Parse(plain, spec.MaxLen)
	if err != nil {
		return nil, err.Error(), nil
	}
	return hunks, "", nil
}

func parseClocks(in map[string]string, now time.Time, checkSkew bool) (map[string]Clock, *ChangeError) {
	out := make(map[string]Clock, len(in))
	errs := map[string]string{}
	for f, s := range in {
		c, err := ParseClock(s)
		switch {
		case err != nil:
			errs[f] = err.Error()
		case checkSkew && c.TooFarAhead(now):
			return nil, &ChangeError{Code: CodeClockSkew, Message: "设备时间比服务器快太多，请校准系统时间后重试"}
		default:
			out[f] = c
		}
	}
	if len(errs) > 0 {
		return nil, invalid(errs)
	}
	return out, nil
}
