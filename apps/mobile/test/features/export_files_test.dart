import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jikelog/core/net/tls.dart';
import 'package:jikelog/features/export/export_api.dart';
import 'package:path/path.dart' as p;

/// 下载地址返回固定内容；[status] 不为 200 时模拟下载失败。
class _Download implements HttpClientAdapter {
  _Download(this.body, {this.status = 200});

  final List<int> body;
  final int status;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromBytes(
    body,
    status,
    headers: {
      Headers.contentLengthHeader: ['${body.length}'],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('jk-export'));
  tearDown(() => dir.deleteSync(recursive: true));

  SaveExportFiles files(_Download d, {String? folder}) => SaveExportFiles(
    tls: TlsPolicy.system,
    dio: Dio()..httpClientAdapter = d,
    pickFolder: () async => folder,
  );

  test('桌面端：下载到选择的文件夹，返回路径，不留临时文件', () async {
    final f = files(_Download([1, 2, 3]), folder: dir.path);
    final saved = await f.downloadAndShare('http://x/e.zip', '导出.zip');

    expect(saved, p.join(dir.path, '导出.zip'));
    expect(File(saved!).readAsBytesSync(), [1, 2, 3]);
    expect(dir.listSync(), hasLength(1));
  });

  test('桌面端：重名时加序号，不覆盖已有文件', () async {
    File(p.join(dir.path, '导出.zip')).writeAsBytesSync([9]);
    File(p.join(dir.path, '导出 (2).zip')).writeAsBytesSync([9]);
    final f = files(_Download([1]), folder: dir.path);

    final saved = await f.downloadAndShare('http://x/e.zip', '导出.zip');
    expect(saved, p.join(dir.path, '导出 (3).zip'));
    expect(File(p.join(dir.path, '导出.zip')).readAsBytesSync(), [9]);
  });

  test('桌面端：取消选择时不下载', () async {
    final f = files(_Download([1]));
    expect(await f.downloadAndShare('http://x/e.zip', '导出.zip'), isNull);
    expect(dir.listSync(), isEmpty);
  });

  test('桌面端：下载失败时删除不完整的文件', () async {
    final f = files(_Download([1], status: 500), folder: dir.path);
    await expectLater(
      f.downloadAndShare('http://x/e.zip', '导出.zip'),
      throwsA(isA<DioException>()),
    );
    expect(dir.listSync(), isEmpty);
  });
}
