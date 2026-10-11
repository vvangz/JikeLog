package export

import (
	"bytes"
	"encoding/json"
	"fmt"
	"path"
	"regexp"
	"slices"
	"strings"

	"github.com/google/uuid"

	"github.com/vvangz/JikeLog/server/internal/syncer"
)

// writeWorklogs 写出工作日志：一个 xlsx（每篇一行）和每篇一个 Markdown 文件。
func (a *archive) writeWorklogs(d *dataset) error {
	if !d.has(ModuleWorklog) {
		return nil
	}
	dir := moduleLabel[ModuleWorklog]
	logs := slices.Clone(d.records(syncer.EntityWorklog))
	slices.SortStableFunc(logs, func(x, y syncer.Snapshot) int {
		return strings.Compare(str(x.Fields, "date"), str(y.Fields, "date"))
	})
	t := table{name: "工作日志", header: []string{"日期", "地点", "内容", "附件数"}}
	for _, w := range logs {
		f := w.Fields
		atts := d.attachments[w.ID]
		t.rows = append(t.rows, []any{str(f, "date"), str(f, "location"), str(f, "content"), int64(len(atts))})

		name := a.names.unique(dir, safeName(str(f, "date"), "工作日志"), ".md")
		var b strings.Builder
		fmt.Fprintf(&b, "# %s 工作日志\n\n", str(f, "date"))
		if loc := str(f, "location"); loc != "" {
			fmt.Fprintf(&b, "- 地点：%s\n\n", strings.ReplaceAll(loc, "\n", " "))
		}
		b.WriteString(a.rewriteAttachments(path.Dir(name), str(f, "content")))
		b.WriteString(a.attachmentList(path.Dir(name), atts))
		b.WriteString("\n")
		if err := a.write(name, []byte(b.String())); err != nil {
			return err
		}
	}
	w, err := a.create(a.names.unique(dir, "工作日志", ".xlsx"))
	if err != nil {
		return err
	}
	return writeXLSX(w, []table{t})
}

// writeNotes 写出笔记：按文件夹存放的 Markdown 文件，开头是标题、标签等信息（YAML front matter）。
func (a *archive) writeNotes(d *dataset) error {
	if !d.has(ModuleNote) {
		return nil
	}
	folders := folderPaths(d.records(syncer.EntityNoteFolder))
	notes := slices.Clone(d.records(syncer.EntityNote))
	slices.SortStableFunc(notes, func(x, y syncer.Snapshot) int { return x.UpdatedAt.Compare(y.UpdatedAt) })
	for _, n := range notes {
		f := n.Fields
		dir := moduleLabel[ModuleNote]
		if p, ok := folders[str(f, "folderId")]; ok {
			dir = path.Join(dir, p)
		}
		title := noteTitle(f)
		name := a.names.unique(dir, safeName(title, "无标题笔记"), ".md")
		body := a.rewriteAttachments(dir, str(f, "body"))
		// 正文中已经显示的图片不再重复列出
		var rest []syncer.Snapshot
		for _, att := range d.attachments[n.ID] {
			if !strings.Contains(str(f, "body"), "attachment:"+att.ID.String()) {
				rest = append(rest, att)
			}
		}
		var b bytes.Buffer
		b.WriteString(frontMatter(title, n, f))
		b.WriteString(body)
		b.WriteString(a.attachmentList(dir, rest))
		b.WriteString("\n")
		if err := a.write(name, b.Bytes()); err != nil {
			return err
		}
	}
	return nil
}

// frontMatter 生成 YAML front matter。字符串用 JSON 写法，同样是合法的 YAML。
func frontMatter(title string, n syncer.Snapshot, f map[string]syncer.Value) string {
	q := func(v any) string {
		b, _ := json.Marshal(v)
		return string(b)
	}
	var b strings.Builder
	b.WriteString("---\n")
	fmt.Fprintf(&b, "title: %s\n", q(title))
	if tags := lines(str(f, "tags")); len(tags) > 0 {
		fmt.Fprintf(&b, "tags: %s\n", q(tags))
	}
	if flag(f, "favorite") {
		b.WriteString("favorite: true\n")
	}
	if flag(f, "pinned") {
		b.WriteString("pinned: true\n")
	}
	fmt.Fprintf(&b, "updated: %s\n", q(n.UpdatedAt.UTC()))
	b.WriteString("---\n\n")
	return b.String()
}

// noteTitle 为笔记标题；没有标题时取正文第一行（去掉 Markdown 标记）。
func noteTitle(f map[string]syncer.Value) string {
	if t := strings.TrimSpace(str(f, "title")); t != "" {
		return t
	}
	for _, line := range strings.Split(str(f, "body"), "\n") {
		line = strings.TrimSpace(strings.TrimLeft(strings.TrimSpace(line), "#>-*+ "))
		if line != "" && !strings.HasPrefix(line, "![") {
			return line
		}
	}
	return "无标题笔记"
}

// lines 把多行文本拆成去掉空行与重复的列表（标签字段的格式，见 ADR-007）。
func lines(s string) []string {
	var out []string
	for _, l := range strings.Split(s, "\n") {
		if l = strings.TrimSpace(l); l != "" && !slices.Contains(out, l) {
			out = append(out, l)
		}
	}
	return out
}

// folderPaths 计算每个文件夹在 zip 中的相对路径（由上级文件夹的名字拼成）。
// 上级不存在时视为顶层；循环引用时在重复处截断。
func folderPaths(folders []syncer.Snapshot) map[string]string {
	byID := map[string]syncer.Snapshot{}
	for _, f := range folders {
		byID[f.ID.String()] = f
	}
	out := map[string]string{}
	for id := range byID {
		var parts []string
		seen := map[string]bool{}
		for cur, ok := byID[id]; ok && !seen[cur.ID.String()] && len(parts) < 20; cur, ok = byID[str(cur.Fields, "parentId")] {
			seen[cur.ID.String()] = true
			parts = append([]string{safeName(str(cur.Fields, "name"), "未命名文件夹")}, parts...)
		}
		out[id] = path.Join(parts...)
	}
	return out
}

var attachmentRef = regexp.MustCompile(`\]\(attachment:([0-9a-fA-F-]{36})\)`)

// rewriteAttachments 把正文中的 attachment:<ID> 引用改为指向 zip 中附件文件的相对路径。
// 不包含附件文件，或者附件已不存在时保持原样。
func (a *archive) rewriteAttachments(dir, md string) string {
	return attachmentRef.ReplaceAllStringFunc(md, func(m string) string {
		id, err := uuid.Parse(attachmentRef.FindStringSubmatch(m)[1])
		if err != nil {
			return m
		}
		if link := a.attachmentLink(dir, id); link != "" {
			return "](" + mdLink(link) + ")"
		}
		return m
	})
}
