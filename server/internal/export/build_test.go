package export

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"io"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/xuri/excelize/v2"

	"github.com/vvangz/JikeLog/server/internal/platform/storage"
	"github.com/vvangz/JikeLog/server/internal/syncer"
)

var (
	shanghai, _ = time.LoadLocation("Asia/Shanghai")
	exportTime  = time.Date(2026, 10, 11, 9, 30, 0, 0, shanghai)
)

func snap(entity string, id uuid.UUID, fields map[string]syncer.Value) syncer.Snapshot {
	return syncer.Snapshot{Entity: entity, ID: id, Fields: fields, UpdatedAt: exportTime}
}

// fakeRecords 为内存中的记录来源。
type fakeRecords []syncer.Snapshot

func (f fakeRecords) EachRecord(_ context.Context, _ uuid.UUID, entities []string, fn func(syncer.Snapshot) error) error {
	for _, s := range f {
		if slices.Contains(entities, s.Entity) {
			if err := fn(s); err != nil {
				return err
			}
		}
	}
	return nil
}

func ids(n int) []uuid.UUID {
	out := make([]uuid.UUID, n)
	for i := range out {
		out[i] = uuid.Must(uuid.NewV7())
	}
	return out
}

// sample 为覆盖四个模块的一组记录。
func sample() (fakeRecords, map[string]uuid.UUID) {
	id := ids(14)
	m := map[string]uuid.UUID{
		"worklog": id[0], "note": id[1], "folder": id[2], "sub": id[3], "img": id[4], "pdf": id[5], "memo": id[6],
		"acc": id[7], "food": id[8], "lunch": id[9], "loan": id[10], "entry": id[11], "lend": id[12], "orphan": id[13],
	}
	at := time.Date(2026, 10, 12, 15, 0, 0, 0, shanghai).UnixMilli()
	return fakeRecords{
		snap(syncer.EntityWorklog, m["worklog"], map[string]syncer.Value{"date": "2026-10-09", "location": "上海", "content": "**评审**会议"}),
		snap(syncer.EntityNoteFolder, m["folder"], map[string]syncer.Value{"name": "工作"}),
		snap(syncer.EntityNoteFolder, m["sub"], map[string]syncer.Value{"name": "周报/月报", "parentId": m["folder"].String()}),
		snap(syncer.EntityNote, m["note"], map[string]syncer.Value{
			"title": "", "body": "# 第 41 周\n\n![截图](attachment:" + m["img"].String() + ")\n完成评审",
			"folderId": m["sub"].String(), "tags": "工作\n周报\n工作", "favorite": int64(1),
		}),
		snap(syncer.EntityAttachment, m["img"], map[string]syncer.Value{"ownerEntity": "note", "ownerId": m["note"].String(), "fileName": "截图.png"}),
		snap(syncer.EntityAttachment, m["pdf"], map[string]syncer.Value{"ownerEntity": "worklog", "ownerId": m["worklog"].String(), "fileName": "方案 (终版).pdf"}),
		// 所属记录不存在的附件不导出
		snap(syncer.EntityAttachment, m["orphan"], map[string]syncer.Value{"ownerEntity": "note", "ownerId": uuid.NewString(), "fileName": "x.txt"}),
		snap(syncer.EntityMemo, m["memo"], map[string]syncer.Value{
			"content": "交房租; 带上合同, 和钥匙\n第二行", "at": at, "allDay": int64(0), "reminders": "0,15,1440", "done": int64(0),
		}),
		snap(syncer.EntityLedgerAccount, m["acc"], map[string]syncer.Value{"name": "钱包", "type": "cash", "initialBalance": "-1050", "sortOrder": int64(1)}),
		snap(syncer.EntityLedgerCategory, m["food"], map[string]syncer.Value{"name": "餐饮", "kind": "expense"}),
		snap(syncer.EntityLedgerCategory, m["lunch"], map[string]syncer.Value{"name": "午餐", "kind": "expense", "parentId": m["food"].String()}),
		snap(syncer.EntityLedgerLoan, m["loan"], map[string]syncer.Value{"direction": "lend", "counterparty": "李四", "dueDate": "2026-12-31", "settled": int64(0)}),
		snap(syncer.EntityLedgerEntry, m["entry"], map[string]syncer.Value{
			"type": "expense", "amount": "3850", "date": "2026-10-11", "accountId": m["acc"].String(), "categoryId": m["lunch"].String(), "note": "牛肉面",
		}),
		snap(syncer.EntityLedgerEntry, m["lend"], map[string]syncer.Value{
			"type": "lend", "amount": "500000", "date": "2026-10-10", "accountId": m["acc"].String(), "loanId": m["loan"].String(),
		}),
	}, m
}

