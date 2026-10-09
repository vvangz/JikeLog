import 'dart:async';

import 'package:drift/drift.dart';

/// 全部测试的公共配置：每个测试各用一个内存数据库属于预期行为，关闭 drift 的重复实例告警。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  await testMain();
}
