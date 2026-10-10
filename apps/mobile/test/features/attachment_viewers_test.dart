import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/app/theme/app_theme.dart';
import 'package:jikelog/features/attachments/attachment_images.dart';
import 'package:jikelog/features/attachments/attachment_service.dart';
import 'package:jikelog/features/attachments/attachment_viewers.dart';
import 'package:jikelog/features/attachments/media.dart';

import '../support/fake_media.dart';

late Directory _tmp;

AttachmentView _view(String name, String mime) => AttachmentView(
  id: '0190a1b2-0000-7000-8000-000000000001',
  fileName: name,
  mime: mime,
  size: 3,
  state: AttachmentState.ready,
);

/// 只挂载被测页面所需的 provider。
Future<WidgetRef> _pump(
  WidgetTester tester, {
  FakePlayer? player,
  bool micPermitted = true,
  bool openExternal = true,
  Widget? child,
}) async {
  late WidgetRef captured;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerFactoryProvider.overrideWithValue(() => player ?? FakePlayer()),
        recorderFactoryProvider.overrideWithValue(
          () => FakeRecorder(permitted: micPermitted),
        ),
        pdfViewBuilderProvider.overrideWithValue((f) => const Text('PDF 内容')),
        recordingDirProvider.overrideWithValue(() async => _tmp),
        openExternalProvider.overrideWithValue((_, _) async => openExternal),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Consumer(
          builder: (context, ref, _) {
            captured = ref;
            return Scaffold(body: child ?? const SizedBox());
          },
        ),
      ),
    ),
  );
  return captured;
}