// buildZip 生成导出文件并解开，返回路径 → 内容。
func buildZip(t *testing.T, recs fakeRecords, modules []Module, open func(context.Context, uuid.UUID) (io.ReadCloser, error)) (map[string][]byte, summary) {
	t.Helper()
	ctx := context.Background()
	d, err := load(ctx, recs, uuid.New(), modules)
	if err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	sum, err := build(ctx, &buf, d, buildOptions{Now: exportTime, Location: shanghai, Open: open})
	if err != nil {
		t.Fatal(err)
	}
	zr, err := zip.NewReader(bytes.NewReader(buf.Bytes()), int64(buf.Len()))
	if err != nil {
		t.Fatal(err)
	}
	files := map[string][]byte{}
	for _, f := range zr.File {
		if f.Flags&0x800 == 0 && f.Name != "README.txt" && f.Name != "data.json" {
			t.Errorf("%s 应标记为 UTF-8 文件名", f.Name)
		}
		r, err := f.Open()
		if err != nil {
			t.Fatal(err)
		}
		b, _ := io.ReadAll(r)
		_ = r.Close()
		files[f.Name] = b
	}
	return files, sum
}

func fileOpener(missing ...uuid.UUID) func(context.Context, uuid.UUID) (io.ReadCloser, error) {
	return func(_ context.Context, id uuid.UUID) (io.ReadCloser, error) {
		if slices.Contains(missing, id) {
			return nil, storage.ErrNotFound
		}
		return io.NopCloser(strings.NewReader("file:" + id.String())), nil
	}
}

func names(files map[string][]byte) []string {
	var out []string
	for n := range files {
		out = append(out, n)
	}
	slices.Sort(out)
	return out
}

func TestBuildAllModulesWithAttachments(t *testing.T) {
	recs, id := sample()
	files, sum := buildZip(t, recs, Modules, fileOpener())
	want := []string{
		"README.txt", "data.json",
		"备忘录/备忘录.csv", "备忘录/备忘录.ics",
		"工作日志/2026-10-09.md", "工作日志/工作日志.xlsx",
		"笔记/工作/周报_月报/第 41 周.md",
		"记账/借贷.csv", "记账/分类.csv", "记账/流水.csv", "记账/记账.xlsx", "记账/账户.csv",
		"附件/" + id["img"].String() + "/截图.png",
		"附件/" + id["pdf"].String() + "/方案 (终版).pdf",
	}
	slices.Sort(want)
	if got := names(files); !slices.Equal(got, want) {
		t.Fatalf("文件列表：\n%v\nwant\n%v", got, want)
	}
	if sum.Attachments != 2 || sum.Missing != 0 || sum.Records[syncer.EntityLedgerEntry] != 2 {
		t.Fatalf("统计：%+v", sum)
	}
	if string(files["附件/"+id["img"].String()+"/截图.png"]) != "file:"+id["img"].String() {
		t.Fatal("附件内容应原样复制")
	}

	note := string(files["笔记/工作/周报_月报/第 41 周.md"])
	for _, s := range []string{
		"title: \"第 41 周\"", "tags: [\"工作\",\"周报\"]", "favorite: true",
		"](<../../../附件/" + id["img"].String() + "/截图.png>)", "完成评审",
	} {
		if !strings.Contains(note, s) {
			t.Errorf("笔记应包含 %q：\n%s", s, note)
		}
	}
	if strings.Contains(note, "## 附件") {
		t.Errorf("正文中已显示的图片不再单独列出：\n%s", note)
	}
	log := string(files["工作日志/2026-10-09.md"])
	for _, s := range []string{"# 2026-10-09 工作日志", "- 地点：上海", "**评审**会议", "- [方案 (终版).pdf](<../附件/" + id["pdf"].String() + "/方案 (终版).pdf>)"} {
		if !strings.Contains(log, s) {
			t.Errorf("工作日志应包含 %q：\n%s", s, log)
		}
	}

	var data struct {
		Modules []string                     `json:"modules"`
		Records map[string][]json.RawMessage `json:"records"`
	}
	if err := json.Unmarshal(files["data.json"], &data); err != nil {
		t.Fatal(err)
	}
	if len(data.Modules) != 4 || len(data.Records["attachment"]) != 2 || len(data.Records["ledger_category"]) != 2 {
		t.Fatalf("data.json：%v %d", data.Modules, len(data.Records["attachment"]))
	}
	if !bytes.Contains(files["data.json"], []byte("牛肉面")) {
		t.Fatal("data.json 应包含解密后的字段")
	}
	if !strings.Contains(string(files["README.txt"]), "2 个附件文件") {
		t.Fatalf("README：%s", files["README.txt"])
	}
}

