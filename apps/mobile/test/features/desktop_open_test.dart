import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/features/attachments/desktop_open.dart';
import 'package:path/path.dart' as p;

void main() {
  group('safeFileName', () {
    test('普通文件名不变', () {
      expect(safeFileName('周报 2026-10.pdf'), '周报 2026-10.pdf');
    });

    test('去掉路径、非法字符与末尾的点和空格', () {
      expect(safeFileName(r'..\..\Windows\evil.exe'), '.._.._Windows_evil.exe');
      expect(safeFileName('a/b.txt'), 'a_b.txt');
      expect(safeFileName('x.txt:evil.exe'), 'x.txt_evil.exe');
      expect(safeFileName('报告.pdf. . '), '报告.pdf');
      expect(safeFileName('a<b>c?.doc'), 'a_b_c_.doc');
      expect(safeFileName(''), 'attachment');
      expect(safeFileName('...'), 'attachment');
    });

    test('避开设备名', () {
      expect(safeFileName('CON'), '_CON');
      expect(safeFileName('nul.txt'), '_nul.txt');
      expect(safeFileName('com1.pdf'), '_com1.pdf');
      expect(safeFileName('console.txt'), 'console.txt');
    });

    test('过长时截断并保留扩展名', () {
      final s = safeFileName('${'长' * 200}.pdf');
      expect(s.length, 120);
      expect(s, endsWith('.pdf'));
    });
  });

  test('isDesktopOpenable：允许列表之外的类型不直接打开', () {
    for (final n in ['a.pdf', 'b.JPG', 'c.docx', 'd.mp3', 'e.zip']) {
      expect(isDesktopOpenable(n), isTrue, reason: n);
    }
    for (final n in [
      'a.exe',
      'b.bat',
      'c.lnk',
      'd.ps1',
      'e.scr',
      'f.hta',
      'g.docm',
      'h.xlsm',
      'i.html',
      'j.svg',
      'k.chm',
      'l.appref-ms',
      'm.dll',
      'README',
    ]) {
      expect(isDesktopOpenable(n), isFalse, reason: n);
    }
  });

  group('openOnDesktop', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('jk-open'));
    tearDown(() => tmp.deleteSync(recursive: true));

    File stored() =>
        File(p.join(tmp.path, '0190a1b2-0000-7000-8000-000000000001'))
          ..writeAsBytesSync([1, 2, 3]);

    test('允许的类型：打开以原文件名命名的副本', () async {
      Uri? launched;
      final ok = await openOnDesktop(
        stored(),
        '会议纪要.pdf',
        root: Directory(p.join(tmp.path, 'open')),
        launch: (u) async {
          launched = u;
          return true;
        },
      );
      expect(ok, isTrue);
      final path = launched!.toFilePath();
      expect(p.basename(path), '会议纪要.pdf');
      expect(File(path).readAsBytesSync(), [1, 2, 3]);
    });

    test('其他类型：只打开副本所在的文件夹', () async {
      Uri? launched;
      await openOnDesktop(
        stored(),
        'setup.exe',
        root: Directory(p.join(tmp.path, 'open')),
        launch: (u) async {
          launched = u;
          return true;
        },
      );
      final dir = Directory(launched!.toFilePath());
      expect(dir.existsSync(), isTrue);
      expect(
        dir.listSync().map((e) => p.basename(e.path)),
        contains('setup.exe'),
      );
    });

    test('打开失败时返回 false', () async {
      final ok = await openOnDesktop(
        stored(),
        'a.pdf',
        root: Directory(p.join(tmp.path, 'open')),
        launch: (_) async => throw PlatformException(code: 'x'),
      );
      expect(ok, isFalse);
    });
  });
}