void main() {
  setUp(() => _tmp = Directory.systemTemp.createTempSync('jk-view'));
  tearDown(() => _tmp.deleteSync(recursive: true));

  testWidgets('按类型打开：图片全屏、PDF 阅读、音频播放、其他交给系统应用', (tester) async {
    final player = FakePlayer();
    final ref = await _pump(tester, player: player);
    final ctx = tester.element(find.byType(Scaffold));
    final file = File('${_tmp.path}/x')..writeAsBytesSync(onePixelPng);

    unawaited(showAttachment(ctx, ref, _view('照片.png', 'image/png'), file));
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewerPage), findsOneWidget);
    expect(find.text('照片.png'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    unawaited(
      showAttachment(ctx, ref, _view('合同.pdf', 'application/pdf'), file),
    );
    await tester.pumpAndSettle();
    expect(find.text('PDF 内容'), findsOneWidget);
    await tester.tap(find.byTooltip('用其他应用打开'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    unawaited(showAttachment(ctx, ref, _view('录音.m4a', 'audio/mp4'), file));
    await tester.pumpAndSettle();
    expect(find.text('录音.m4a'), findsOneWidget);
    expect(find.text('01:30'), findsOneWidget);
    expect(find.text('00:03'), findsOneWidget);
    await tester.tap(find.byKey(const Key('audio-toggle')));
    await tester.pump();
    await tester.drag(
      find.byKey(const Key('audio-seek')),
      const Offset(100, 0),
    );
    await tester.pump();
    expect(player.calls, containsAllInOrder(['load', 'play', 'pause', 'seek']));
    Navigator.of(tester.element(find.byType(AudioPlayerSheet))).pop();
    await tester.pumpAndSettle();
    expect(player.calls.last, 'dispose');

    await showAttachment(
      ctx,
      ref,
      _view('表格.xlsx', 'application/vnd.ms-excel'),
      file,
    );
    await tester.pump();
    expect(find.text('没有可以打开该文件的应用'), findsNothing);
  });

  testWidgets('没有可以打开的应用时提示', (tester) async {
    final ref = await _pump(tester, openExternal: false);
    final ctx = tester.element(find.byType(Scaffold));
    await showAttachment(
      ctx,
      ref,
      _view('a.bin', 'application/octet-stream'),
      File('${_tmp.path}/a'),
    );
    await tester.pump();
    expect(find.text('没有可以打开该文件的应用'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('音频无法播放时显示错误', (tester) async {
    await _pump(
      tester,
      child: AudioPlayerSheet(file: File('${_tmp.path}/none'), title: '坏文件'),
      player: _BrokenPlayer(),
    );
    await tester.pumpAndSettle();
    expect(find.text('无法播放该音频'), findsOneWidget);
  });

  testWidgets('录音：开始、计时、停止并返回文件；没有权限时提示', (tester) async {
    await _pump(tester);
    final ctx = tester.element(find.byType(Scaffold));
    File? result;
    final done = showModalBottomSheet<File>(
      context: ctx,
      builder: (_) => const RecorderSheet(),
    ).then((f) => result = f);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recorder-toggle')));
    // 开始录音要写文件（真实 IO）：交替推进真实时间与虚拟时间
    for (var i = 0; i < 20 && find.text('停止并保存').evaluate().isEmpty; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('00:02'), findsOneWidget);
    expect(find.text('停止并保存'), findsOneWidget);
    await tester.tap(find.byKey(const Key('recorder-toggle')));
    await tester.pumpAndSettle();
    await done;
    expect(result!.path, endsWith('.m4a'));
    expect(result!.path, contains('录音 '));

    await _pump(tester, micPermitted: false);
    unawaited(
      showModalBottomSheet<File>(
        context: tester.element(find.byType(Scaffold)),
        builder: (_) => const RecorderSheet(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recorder-toggle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('没有麦克风权限'), findsOneWidget);
  });

  testWidgets('预览中的图片：附件图片、加载失败、网络图片不加载', (tester) async {
    final file = File('${_tmp.path}/p.png')..writeAsBytesSync(onePixelPng);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          attachmentFileProvider('ok').overrideWith((_) async => file),
          attachmentFileProvider('bad')
              .overrideWith((_) async => throw StateError('附件不存在')),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Column(
              children: [
                markdownImage(Uri.parse('attachment:ok'), null, '图'),
                markdownImage(Uri.parse('attachment:bad'), null, '合同'),
                markdownImage(Uri.parse('https://x.example/a.png'), null, '外链'),
                markdownImage(Uri.parse('https://x.example/b.png'), null, null),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('图片无法显示：合同'), findsOneWidget);
    expect(find.text('[图片：外链]'), findsOneWidget);
    expect(find.text('[图片]'), findsOneWidget);
  });

  group('imageDataUrl', () {
    test('识别常见格式的文件头', () {
      List<int> b(List<int> head) => [...head, ...List.filled(16, 0)];
      expect(
        sniffImageMime(Uint8ListOf(b([0x89, 0x50, 0x4E, 0x47]))),
        'image/png',
      );
      expect(sniffImageMime(Uint8ListOf(b([0xFF, 0xD8, 0xFF]))), 'image/jpeg');
      expect(
        sniffImageMime(Uint8ListOf(b([0x47, 0x49, 0x46, 0x38]))),
        'image/gif',
      );
      expect(
        sniffImageMime(
          Uint8ListOf(
            b([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]),
          ),
        ),
        'image/webp',
      );
      expect(sniffImageMime(Uint8ListOf([1, 2])), isNull);
    });

    testWidgets('小图片直接编码；不是图片时返回 null', (tester) async {
      final png = File('${_tmp.path}/a.png')..writeAsBytesSync(onePixelPng);
      final txt = File('${_tmp.path}/a.txt')..writeAsStringSync('不是图片');
      await tester.runAsync(() async {
        expect(
          await imageDataUrl(png),
          startsWith('data:image/png;base64,iVBOR'),
        );
        expect(await imageDataUrl(txt), isNull);
        // BMP 不能直接交给编辑器显示：解码后转成 PNG
        final bmp = File('${_tmp.path}/a.bmp')..writeAsBytesSync(_bmp1x1);
        expect(await imageDataUrl(bmp), startsWith('data:image/png;base64,'));
      });
    });
  });
}

// ignore: non_constant_identifier_names
Uint8List Uint8ListOf(List<int> b) => Uint8List.fromList(b);

class _BrokenPlayer extends FakePlayer {
  @override
  Future<Duration?> load(String path) async => throw StateError('无法解码');
}

/// 1×1 的 24 位 BMP 图片（白色）。
final _bmp1x1 = Uint8List.fromList([
  0x42, 0x4D, 0x3A, 0, 0, 0, 0, 0, 0, 0, 0x36, 0, 0, 0, // 文件头
  0x28, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 24, 0, // 信息头
  0, 0, 0, 0, 4, 0, 0, 0, 0x13, 0x0B, 0, 0, 0x13, 0x0B, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0,
  0xFF, 0xFF, 0xFF, 0, // 像素（每行补齐到 4 字节）
]);
