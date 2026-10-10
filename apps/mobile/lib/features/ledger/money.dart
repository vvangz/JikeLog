/// 金额工具：全部以"分"为单位的整数计算，只在显示与输入时换算成元（ADR-009）。
library;

/// 金额（分）的绝对值上限，与服务端一致：10^15 分。
const maxMoneyCents = 999999999999999;

/// 解析服务端的金额字符串（分）。格式不对时为 null。
int? parseCents(Object? v) {
  if (v is! String) return null;
  return int.tryParse(v);
}

/// 金额（分）编码为服务端格式。
String encodeCents(int cents) => cents.toString();

/// 解析用户输入的金额（元）：最多两位小数，不接受负数与科学计数法。格式不对时为 null。
int? parseYuan(String input) {
  final s = input.trim().replaceAll(',', '').replaceAll('，', '');
  final m = RegExp(r'^(\d{1,13})(?:\.(\d{0,2}))?$').firstMatch(s);
  if (m == null) return null;
  final yuan = int.parse(m.group(1)!);
  final frac = (m.group(2) ?? '').padRight(2, '0');
  final cents = yuan * 100 + int.parse(frac);
  return cents > maxMoneyCents ? null : cents;
}

/// 金额（分）显示为元：千分位、两位小数，如 "1,234.50"；[sign] 为 true 时正数带"+"。
String formatYuan(int cents, {bool sign = false}) {
  final negative = cents < 0;
  final abs = cents.abs();
  final yuan = (abs ~/ 100).toString();
  final buf = StringBuffer();
  for (var i = 0; i < yuan.length; i++) {
    if (i > 0 && (yuan.length - i) % 3 == 0) buf.write(',');
    buf.write(yuan[i]);
  }
  final frac = (abs % 100).toString().padLeft(2, '0');
  final prefix = negative ? '-' : (sign && cents > 0 ? '+' : '');
  return '$prefix$buf.$frac';
}

/// 输入框中显示的金额（元）：去掉多余的零，如 1250 → "12.5"，1200 → "12"。
String editableYuan(int cents) {
  final yuan = cents ~/ 100;
  final frac = cents % 100;
  if (frac == 0) return '$yuan';
  if (frac % 10 == 0) return '$yuan.${frac ~/ 10}';
  return '$yuan.${frac.toString().padLeft(2, '0')}';
}
