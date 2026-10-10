package server

import (
	"context"
	"net/http"
	"strings"
	"testing"
)

func TestLedgerSyncEncryptsAmountsAndNames(t *testing.T) {
	a := newTestApp(t)
	d1, d2 := a.twoDevices("ledger01")
	c1, c2 := a.handshake(d1), a.handshake(d2)
	acc, cat, loan, entry, lend := newID(), newID(), newID(), newID(), newID()
	k := a.hlc(0, nodeA)
	clocks := func(fields map[string]any) map[string]string {
		out := map[string]string{}
		for f := range fields {
			out[f] = k
		}
		return out
	}
	change := func(entity, id string, fields map[string]any) map[string]any {
		return c1.encode(worklogChange{entity: entity, id: id, fields: fields, clocks: clocks(fields)})
	}
	r := a.push(d1, c1,
		change("ledger_account", acc, map[string]any{"name": "招商银行储蓄卡", "type": "debit", "initialBalance": "1234500"}),
		change("ledger_category", cat, map[string]any{"name": "餐饮", "kind": "expense", "icon": "restaurant"}),
		change("ledger_loan", loan, map[string]any{"direction": "lend", "counterparty": "李四", "dueDate": "2026-12-31"}),
		change("ledger_entry", entry, map[string]any{
			"type": "expense", "amount": "3850", "date": "2026-10-11", "accountId": acc, "categoryId": cat, "note": "午饭",
		}),
		change("ledger_entry", lend, map[string]any{
			"type": "lend", "amount": "500000", "date": "2026-10-11", "accountId": acc, "loanId": loan,
		}),
	)
	a.expect(r, http.StatusOK, "")
	for _, res := range r.results() {
		if res["status"] != "applied" {
			t.Fatalf("推送应成功：%v", res)
		}
	}

	var stored strings.Builder
	rows, err := a.pool.Query(context.Background(), "SELECT fields::text FROM records WHERE entity LIKE 'ledger_%'")
	if err != nil {
		t.Fatal(err)
	}
	for rows.Next() {
		var s string
		if err := rows.Scan(&s); err != nil {
			t.Fatal(err)
		}
		stored.WriteString(s)
	}
	rows.Close()
	for _, plain := range []string{"招商银行", "1234500", "餐饮", "李四", "3850", "午饭", "500000"} {
		if strings.Contains(stored.String(), plain) {
			t.Fatalf("%q 应加密落库：%s", plain, stored.String())
		}
	}
	if !strings.Contains(stored.String(), `"expense"`) || !strings.Contains(stored.String(), acc) {
		t.Fatalf("类型与关联 ID 应为明文：%s", stored.String())
	}

	got := map[string]map[string]any{}
	for _, rec := range a.pull(d2, c2, 0).records() {
		got[rec["id"].(string)] = rec["fields"].(map[string]any)
	}
	amount, err1 := c2.open("ledger_entry", entry, "amount", got[entry]["amount"].(string))
	name, err2 := c2.open("ledger_account", acc, "name", got[acc]["name"].(string))
	who, err3 := c2.open("ledger_loan", loan, "counterparty", got[loan]["counterparty"].(string))
	if err1 != nil || err2 != nil || err3 != nil || amount != "3850" || name != "招商银行储蓄卡" || who != "李四" {
		t.Fatalf("另一台设备应能解密：%q %q %q (%v %v %v)", amount, name, who, err1, err2, err3)
	}
}

func TestLedgerRejectsInvalidAmounts(t *testing.T) {
	a := newTestApp(t)
	d1, _ := a.twoDevices("ledger02")
	c1 := a.handshake(d1)
	k := a.hlc(0, nodeA)
	acc := newID()
	for _, amount := range []string{"0", "-100", "12.50", "abc"} {
		fields := map[string]any{"type": "expense", "amount": amount, "date": "2026-10-11", "accountId": acc}
		clocks := map[string]string{"type": k, "amount": k, "date": k, "accountId": k}
		r := a.push(d1, c1, c1.encode(worklogChange{entity: "ledger_entry", id: newID(), fields: fields, clocks: clocks}))
		if r.results()[0]["status"] != "rejected" {
			t.Fatalf("金额 %q 应被拒绝：%v", amount, r.results()[0])
		}
	}
}

// 两台设备各自写入同一 ID 的预置分类（时钟逐字相同）：合并为同一条，不产生冲突。
func TestLedgerPresetSeededOnTwoDevicesDoesNotConflict(t *testing.T) {
	a := newTestApp(t)
	d1, d2 := a.twoDevices("ledger03")
	c1, c2 := a.handshake(d1), a.handshake(d2)
	id := newID()
	const seed = "0000000000000-0000-0000000000000000"
	fields := map[string]any{"name": "餐饮", "kind": "expense", "icon": "restaurant", "archived": 0, "sortOrder": 0}
	clocks := map[string]string{}
	for f := range fields {
		clocks[f] = seed
	}
	for _, d := range []struct {
		s session
		c e2eClient
	}{{d1, c1}, {d2, c2}} {
		r := a.push(d.s, d.c, d.c.encode(worklogChange{entity: "ledger_category", id: id, fields: fields, clocks: clocks}))
		a.expect(r, http.StatusOK, "")
		if st := r.results()[0]["status"]; st == "conflict" || st == "rejected" {
			t.Fatalf("预置记录不应冲突：%v", r.results()[0])
		}
	}
	var revisions int
	if err := a.pool.QueryRow(context.Background(), "SELECT count(*) FROM record_revisions WHERE record_id = $1", id).Scan(&revisions); err != nil || revisions != 0 {
		t.Fatalf("不应保存冲突版本：%d %v", revisions, err)
	}
}
