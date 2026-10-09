package syncer

import (
	"testing"
	"time"
)

func TestParseClock(t *testing.T) {
	valid := []string{
		"1791553544038-0000-a1b2c3d4e5f60718",
		"0000000000000-ffff-0000000000000000",
	}
	for _, s := range valid {
		if _, err := ParseClock(s); err != nil {
			t.Errorf("%q 应当合法：%v", s, err)
		}
	}
	invalid := []string{
		"", "1791553544038-0000", "1791553544038-000g-a1b2c3d4e5f60718",
		"179155354403-0000-a1b2c3d4e5f60718", "1791553544038-0000-A1B2C3D4E5F60718",
		"1791553544038-0000-a1b2c3d4e5f607181",
	}
	for _, s := range invalid {
		if _, err := ParseClock(s); err == nil {
			t.Errorf("%q 应当非法", s)
		}
	}
}

func TestClockOrderAndPhysical(t *testing.T) {
	a := Clock("1791553544038-0000-a1b2c3d4e5f60718")
	b := Clock("1791553544038-0001-0000000000000000")
	c := Clock("1791553544039-0000-0000000000000000")
	if !(a < b && b < c) {
		t.Fatal("字符串顺序应与时间顺序一致")
	}
	if got := c.Physical(); !got.Equal(time.UnixMilli(1791553544039)) {
		t.Fatalf("physical=%v", got)
	}
	if MaxClock(a, c) != c || MaxClock(c, a) != c {
		t.Fatal("MaxClock 错误")
	}
}

func TestClockSkew(t *testing.T) {
	now := time.UnixMilli(1791553544038)
	ok := Clock("1791553844038-0000-a1b2c3d4e5f60718")  // +5 分钟，刚好允许
	bad := Clock("1791553844039-0000-a1b2c3d4e5f60718") // 超过 5 分钟
	if ok.TooFarAhead(now) {
		t.Fatal("5 分钟以内应当允许")
	}
	if !bad.TooFarAhead(now) {
		t.Fatal("超过 5 分钟应当拒绝")
	}
}
