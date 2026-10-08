package auth

import (
	"regexp"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/vvangz/JikeLog/server/internal/apigen"
)

var (
	usernamePattern = regexp.MustCompile(`^[A-Za-z][A-Za-z0-9_]{3,19}$`)
	// 中国大陆手机号：1 开头，第二位 3–9，共 11 位
	cnMobilePattern = regexp.MustCompile(`^1[3-9][0-9]{9}$`)
	smsCodePattern  = regexp.MustCompile(`^[0-9]{6}$`)
)

const (
	minPasswordLen    = 8
	maxPasswordLen    = 64
	maxNicknameLen    = 20
	maxDeviceFieldLen = 64
	maxAppVersionLen  = 32
)

// FieldErrors 收集字段级校验错误，Err 在有错误时返回 422 VALIDATION_FAILED。
type FieldErrors map[string]string

// Add 记录字段错误；同一字段只保留第一条。
func (f FieldErrors) Add(field, reason string) {
	if _, exists := f[field]; !exists {
		f[field] = reason
	}
}

// NormalizePhone 把用户输入的手机号规范为 E.164（+86…）。目前只支持中国大陆手机号。
func NormalizePhone(raw string) (string, bool) {
	s := strings.NewReplacer(" ", "", "-", "").Replace(strings.TrimSpace(raw))
	s = strings.TrimPrefix(s, "+86")
	if !cnMobilePattern.MatchString(s) {
		return "", false
	}
	return "+86" + s, true
}

// MaskPhone 返回脱敏后的手机号，如 138****5678。
func MaskPhone(e164 string) string {
	local := strings.TrimPrefix(e164, "+86")
	if len(local) < 7 {
		return "****"
	}
	return local[:3] + "****" + local[len(local)-4:]
}

// CheckUsername 校验用户名格式。
func CheckUsername(f FieldErrors, field, username string) {
	if !usernamePattern.MatchString(username) {
		f.Add(field, "用户名为 4–20 位，以字母开头，只能包含字母、数字和下划线")
	}
}

// CheckPassword 校验密码强度：8–64 位，同时包含字母和数字，不含控制字符。
func CheckPassword(f FieldErrors, field, password string) {
	n := utf8.RuneCountInString(password)
	if n < minPasswordLen || n > maxPasswordLen {
		f.Add(field, "密码长度为 8–64 位")
		return
	}
	var letter, digit bool
	for _, r := range password {
		switch {
		case unicode.IsLetter(r):
			letter = true
		case unicode.IsDigit(r):
			digit = true
		case unicode.IsControl(r):
			f.Add(field, "密码不能包含控制字符")
			return
		}
	}
	if !letter || !digit {
		f.Add(field, "密码需同时包含字母和数字")
	}
}

// CheckNickname 校验昵称并返回去掉首尾空白后的值；nickname 为 nil 时返回空串。
func CheckNickname(f FieldErrors, field string, nickname *string) string {
	if nickname == nil {
		return ""
	}
	n := strings.TrimSpace(*nickname)
	if utf8.RuneCountInString(n) > maxNicknameLen {
		f.Add(field, "昵称最多 20 个字符")
	}
	for _, r := range n {
		if unicode.IsControl(r) {
			f.Add(field, "昵称不能包含控制字符")
			break
		}
	}
	return n
}

// CheckPhone 校验手机号并返回 E.164 格式。
func CheckPhone(f FieldErrors, field, raw string) string {
	phone, ok := NormalizePhone(raw)
	if !ok {
		f.Add(field, "请输入正确的中国大陆手机号")
	}
	return phone
}

// CheckSMSCode 校验验证码格式。
func CheckSMSCode(f FieldErrors, field, code string) {
	if !smsCodePattern.MatchString(code) {
		f.Add(field, "验证码为 6 位数字")
	}
}

// DeviceMeta 为校验并清洗后的设备信息。
type DeviceMeta struct {
	InstallationID string
	Platform       string
	Model          string
	OSVersion      string
	AppVersion     string
}

// CheckDevice 校验设备信息，展示用字段超长时截断而不是拒绝。
func CheckDevice(f FieldErrors, d apigen.DeviceInfo) DeviceMeta {
	if n := len(d.InstallationId); n < 8 || n > maxDeviceFieldLen {
		f.Add("device.installationId", "设备标识长度为 8–64")
	}
	if !d.Platform.Valid() {
		f.Add("device.platform", "不支持的平台")
	}
	return DeviceMeta{
		InstallationID: d.InstallationId,
		Platform:       string(d.Platform),
		Model:          clip(d.Model, maxDeviceFieldLen),
		OSVersion:      clip(d.OsVersion, maxDeviceFieldLen),
		AppVersion:     clip(d.AppVersion, maxAppVersionLen),
	}
}

// clip 截断可选的展示字段并去掉控制字符：这些字段只用于设备列表展示，没必要因为超长拒绝登录。
func clip(s *string, maxRunes int) string {
	if s == nil {
		return ""
	}
	out := make([]rune, 0, maxRunes)
	for _, r := range strings.TrimSpace(*s) {
		if len(out) == maxRunes {
			break
		}
		if !unicode.IsControl(r) {
			out = append(out, r)
		}
	}
	return string(out)
}
