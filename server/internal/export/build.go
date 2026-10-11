package export

import (
	"archive/zip"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/platform/storage"
	"github.com/vvangz/JikeLog/server/internal/syncer"
)

// attachmentDir 为 zip 中存放附件文件的目录。
const attachmentDir = "附件"

// buildOptions 为生成导出文件的参数。
type buildOptions struct {
	Now time.Time
	// Location 为显示日期时间所用的时区（发起导出的设备所在时区）。
	Location *time.Location
	// Open 读取附件文件；为 nil 时不包含附件文件。
	Open func(ctx context.Context, attachmentID uuid.UUID) (io.ReadCloser, error)
}

// summary 为导出内容的统计。
type summary struct {
	Records     map[string]int
	Attachments int
	// Missing 为对象存储中找不到的附件数（已被删除或从未上传完成）。
	Missing int
}

// archive 向 zip 中写入文件。
type archive struct {
	zw    *zip.Writer
	names *namer
	now   time.Time
	loc   *time.Location
	// attPaths 为附件 ID → zip 中的路径（只在包含附件文件时有值）。
	attPaths map[uuid.UUID]string
}

// create 新建一个文件（路径须已通过 namer 去重）。
func (a *archive) create(name string) (io.Writer, error) {
	w, err := a.zw.CreateHeader(&zip.FileHeader{Name: name, Method: zip.Deflate, Modified: a.now})
	if err != nil {
		return nil, fmt.Errorf("写入 %s 失败: %w", name, err)
	}
	return w, nil
}

func (a *archive) write(name string, data []byte) error {
	w, err := a.create(name)
	if err != nil {
		return err
	}
	_, err = w.Write(data)
	return err
}

// build 把数据集写成 zip。
func build(ctx context.Context, out io.Writer, d *dataset, o buildOptions) (summary, error) {
	zw := zip.NewWriter(out)
	a := &archive{zw: zw, names: newNamer(), now: o.Now, loc: o.Location, attPaths: map[uuid.UUID]string{}}
	if o.Open != nil {
		for _, att := range d.allAttachments() {
			dir := attachmentDir + "/" + att.ID.String()
			a.attPaths[att.ID] = a.names.unique(dir, safeName(fileStem(str(att.Fields, "fileName")), "附件"), fileExt(str(att.Fields, "fileName")))
		}
	}
	steps := []func() error{
		func() error { return a.writeJSON(d) },
		func() error { return a.writeWorklogs(d) },
		func() error { return a.writeNotes(d) },
		func() error { return a.writeMemos(d) },
		func() error { return a.writeLedger(d) },
	}
	for _, step := range steps {
		if err := step(); err != nil {
			return summary{}, err
		}
	}
	sum := summary{Records: map[string]int{}}
	for e, list := range d.byEntity {
		sum.Records[e] = len(list)
	}
	if o.Open != nil {
		if err := a.writeAttachments(ctx, d, o.Open, &sum); err != nil {
			return summary{}, err
		}
	}
	if err := a.write("README.txt", readme(d, sum, o)); err != nil {
		return summary{}, err
	}
	if err := zw.Close(); err != nil {
		return summary{}, fmt.Errorf("生成 zip 失败: %w", err)
	}
	return sum, nil
}

// writeAttachments 从对象存储逐个复制附件文件。找不到的附件跳过并计数。
func (a *archive) writeAttachments(ctx context.Context, d *dataset, open func(context.Context, uuid.UUID) (io.ReadCloser, error), sum *summary) error {
	for _, att := range d.allAttachments() {
		r, err := open(ctx, att.ID)
		if errors.Is(err, storage.ErrNotFound) {
			sum.Missing++
			continue
		}
		if err != nil {
			return fmt.Errorf("读取附件失败: %w", err)
		}
		w, err := a.create(a.attPaths[att.ID])
		if err == nil {
			_, err = io.Copy(w, r)
		}
		_ = r.Close()
		if err != nil {
			return fmt.Errorf("写入附件失败: %w", err)
		}
		sum.Attachments++
	}
	return nil
}

// jsonRecord 为 data.json 中的一条记录。
type jsonRecord struct {
	ID        uuid.UUID               `json:"id"`
	UpdatedAt time.Time               `json:"updatedAt"`
	Fields    map[string]syncer.Value `json:"fields"`
}