func TestLedgerTables(t *testing.T) {
	recs, _ := sample()
	files, _ := buildZip(t, recs, []Module{ModuleLedger}, nil)
	csv := string(files["记账/流水.csv"])
	if !strings.HasPrefix(csv, "\xEF\xBB\xBF日期,类型,金额,手续费,账户,转入账户,分类,借贷对方,备注\r\n") {
		t.Fatalf("CSV 应带 BOM 与表头：%q", csv[:40])
	}
	for _, s := range []string{
		"2026-10-10,借出,5000.00,0.00,钱包,,,李四,\r\n",
		"2026-10-11,支出,38.50,0.00,钱包,,餐饮 / 午餐,,牛肉面\r\n",
	} {
		if !strings.Contains(csv, s) {
			t.Errorf("流水应包含 %q：\n%s", s, csv)
		}
	}
	if !strings.Contains(string(files["记账/账户.csv"]), "钱包,现金,-10.50,否") {
		t.Errorf("账户：%s", files["记账/账户.csv"])
	}

	f, err := excelize.OpenReader(bytes.NewReader(files["记账/记账.xlsx"]))
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = f.Close() }()
	if got := f.GetSheetList(); !slices.Equal(got, []string{"流水", "账户", "分类", "借贷"}) {
		t.Fatalf("工作表：%v", got)
	}
	rows, err := f.GetRows("流水")
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 3 || rows[2][2] != "38.50" || rows[2][6] != "餐饮 / 午餐" {
		t.Fatalf("流水工作表：%v", rows)
	}
	if v, _ := f.GetCellValue("流水", "C3", excelize.Options{RawCellValue: true}); v != "38.5" {
		t.Fatalf("金额应为数字：%q", v)
	}
	if _, ok := files["工作日志/工作日志.xlsx"]; ok {
		t.Fatal("未选择的模块不导出")
	}
	if strings.Contains(string(files["README.txt"]), "附件/") {
		t.Fatal("只导出记账时不提附件目录")
	}
}

func TestMemoCalendarAndCSV(t *testing.T) {
	recs, id := sample()
	allDay := snap(syncer.EntityMemo, uuid.New(), map[string]syncer.Value{
		"content": "体检", "at": time.Date(2026, 10, 20, 0, 0, 0, 0, shanghai).UnixMilli(), "allDay": int64(1), "reminders": "", "done": int64(1),
	})
	files, _ := buildZip(t, append(recs, allDay), []Module{ModuleMemo}, nil)
	ics := string(files["备忘录/备忘录.ics"])
	for _, s := range []string{
		"BEGIN:VCALENDAR\r\n", "UID:" + id["memo"].String() + "@jikelog\r\n",
		"DTSTART:20261012T070000Z\r\n", "SUMMARY:交房租\\; 带上合同\\, 和钥匙\r\n",
		"DESCRIPTION:交房租\\; 带上合同\\, 和钥匙\\n第二行\r\n",
		"TRIGGER:-PT0M\r\n", "TRIGGER:-PT15M\r\n", "TRIGGER:-PT1440M\r\n",
		"DTSTART;VALUE=DATE:20261020\r\n", "DTEND;VALUE=DATE:20261021\r\n", "SUMMARY:[已完成] 体检\r\n",
		"END:VCALENDAR\r\n",
	} {
		if !strings.Contains(ics, s) {
			t.Errorf("ICS 应包含 %q：\n%s", s, ics)
		}
	}
	if strings.Count(ics, "BEGIN:VALARM") != 3 {
		t.Error("已完成的备忘不带提醒")
	}
	for _, line := range strings.Split(ics, "\r\n") {
		if len(line) > 75 {
			t.Errorf("行超过 75 字节：%q", line)
		}
	}
	csv := string(files["备忘录/备忘录.csv"])
	if !strings.Contains(csv, "2026-10-12 15:00,否,") || !strings.Contains(csv, "准时、提前 15 分钟、提前 1 天,否") ||
		!strings.Contains(csv, "2026-10-20,是,体检,,是") {
		t.Errorf("CSV：\n%s", csv)
	}
}

func TestBuildWithoutAttachmentFilesOrMissingFiles(t *testing.T) {
	recs, id := sample()
	files, _ := buildZip(t, recs, []Module{ModuleNote, ModuleWorklog}, nil)
	for n := range files {
		if strings.HasPrefix(n, "附件/") {
			t.Fatalf("不包含附件文件：%s", n)
		}
	}
	note := string(files["笔记/工作/周报_月报/第 41 周.md"])
	if !strings.Contains(note, "(attachment:"+id["img"].String()+")") {
		t.Errorf("不包含附件文件时保留原引用：\n%s", note)
	}
	if !strings.Contains(string(files["工作日志/2026-10-09.md"]), "- 方案 (终版).pdf\n") {
		t.Error("不包含附件文件时只列名称")
	}
	if !strings.Contains(string(files["README.txt"]), "未包含附件文件") {
		t.Error("README 应说明未包含附件")
	}

	files, sum := buildZip(t, recs, []Module{ModuleNote, ModuleWorklog}, fileOpener(id["pdf"]))
	if sum.Attachments != 1 || sum.Missing != 1 {
		t.Fatalf("统计：%+v", sum)
	}
	if !strings.Contains(string(files["README.txt"]), "另有 1 个附件") {
		t.Errorf("README：%s", files["README.txt"])
	}
}

