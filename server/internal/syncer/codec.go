package syncer

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/dbgen"
	"github.com/vvangz/JikeLog/server/internal/e2e"
	"github.com/vvangz/JikeLog/server/internal/vault"
)

// Transport 为应用层传输加密会话（*e2e.Session）。
type Transport interface {
	Open(aad, enc string) (string, error)
	Seal(aad, plain string) (string, error)
}

// Record 为下发给客户端的记录；敏感字段已用传输会话加密。
type Record struct {
	Entity    string
	ID        uuid.UUID
	Version   int64
	ServerSeq int64
	Deleted   bool
	Fields    map[string]any
	Clocks    map[string]Clock
	UpdatedAt time.Time
}

// rowState 把存储的记录解码为明文状态。key 为账号数据密钥（没有敏感字段时可为 nil）。
func rowState(e Entity, row dbgen.Record, key []byte) (State, error) {
	fields, err := openFields(e, row.UserID, row.ID, row.Fields, key)
	if err != nil {
		return State{}, err
	}
	var clocks map[string]Clock
	if err := json.Unmarshal(row.Clocks, &clocks); err != nil {
		return State{}, fmt.Errorf("解析字段时钟失败: %w", err)
	}
	var absorbed map[string][]Clock
	if err := json.Unmarshal(row.Absorbed, &absorbed); err != nil {
		return State{}, fmt.Errorf("解析已吸收时钟失败: %w", err)
	}
	return State{Fields: fields, Clocks: clocks, Absorbed: absorbed, Deleted: row.Deleted}, nil
}

// openFields 解码存储的字段 JSON：敏感字段用数据密钥解密。
func openFields(e Entity, userID, recordID uuid.UUID, raw []byte, key []byte) (map[string]Value, error) {
	var stored map[string]json.RawMessage
	if err := json.Unmarshal(raw, &stored); err != nil {
		return nil, fmt.Errorf("解析记录字段失败: %w", err)
	}
	out := make(map[string]Value, len(stored))
	for f, v := range stored {
		spec, ok := e.Fields[f]
		if !ok {
			continue // 已从 schema 移除的历史字段
		}
		var s string
		if spec.Sensitive && json.Unmarshal(v, &s) == nil {
			plain, err := vault.OpenField(key, userID, recordID, f, s)
			if err != nil {
				return nil, fmt.Errorf("解密字段 %s 失败: %w", f, err)
			}
			out[f] = plain
			continue
		}
		val, err := spec.DecodeValue(v)
		if err != nil && string(v) != "null" {
			return nil, fmt.Errorf("解析字段 %s 失败: %w", f, err)
		}
		out[f] = val
	}
	return out, nil
}

// sealFields 把明文字段编码为存储格式：敏感字段用数据密钥加密。
func sealFields(e Entity, userID, recordID uuid.UUID, fields map[string]Value, key []byte) ([]byte, error) {
	out := make(map[string]Value, len(fields))
	for f, v := range fields {
		s, isString := v.(string)
		if e.Fields[f].Sensitive && isString {
			sealed, err := vault.SealField(key, userID, recordID, f, s)
			if err != nil {
				return nil, fmt.Errorf("加密字段 %s 失败: %w", f, err)
			}
			out[f] = sealed
			continue
		}
		out[f] = v
	}
	return json.Marshal(out)
}

// outRecord 生成下发记录：敏感字段用传输会话加密；墓碑不下发字段。
func outRecord(e Entity, id uuid.UUID, version, seq int64, s State, updated time.Time, tr Transport) (*Record, error) {
	rec := &Record{
		Entity: e.Name, ID: id, Version: version, ServerSeq: seq, Deleted: s.Deleted,
		Fields: map[string]any{}, Clocks: s.Clocks, UpdatedAt: updated,
	}
	if s.Deleted {
		rec.Clocks = map[string]Clock{}
		return rec, nil
	}
	sealed, err := transportFields(e, id, s.Fields, tr)
	if err != nil {
		return nil, err
	}
	rec.Fields = sealed
	return rec, nil
}

// transportFields 用传输会话加密敏感字段。需要加密但没有会话时返回 e2e.ErrSessionInvalid。
func transportFields(e Entity, id uuid.UUID, fields map[string]Value, tr Transport) (map[string]any, error) {
	out := make(map[string]any, len(fields))
	for f, v := range fields {
		s, isString := v.(string)
		if !e.Fields[f].Sensitive || !isString {
			out[f] = v
			continue
		}
		if tr == nil {
			return nil, e2e.ErrSessionInvalid
		}
		enc, err := tr.Seal(e2e.AAD(e.Name, id, f, e2e.KindValue), s)
		if err != nil {
			return nil, fmt.Errorf("传输加密失败: %w", err)
		}
		out[f] = enc
	}
	return out, nil
}

func marshalClocks(c map[string]Clock) ([]byte, error) {
	if c == nil {
		c = map[string]Clock{}
	}
	return json.Marshal(c)
}

func marshalAbsorbed(a map[string][]Clock) ([]byte, error) {
	if a == nil {
		a = map[string][]Clock{}
	}
	return json.Marshal(a)
}
