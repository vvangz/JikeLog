package export

import (
	"cmp"
	"slices"
	"strconv"
	"strings"

	"github.com/vvangz/JikeLog/server/internal/syncer"
)

// 记账枚举值的中文名（与 App 一致，见 ADR-009）。
var (
	entryTypeLabel = map[string]string{
		"income": "收入", "expense": "支出", "transfer": "转账",
		"lend": "借出", "borrow": "借入", "collect": "收款", "repay": "还款",
	}
	accountTypeLabel = map[string]string{ //nolint:gosec // 账户类型的中文名，不是凭据
		"cash": "现金", "debit": "储蓄卡", "credit": "信用卡", "alipay": "支付宝", "wechat": "微信", "other": "其他",
	}
	categoryKindLabel  = map[string]string{"expense": "支出", "income": "收入"}
	loanDirectionLabel = map[string]string{"lend": "借出", "borrow": "借入"}
)

// label 返回枚举值的中文名；未知的值原样返回。
func label(m map[string]string, v string) string {
	if l, ok := m[v]; ok {
		return l
	}
	return v
}

// cents 解析以分为单位的金额字段；缺失或格式不对时为 0。
func cents(f map[string]syncer.Value, key string) money {
	n, _ := strconv.ParseInt(str(f, key), 10, 64)
	return money(n)
}

// writeLedger 写出记账：一个含四个工作表的 xlsx，以及与之对应的四个 CSV。
func (a *archive) writeLedger(d *dataset) error {
	if !d.has(ModuleLedger) {
		return nil
	}
	tables := ledgerTables(d)
	dir := moduleLabel[ModuleLedger]
	w, err := a.create(a.names.unique(dir, "记账", ".xlsx"))
	if err != nil {
		return err
	}
	if err := writeXLSX(w, tables); err != nil {
		return err
	}
	for _, t := range tables {
		cw, err := a.create(a.names.unique(dir, t.name, ".csv"))
		if err != nil {
			return err
		}
		if err := writeCSV(cw, t); err != nil {
			return err
		}
	}
	return nil
}

func ledgerTables(d *dataset) []table {
	accounts := sortedBy(d.records(syncer.EntityLedgerAccount), "sortOrder")
	categories := sortedBy(d.records(syncer.EntityLedgerCategory), "sortOrder")
	loans := slices.Clone(d.records(syncer.EntityLedgerLoan))
	entries := slices.Clone(d.records(syncer.EntityLedgerEntry))
	slices.SortStableFunc(entries, func(x, y syncer.Snapshot) int {
		if c := strings.Compare(str(x.Fields, "date"), str(y.Fields, "date")); c != 0 {
			return c
		}
		return x.UpdatedAt.Compare(y.UpdatedAt)
	})

	accountName := map[string]string{}
	for _, r := range accounts {
		accountName[r.ID.String()] = str(r.Fields, "name")
	}
	catName := categoryNames(categories)
	who := map[string]string{}
	for _, r := range loans {
		who[r.ID.String()] = str(r.Fields, "counterparty")
	}

	entryTable := table{name: "流水", header: []string{"日期", "类型", "金额", "手续费", "账户", "转入账户", "分类", "借贷对方", "备注"}}
	for _, r := range entries {
		f := r.Fields
		entryTable.rows = append(entryTable.rows, []any{
			str(f, "date"), label(entryTypeLabel, str(f, "type")), cents(f, "amount"), cents(f, "fee"),
			accountName[str(f, "accountId")], accountName[str(f, "toAccountId")],
			catName[str(f, "categoryId")], who[str(f, "loanId")], str(f, "note"),
		})
	}
	accountTable := table{name: "账户", header: []string{"名称", "类型", "初始余额", "已隐藏"}}
	for _, r := range accounts {
		f := r.Fields
		accountTable.rows = append(accountTable.rows, []any{
			str(f, "name"), label(accountTypeLabel, str(f, "type")), cents(f, "initialBalance"), flag(f, "archived"),
		})
	}
	categoryTable := table{name: "分类", header: []string{"名称", "收支", "上级分类", "已隐藏"}}
	for _, r := range categories {
		f := r.Fields
		categoryTable.rows = append(categoryTable.rows, []any{
			str(f, "name"), label(categoryKindLabel, str(f, "kind")), catName[str(f, "parentId")], flag(f, "archived"),
		})
	}
	loanTable := table{name: "借贷", header: []string{"方向", "对方", "到期日", "已结清", "备注"}}
	for _, r := range loans {
		f := r.Fields
		loanTable.rows = append(loanTable.rows, []any{
			label(loanDirectionLabel, str(f, "direction")), str(f, "counterparty"), str(f, "dueDate"),
			flag(f, "settled"), str(f, "note"),
		})
	}
	return []table{entryTable, accountTable, categoryTable, loanTable}
}

// categoryNames 返回分类 ID → 显示名；二级分类写成"上级 / 名称"。
func categoryNames(categories []syncer.Snapshot) map[string]string {
	own := map[string]string{}
	for _, r := range categories {
		own[r.ID.String()] = str(r.Fields, "name")
	}
	out := map[string]string{}
	for _, r := range categories {
		name := own[r.ID.String()]
		if parent, ok := own[str(r.Fields, "parentId")]; ok {
			name = parent + " / " + name
		}
		out[r.ID.String()] = name
	}
	return out
}

// sortedBy 按整数字段排序（相同时按 ID，结果稳定）。
func sortedBy(list []syncer.Snapshot, field string) []syncer.Snapshot {
	out := slices.Clone(list)
	slices.SortStableFunc(out, func(x, y syncer.Snapshot) int {
		if c := cmp.Compare(num(x.Fields, field), num(y.Fields, field)); c != 0 {
			return c
		}
		return strings.Compare(x.ID.String(), y.ID.String())
	})
	return out
}