// writeJSON 写出全部记录（解密后的字段），可用于备份与迁移。
func (a *archive) writeJSON(d *dataset) error {
	records := map[string][]jsonRecord{}
	add := func(entity string, list []syncer.Snapshot) {
		for _, s := range list {
			records[entity] = append(records[entity], jsonRecord{ID: s.ID, UpdatedAt: s.UpdatedAt.UTC(), Fields: s.Fields})
		}
	}
	for e, list := range d.byEntity {
		add(e, list)
	}
	add(syncer.EntityAttachment, d.allAttachments())
	w, err := a.create(a.names.unique("", "data", ".json"))
	if err != nil {
		return err
	}
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	return enc.Encode(map[string]any{
		"app":        "即刻日志",
		"format":     1,
		"exportedAt": a.now.UTC(),
		"modules":    d.modules,
		"records":    records,
	})
}

// attachmentLink 返回从 dir 指向附件文件的相对路径；不包含附件文件时为空。
func (a *archive) attachmentLink(dir string, id uuid.UUID) string {
	p, ok := a.attPaths[id]
	if !ok {
		return ""
	}
	return relPath(dir, p)
}

// attachmentList 生成"附件"一节：包含附件文件时为链接，否则只列文件名。
func (a *archive) attachmentList(dir string, atts []syncer.Snapshot) string {
	if len(atts) == 0 {
		return ""
	}
	var b strings.Builder
	b.WriteString("\n\n## 附件\n\n")
	for _, att := range atts {
		name := str(att.Fields, "fileName")
		if link := a.attachmentLink(dir, att.ID); link != "" {
			fmt.Fprintf(&b, "- [%s](%s)\n", escapeMarkdown(name), mdLink(link))
		} else {
			fmt.Fprintf(&b, "- %s\n", escapeMarkdown(name))
		}
	}
	return b.String()
}

// escapeMarkdown 转义链接文字中会破坏语法的字符。
func escapeMarkdown(s string) string {
	return strings.NewReplacer(`\`, `\\`, "[", `\[`, "]", `\]`, "\n", " ").Replace(s)
}

// fileStem 与 fileExt 拆分文件名（扩展名包含点，最长 10 个字符，否则视为没有扩展名）。
func fileStem(name string) string { return strings.TrimSuffix(name, fileExt(name)) }

func fileExt(name string) string {
	i := strings.LastIndex(name, ".")
	if i <= 0 || len(name)-i > 10 || strings.ContainsAny(name[i:], ` /\`) {
		return ""
	}
	if ext := safeName(name[i+1:], ""); ext != "" {
		return "." + ext
	}
	return ""
}

func readme(d *dataset, sum summary, o buildOptions) []byte {
	var b strings.Builder
	fmt.Fprintf(&b, "即刻日志 数据导出\r\n导出时间：%s\r\n\r\n", o.Now.In(o.Location).Format("2006-01-02 15:04:05 MST"))
	b.WriteString("包含的模块：")
	for i, m := range d.modules {
		if i > 0 {
			b.WriteString("、")
		}
		b.WriteString(moduleLabel[m])
	}
	b.WriteString("\r\n\r\n文件说明：\r\n")
	b.WriteString("- data.json：所选模块的全部记录（原始字段），可用于备份或迁移。\r\n")
	lines := map[Module]string{
		ModuleWorklog: "- 工作日志/工作日志.xlsx：每篇一行；工作日志/<日期>.md：每篇一个 Markdown 文件。\r\n",
		ModuleNote:    "- 笔记/：按文件夹存放的 Markdown 文件，开头是标题、标签等信息。\r\n",
		ModuleMemo:    "- 备忘录/备忘录.ics：可导入日历（含提醒）；备忘录/备忘录.csv：表格。\r\n",
		ModuleLedger:  "- 记账/记账.xlsx：流水、账户、分类、借贷四个工作表，金额单位为元；记账/*.csv：与工作表一一对应。\r\n",
	}
	for _, m := range d.modules {
		b.WriteString(lines[m])
	}
	switch {
	case o.Open == nil:
		b.WriteString("- 本次导出未包含附件文件，Markdown 中只列出附件名称。\r\n")
	case sum.Missing > 0:
		fmt.Fprintf(&b, "- 附件/：%d 个附件文件。另有 %d 个附件在服务器上已不存在，未能导出。\r\n", sum.Attachments, sum.Missing)
	default:
		fmt.Fprintf(&b, "- 附件/：%d 个附件文件，Markdown 中的链接指向这里。\r\n", sum.Attachments)
	}
	b.WriteString("\r\n表格文件为 UTF-8 编码；CSV 带 BOM，可以直接用 Excel 打开。\r\n")
	return []byte(b.String())
}
