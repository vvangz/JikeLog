package export

import (
	"encoding/csv"
	"fmt"
	"io"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/xuri/excelize/v2"
)

// maxCellRunes 为 Excel 单元格的字符上限（32767），超出部分截断并注明。
const maxCellRunes = 32767

// utf8BOM 让 Excel 按 UTF-8 打开 CSV。
var utf8BOM = []byte{0xEF, 0xBB, 0xBF}

const truncatedNote = "…（内容过长，完整内容见 Markdown 文件或 data.json）"

// money 为以"分"为单位的金额，表格中显示为元。
type money int64

func (m money) String() string {
	n := int64(m)
	sign := ""
	if n < 0 {
		sign, n = "-", -n
	}
	return fmt.Sprintf("%s%d.%02d", sign, n/100, n%100)
}

// table 为一张表：同时写成 xlsx 中的工作表和一个 CSV 文件。
// 单元格的值为 string、int64、money 或 bool。
type table struct {
	name   string
	header []string
	rows   [][]any
}

func cellText(v any) string {
	switch x := v.(type) {
	case string:
		return x
	case int64:
		return strconv.FormatInt(x, 10)
	case money:
		return x.String()
	case bool:
		if x {
			return "是"
		}
		return "否"
	default:
		return ""
	}
}

// writeCSV 写出 CSV（UTF-8 BOM、CRLF，Excel 可以直接打开）。
func writeCSV(w io.Writer, t table) error {
	if _, err := w.Write(utf8BOM); err != nil {
		return err
	}
	cw := csv.NewWriter(w)
	cw.UseCRLF = true
	if err := cw.Write(t.header); err != nil {
		return err
	}
	for _, row := range t.rows {
		rec := make([]string, len(row))
		for i, v := range row {
			rec[i] = cellText(v)
			if _, isText := v.(string); isText {
				rec[i] = neutralizeFormula(rec[i])
			}
		}
		if err := cw.Write(rec); err != nil {
			return err
		}
	}
	cw.Flush()
	return cw.Error()
}

// neutralizeFormula 防止 CSV 中的文字被 Excel 当作公式执行（CSV 注入）：以 = + - @ 制表符或回车开头时前置单引号。
// 只用于文字，金额与数字保持原样；xlsx 中的文字以字符串类型写入，不会被当作公式。
func neutralizeFormula(s string) string {
	if s != "" && strings.ContainsRune("=+-@\t\r", rune(s[0])) {
		return "'" + s
	}
	return s
}

// writeXLSX 把多张表写成一个 xlsx 文件，每张表一个工作表。
func writeXLSX(w io.Writer, tables []table) error {
	f := excelize.NewFile()
	defer func() { _ = f.Close() }()
	moneyStyle, err := f.NewStyle(&excelize.Style{NumFmt: 2}) // 0.00
	if err != nil {
		return fmt.Errorf("创建表格样式失败: %w", err)
	}
	headerStyle, err := f.NewStyle(&excelize.Style{Font: &excelize.Font{Bold: true}})
	if err != nil {
		return fmt.Errorf("创建表格样式失败: %w", err)
	}
	for i, t := range tables {
		if i == 0 {
			if err := f.SetSheetName("Sheet1", t.name); err != nil {
				return fmt.Errorf("创建工作表失败: %w", err)
			}
		} else if _, err := f.NewSheet(t.name); err != nil {
			return fmt.Errorf("创建工作表失败: %w", err)
		}
		if err := writeSheet(f, t, headerStyle, moneyStyle); err != nil {
			return err
		}
	}
	if err := f.Write(w); err != nil {
		return fmt.Errorf("写入表格失败: %w", err)
	}
	return nil
}

func writeSheet(f *excelize.File, t table, headerStyle, moneyStyle int) error {
	sw, err := f.NewStreamWriter(t.name)
	if err != nil {
		return fmt.Errorf("创建工作表失败: %w", err)
	}
	header := make([]any, len(t.header))
	for i, h := range t.header {
		header[i] = excelize.Cell{StyleID: headerStyle, Value: h}
	}
	if err := sw.SetRow("A1", header); err != nil {
		return fmt.Errorf("写入表头失败: %w", err)
	}
	for r, row := range t.rows {
		cells := make([]any, len(row))
		for i, v := range row {
			cells[i] = xlsxCell(v, moneyStyle)
		}
		axis, err := excelize.CoordinatesToCellName(1, r+2)
		if err != nil {
			return err
		}
		if err := sw.SetRow(axis, cells); err != nil {
			return fmt.Errorf("写入第 %d 行失败: %w", r+2, err)
		}
	}
	if err := sw.Flush(); err != nil {
		return fmt.Errorf("写入工作表失败: %w", err)
	}
	return nil
}

func xlsxCell(v any, moneyStyle int) any {
	switch x := v.(type) {
	case money:
		return excelize.Cell{StyleID: moneyStyle, Value: float64(x) / 100}
	case string:
		return clipCell(x)
	case int64:
		return x
	default:
		return cellText(v)
	}
}

// clipCell 截断超出单元格上限的文本。
func clipCell(s string) string {
	if utf8.RuneCountInString(s) <= maxCellRunes {
		return s
	}
	keep := maxCellRunes - utf8.RuneCountInString(truncatedNote)
	return string([]rune(s)[:keep]) + truncatedNote
}
