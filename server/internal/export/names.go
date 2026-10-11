package export

import (
	"path"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"
)

// maxNameRunes 为 zip 中单个文件名（不含扩展名）的最大字符数。
const maxNameRunes = 80

// safeName 把用户输入的标题、文件名转为可用的文件名：替换路径分隔符和各平台不允许的字符，
// 去掉首尾的空白和点，过长时截断。结果为空时使用 fallback。
func safeName(s, fallback string) string {
	var b strings.Builder
	for _, r := range s {
		switch {
		case r == '/' || r == '\\' || r == ':' || r == '*' || r == '?' || r == '"' ||
			r == '<' || r == '>' || r == '|' || unicode.IsControl(r):
			b.WriteRune('_')
		default:
			b.WriteRune(r)
		}
	}
	name := strings.TrimFunc(b.String(), func(r rune) bool { return r == '.' || unicode.IsSpace(r) })
	if utf8.RuneCountInString(name) > maxNameRunes {
		name = strings.TrimRight(string([]rune(name)[:maxNameRunes]), " .")
	}
	if name == "" {
		return fallback
	}
	return name
}

// namer 为同一目录中的文件分配不重复的名字（不区分大小写，兼容 Windows 与 macOS）。
type namer struct {
	used map[string]bool
}

func newNamer() *namer { return &namer{used: map[string]bool{}} }

// unique 返回 dir/name+ext；已被占用时依次尝试 "name (2)"、"name (3)"……
func (n *namer) unique(dir, name, ext string) string {
	for i := 1; ; i++ {
		candidate := name
		if i > 1 {
			candidate = name + " (" + strconv.Itoa(i) + ")"
		}
		full := path.Join(dir, candidate+ext)
		if key := strings.ToLower(full); !n.used[key] {
			n.used[key] = true
			return full
		}
	}
}

// relPath 返回从 fromDir 指向 target 的相对路径（两者都是 zip 内的路径），用于 Markdown 链接。
func relPath(fromDir, target string) string {
	depth := 0
	if fromDir != "" && fromDir != "." {
		depth = strings.Count(path.Clean(fromDir), "/") + 1
	}
	return strings.Repeat("../", depth) + target
}

// mdLink 把路径写成 Markdown 链接目标：用尖括号包住，路径中的空格和括号无需转义。
func mdLink(p string) string {
	return "<" + strings.NewReplacer("<", "%3C", ">", "%3E").Replace(p) + ">"
}
