// 颜色工具：十六进制解析、Dart Color 字面量、WCAG 对比度

const HEX = /^#([0-9a-f]{6}|[0-9a-f]{8})$/i;

export function parseHex(hex) {
  if (typeof hex !== 'string' || !HEX.test(hex)) {
    throw new Error(`非法颜色值：${hex}（需要 #RRGGBB 或 #RRGGBBAA）`);
  }
  const n = hex.slice(1);
  const byte = (i) => parseInt(n.slice(i, i + 2), 16);
  return { r: byte(0), g: byte(2), b: byte(4), a: n.length === 8 ? byte(6) : 0xff };
}

export function hexToDartColor(hex) {
  const { r, g, b, a } = parseHex(hex);
  const h = (v) => v.toString(16).padStart(2, '0').toUpperCase();
  return `Color(0x${h(a)}${h(r)}${h(g)}${h(b)})`;
}

function channel(v) {
  const s = v / 255;
  return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
}

function luminance(hex) {
  const { r, g, b } = parseHex(hex);
  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
}

export function contrastRatio(a, b) {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}
