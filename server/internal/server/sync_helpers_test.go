package server

import (
	"crypto/ecdh"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/e2e"
	"github.com/vvangz/JikeLog/server/internal/platform/crypto"
	"github.com/vvangz/JikeLog/server/internal/syncer"
)

// e2eClient 模拟 App 端的传输加密会话。
type e2eClient struct {
	sid string
	key []byte
}

// handshake 以临时 X25519 密钥建立传输加密会话。
func (a *testApp) handshake(s session) e2eClient {
	a.t.Helper()
	priv, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		a.t.Fatal(err)
	}
	serverPriv, err := crypto.ParseX25519PrivateKey(testE2EPrivateKey)
	if err != nil {
		a.t.Fatal(err)
	}
	serverPub := serverPriv.PublicKey()
	r := a.call(http.MethodPost, "/api/v1/sync/e2e/session", map[string]any{
		"clientPublicKey": base64.StdEncoding.EncodeToString(priv.PublicKey().Bytes()),
		"serverKeyId":     crypto.KeyID(serverPub),
	}, s.access)
	a.expect(r, http.StatusCreated, "")
	key, err := crypto.DeriveSessionKey(priv, serverPub, priv.PublicKey().Bytes(), serverPub.Bytes())
	if err != nil {
		a.t.Fatal(err)
	}
	return e2eClient{sid: r.str("data", "sessionId"), key: key}
}

func (c e2eClient) seal(entity, id, field, kind, plain string) string {
	out, err := crypto.SealString(c.key, plain, []byte(e2e.AAD(entity, uuid.MustParse(id), field, kind)))
	if err != nil {
		panic(err)
	}
	return out
}

func (c e2eClient) open(entity, id, field, enc string) (string, error) {
	return crypto.OpenString(c.key, enc, []byte(e2e.AAD(entity, uuid.MustParse(id), field, e2e.KindValue)))
}

func (c e2eClient) headers() map[string]string { return map[string]string{e2e.HeaderName: c.sid} }

// hlc 返回测试时钟上偏移 offsetMs 毫秒的 HLC。
func (a *testApp) hlc(offsetMs int64, node string) string {
	return fmt.Sprintf("%013d-0000-%s", a.clock.Now().UnixMilli()+offsetMs, node)
}

const (
	nodeA = "aaaaaaaaaaaaaaaa"
	nodeB = "bbbbbbbbbbbbbbbb"
)

// worklogChange 构造一条变更（默认为工作日志）：schema 中的敏感字段自动加密。
type worklogChange struct {
	entity     string // 为空时为 worklog
	id         string
	fields     map[string]any // 明文；nil 值表示清空
	clocks     map[string]string
	baseClocks map[string]string
	patches    map[string]string // 明文 JSON
	deleted    bool
}

func (c e2eClient) encode(ch worklogChange) map[string]any {
	entity := ch.entity
	if entity == "" {
		entity = syncer.EntityWorklog
	}
	spec := syncer.Registry[entity].Fields
	fields := map[string]any{}
	for f, v := range ch.fields {
		if s, ok := v.(string); ok && spec[f].Sensitive {
			fields[f] = c.seal(entity, ch.id, f, e2e.KindValue, s)
			continue
		}
		fields[f] = v
	}
	patches := map[string]any{}
	for f, p := range ch.patches {
		if spec[f].Sensitive {
			p = c.seal(entity, ch.id, f, e2e.KindPatch, p)
		}
		patches[f] = p
	}
	out := map[string]any{"entity": entity, "id": ch.id, "fields": fields, "clocks": ch.clocks, "patches": patches}
	if ch.baseClocks != nil {
		out["baseClocks"] = ch.baseClocks
	}
	if ch.deleted {
		out["deleted"] = true
	}
	return out
}

func (a *testApp) push(s session, c e2eClient, changes ...map[string]any) apiResp {
	a.t.Helper()
	return a.callWith(http.MethodPost, "/api/v1/sync/push", map[string]any{"changes": changes}, s.access, c.headers())
}

func (a *testApp) pull(s session, c e2eClient, since int64) apiResp {
	a.t.Helper()
	return a.callWith(http.MethodGet, "/api/v1/sync/pull?since="+strconv.FormatInt(since, 10), nil, s.access, c.headers())
}

// results 返回推送响应中的逐条结果。
func (r apiResp) results() []map[string]any {
	list, _ := r.data()["results"].([]any)
	out := make([]map[string]any, len(list))
	for i, v := range list {
		out[i], _ = v.(map[string]any)
	}
	return out
}

func (r apiResp) records() []map[string]any {
	list, _ := r.data()["records"].([]any)
	out := make([]map[string]any, len(list))
	for i, v := range list {
		out[i], _ = v.(map[string]any)
	}
	return out
}

func num(m map[string]any, k string) int64 {
	f, _ := m[k].(float64)
	return int64(f)
}

func patchJSON(hunks ...map[string]any) string {
	b, _ := json.Marshal(hunks)
	return string(b)
}

func newID() string { return uuid.Must(uuid.NewV7()).String() }
