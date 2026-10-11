package export

import (
	"context"
	"slices"
	"strings"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/syncer"
)

// Module 为可以导出的模块。
type Module string

// 各模块的取值，与接口中的 ExportModule 一致。
const (
	ModuleWorklog Module = "worklog"
	ModuleNote    Module = "note"
	ModuleMemo    Module = "memo"
	ModuleLedger  Module = "ledger"
)

// Modules 为全部模块，按导出顺序排列。
var Modules = []Module{ModuleWorklog, ModuleNote, ModuleMemo, ModuleLedger}

// moduleLabel 为模块的中文名，也是 zip 中的目录名。
var moduleLabel = map[Module]string{
	ModuleWorklog: "工作日志", ModuleNote: "笔记", ModuleMemo: "备忘录", ModuleLedger: "记账",
}

// moduleEntities 为各模块包含的同步实体。
var moduleEntities = map[Module][]string{
	ModuleWorklog: {syncer.EntityWorklog},
	ModuleNote:    {syncer.EntityNote, syncer.EntityNoteFolder},
	ModuleMemo:    {syncer.EntityMemo},
	ModuleLedger: {
		syncer.EntityLedgerAccount, syncer.EntityLedgerCategory,
		syncer.EntityLedgerLoan, syncer.EntityLedgerEntry,
	},
}

// attachmentOwners 为可以带附件的模块。
var attachmentOwners = map[string]Module{syncer.EntityWorklog: ModuleWorklog, syncer.EntityNote: ModuleNote}

// RecordSource 逐条读取账号的明文记录（*syncer.Service 实现）。
type RecordSource interface {
	EachRecord(ctx context.Context, userID uuid.UUID, entities []string, fn func(syncer.Snapshot) error) (int, error)
}

// dataset 为一次导出读取到的全部记录。
type dataset struct {
	modules  []Module
	byEntity map[string][]syncer.Snapshot
	// attachments 为属于所选模块中现有记录的附件，按所属记录分组。
	attachments map[uuid.UUID][]syncer.Snapshot
	// skipped 为无法解密或解析、未能导出的记录数。
	skipped int
}

// load 读取所选模块的全部有效记录（模块按 Modules 的顺序排列）。
func load(ctx context.Context, src RecordSource, userID uuid.UUID, modules []Module) (*dataset, error) {
	d := &dataset{byEntity: map[string][]syncer.Snapshot{}, attachments: map[uuid.UUID][]syncer.Snapshot{}}
	var entities []string
	for _, m := range Modules {
		if slices.Contains(modules, m) {
			d.modules = append(d.modules, m)
			entities = append(entities, moduleEntities[m]...)
		}
	}
	withAttachments := slices.Contains(d.modules, ModuleWorklog) || slices.Contains(d.modules, ModuleNote)
	if withAttachments {
		entities = append(entities, syncer.EntityAttachment)
	}
	var atts []syncer.Snapshot
	var err error
	d.skipped, err = src.EachRecord(ctx, userID, entities, func(s syncer.Snapshot) error {
		if s.Entity == syncer.EntityAttachment {
			atts = append(atts, s)
		} else {
			d.byEntity[s.Entity] = append(d.byEntity[s.Entity], s)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	owners := map[uuid.UUID]bool{}
	for e, m := range attachmentOwners {
		if slices.Contains(d.modules, m) {
			for _, r := range d.byEntity[e] {
				owners[r.ID] = true
			}
		}
	}
	for _, a := range atts {
		if owner, err := uuid.Parse(str(a.Fields, "ownerId")); err == nil && owners[owner] {
			d.attachments[owner] = append(d.attachments[owner], a)
		}
	}
	return d, nil
}

func (d *dataset) has(m Module) bool { return slices.Contains(d.modules, m) }

// records 返回某个实体的记录。
func (d *dataset) records(entity string) []syncer.Snapshot { return d.byEntity[entity] }

// allAttachments 返回全部附件（按所属记录、文件名排序，结果稳定）。
func (d *dataset) allAttachments() []syncer.Snapshot {
	var out []syncer.Snapshot
	for _, list := range d.attachments {
		out = append(out, list...)
	}
	slices.SortFunc(out, func(a, b syncer.Snapshot) int {
		if c := strings.Compare(str(a.Fields, "ownerId"), str(b.Fields, "ownerId")); c != 0 {
			return c
		}
		return strings.Compare(a.ID.String(), b.ID.String())
	})
	return out
}

// str 读取字符串字段；不存在或类型不符时为空串。
func str(f map[string]syncer.Value, key string) string {
	s, _ := f[key].(string)
	return s
}

// num 读取整数字段；不存在或类型不符时为 0。
func num(f map[string]syncer.Value, key string) int64 {
	n, _ := f[key].(int64)
	return n
}

// flag 读取开关字段。
func flag(f map[string]syncer.Value, key string) bool { return num(f, key) == 1 }