func TestSameNamesAreNumbered(t *testing.T) {
	a, b, c := uuid.New(), uuid.New(), uuid.New()
	recs := fakeRecords{
		snap(syncer.EntityNote, a, map[string]syncer.Value{"title": "Plan", "body": ""}),
		snap(syncer.EntityNote, b, map[string]syncer.Value{"title": "plan", "body": ""}),
		snap(syncer.EntityNote, c, map[string]syncer.Value{"title": "", "body": "![图](attachment:x)"}),
	}
	files, _ := buildZip(t, recs, []Module{ModuleNote}, nil)
	for _, n := range []string{"笔记/Plan.md", "笔记/plan (2).md", "笔记/无标题笔记.md"} {
		if _, ok := files[n]; !ok {
			t.Errorf("缺少 %s：%v", n, names(files))
		}
	}
}

func TestSafeNameAndPaths(t *testing.T) {
	cases := []struct{ in, want string }{
		{`a/b\c:d*e?f"g<h>i|j`, "a_b_c_d_e_f_g_h_i_j"},
		{" .隐藏. ", "隐藏"},
		{"", "默认"},
		{"..", "默认"},
		{"line" + string(rune(10)) + "break", "line_break"},
		{strings.Repeat("长", 100), strings.Repeat("长", maxNameRunes)},
	}
	for _, c := range cases {
		if got := safeName(c.in, "默认"); got != c.want {
			t.Errorf("safeName(%q)=%q want %q", c.in, got, c.want)
		}
	}
	if relPath("笔记/工作", "附件/x") != "../../附件/x" || relPath("", "附件/x") != "附件/x" {
		t.Error("relPath")
	}
	if fileExt("报告.final.PDF") != ".PDF" || fileExt("没有扩展名") != "" || fileExt(".bashrc") != "" || fileExt("a.toolongextension") != "" {
		t.Error("fileExt")
	}
}

func TestFoldICSKeepsMultibyteRunes(t *testing.T) {
	line := "DESCRIPTION:" + strings.Repeat("中", 40)
	folded := foldICS(line)
	for _, l := range strings.Split(strings.TrimSuffix(folded, "\r\n"), "\r\n") {
		if len(l) > 75 || !strings.HasPrefix(strings.TrimPrefix(l, " "), "") {
			t.Fatalf("折行错误：%q", l)
		}
	}
	if strings.ReplaceAll(strings.TrimSuffix(folded, "\r\n"), "\r\n ", "") != line {
		t.Fatal("展开后应与原文相同")
	}
}

func TestClipCellAndMoney(t *testing.T) {
	long := strings.Repeat("字", maxCellRunes+10)
	got := clipCell(long)
	if n := len([]rune(got)); n != maxCellRunes || !strings.HasSuffix(got, truncatedNote) {
		t.Fatalf("截断后长度 %d", n)
	}
	for c, want := range map[money]string{0: "0.00", 5: "0.05", -1050: "-10.50", 123456789: "1234567.89"} {
		if c.String() != want {
			t.Errorf("money(%d)=%s", c, c.String())
		}
	}
}

func TestNormalizeModules(t *testing.T) {
	got, err := normalize([]Module{ModuleLedger, ModuleWorklog, ModuleLedger})
	if err != nil || !slices.Equal(got, []string{"worklog", "ledger"}) {
		t.Fatalf("%v %v", got, err)
	}
	if _, err := normalize(nil); err == nil {
		t.Fatal("至少选一个模块")
	}
	if _, err := normalize([]Module{"photos"}); err == nil {
		t.Fatal("未知模块")
	}
}

func TestFolderCycleIsCut(t *testing.T) {
	a, b := uuid.New(), uuid.New()
	paths := folderPaths([]syncer.Snapshot{
		snap(syncer.EntityNoteFolder, a, map[string]syncer.Value{"name": "A", "parentId": b.String()}),
		snap(syncer.EntityNoteFolder, b, map[string]syncer.Value{"name": "B", "parentId": a.String()}),
	})
	if paths[a.String()] != "B/A" || paths[b.String()] != "A/B" {
		t.Fatalf("%v", paths)
	}
}
