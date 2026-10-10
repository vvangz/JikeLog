package syncer

import (
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"time"
)

// Clock 为混合逻辑时钟（HLC），格式 <13 位毫秒>-<4 位十六进制计数>-<16 位十六进制节点>。
// 定长且字段按重要性排列，按字符串比较即为先后顺序。
type Clock string

// maxClockSkew 为允许客户端时钟领先服务器的最大时长，防止时间错乱的设备在"最后修改覆盖"中永远胜出。
const maxClockSkew = 5 * time.Minute

var clockPattern = regexp.MustCompile(`^[0-9]{13}-[0-9a-f]{4}-[0-9a-f]{16}$`)

// ParseClock 校验并返回时钟。
func ParseClock(s string) (Clock, error) {
	if !clockPattern.MatchString(s) {
		return "", errors.New("时钟格式错误")
	}
	return Clock(s), nil
}

// Physical 返回时钟的物理时间部分。
func (c Clock) Physical() time.Time {
	ms, _ := strconv.ParseInt(string(c)[:13], 10, 64) // 格式已校验，不会出错
	return time.UnixMilli(ms)
}

// TooFarAhead 报告时钟是否比 now 领先超过允许范围。
func (c Clock) TooFarAhead(now time.Time) bool {
	return c.Physical().Sub(now) > maxClockSkew
}

// clockAfter 返回紧随 c 之后的服务端时钟：计数加一（溢出时进到下一毫秒），节点为服务端。
func clockAfter(c Clock) Clock {
	ms, _ := strconv.ParseInt(string(c)[:13], 10, 64) // 格式已校验
	n, _ := strconv.ParseUint(string(c)[14:18], 16, 16)
	if n == 0xffff {
		ms, n = ms+1, 0
	} else {
		n++
	}
	return Clock(fmt.Sprintf("%013d-%04x-%s", ms, n, serverNode))
}

// MaxClock 返回较晚的时钟。
func MaxClock(a, b Clock) Clock {
	if a > b {
		return a
	}
	return b
}
