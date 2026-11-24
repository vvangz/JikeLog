import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../../app/version.dart';
import '../../core/config.dart';
import '../../core/platform/platform_features.dart';
import '../../core/storage/stores.dart';
import 'update_installer.dart';
import 'update_models.dart';

/// 应用内更新异常（可展示给用户的明确提示）。
class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 负责从同源服务器检查最新版本、流式下载、SHA-256 校验与触发系统覆盖安装。
class AppUpdateService {
  AppUpdateService({
    required String baseUrl,
    required this.dio,
    required this.isDesktop,
    required this.currentVersion,
    required this.updateDir,
    required this.installPackage,
  }) : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');

  final String _baseUrl;
  final Dio dio;
  final bool isDesktop;
  final String currentVersion;
  final Future<Directory> Function() updateDir;
  final InstallPackageFn installPackage;

  String get downloadPageUrl => '$_baseUrl/download';

  /// 检查服务端 `/download/latest.json`，若存在更高版本且包含当前平台安装包则返回候选信息。
  Future<UpdateCandidate?> checkForUpdate() async {
    final Response<dynamic> res;
    try {
      res = await dio.get<dynamic>(
        '$_baseUrl/download/latest.json',
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
    } on DioException catch (e) {
      debugPrint('检查更新失败: $e');
      throw const UpdateException('检查更新失败，请检查网络连接后重试');
    }

    final raw = res.data is String ? _tryJson(res.data as String) : res.data;
    final manifest = UpdateManifest.tryParse(raw);
    if (manifest == null) {
      throw const UpdateException('更新清单格式异常，请稍后重试');
    }

    final file = isDesktop ? manifest.windows : manifest.android;
    if (file == null || !isNewerVersion(manifest.version, currentVersion)) {
      unawaited(_pruneStale());
      return null;
    }

    return UpdateCandidate(
      version: manifest.version,
      file: file,
      downloadUrl: '$_baseUrl/download/${file.name}',
      changelogUrl: '$_baseUrl/changelog/v${manifest.version}',
      releaseUrl: manifest.releaseUrl,
      publishedAt: manifest.publishedAt,
    );
  }

  /// 下载安装包并逐字节校验 SHA-256。若本地已有同文件且校验通过，直接复用避免重复下载。
  Future<File> downloadAndVerify(
    UpdateCandidate candidate, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await updateDir();
    await dir.create(recursive: true);
    final target = File(p.join(dir.path, candidate.file.name));

    if (await target.exists()) {
      final cachedHash = await _sha256File(target);
      if (cachedHash == candidate.file.sha256) {
        onProgress?.call(candidate.file.size, candidate.file.size);
        return target;
      }
      await _deleteQuietly(target);
    }

    await _pruneStale(keepName: candidate.file.name);

    final part = File('${target.path}.part');
    await _deleteQuietly(part);

    try {
      await dio.download(
        candidate.downloadUrl,
        part.path,
        cancelToken: cancelToken,
        deleteOnError: true,
        options: Options(receiveTimeout: const Duration(minutes: 10)),
        onReceiveProgress: (received, total) {
          onProgress?.call(received, total > 0 ? total : candidate.file.size);
        },
      );
    } on DioException catch (e) {
      await _deleteQuietly(part);
      if (CancelToken.isCancel(e)) {
        throw const UpdateException('已取消下载');
      }
      debugPrint('下载安装包失败: $e');
      throw const UpdateException('下载安装包失败，请检查网络后重试');
    }

    if (!await part.exists()) {
      throw const UpdateException('安装包保存失败，请重试');
    }

    final actualHash = await _sha256File(part);
    if (actualHash != candidate.file.sha256) {
      await _deleteQuietly(part);
      throw const UpdateException('安装包校验未通过，文件可能已损坏，请重新下载');
    }

    await _deleteQuietly(target);
    return part.rename(target.path);
  }

  /// 调起系统安装器覆盖安装。
  Future<InstallOutcome> install(File file) => installPackage(file);

  Future<void> _pruneStale({String? keepName}) async {
    try {
      final dir = await updateDir();
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is File && p.basename(entity.path) != keepName) {
          await _deleteQuietly(entity);
        }
      }
    } on Object catch (e) {
      debugPrint('清理旧更新包失败: $e');
    }
  }

  static Future<String> _sha256File(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase();
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on Object catch (e) {
      debugPrint('删除临时更新文件失败: $e');
    }
  }

  static Object? _tryJson(String s) {
    try {
      return jsonDecode(s);
    } on FormatException {
      return null;
    }
  }
}

/// 应用内更新状态阶段。
enum UpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  verifying,
  permissionRequired,
  launched,
  error,
}

@immutable
class AppUpdateState {
  const AppUpdateState({
    this.phase = UpdatePhase.idle,
    this.candidate,
    this.received = 0,
    this.total = 0,
    this.verifiedFile,
    this.errorMessage,
    this.dismissedVersion,
  });

  final UpdatePhase phase;
  final UpdateCandidate? candidate;
  final int received;
  final int total;
  final File? verifiedFile;
  final String? errorMessage;
  final String? dismissedVersion;

  double? get progress => total > 0 ? (received / total).clamp(0.0, 1.0) : null;

  bool get hasUpdate => candidate != null;

  bool get shouldShowBanner =>
      candidate != null &&
      candidate!.version != dismissedVersion &&
      phase != UpdatePhase.launched;

  AppUpdateState copyWith({
    UpdatePhase? phase,
    UpdateCandidate? candidate,
    bool clearCandidate = false,
    int? received,
    int? total,
    File? verifiedFile,
    bool clearVerifiedFile = false,
    String? errorMessage,
    bool clearError = false,
    String? dismissedVersion,
  }) => AppUpdateState(
    phase: phase ?? this.phase,
    candidate: clearCandidate ? null : (candidate ?? this.candidate),
    received: received ?? this.received,
    total: total ?? this.total,
    verifiedFile: clearVerifiedFile
        ? null
        : (verifiedFile ?? this.verifiedFile),
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    dismissedVersion: dismissedVersion ?? this.dismissedVersion,
  );
}

const _dismissedKey = 'update.dismissedVersion';

class AppUpdateController extends Notifier<AppUpdateState> {
  CancelToken? _cancelToken;
  bool _silentChecked = false;

  @override
  AppUpdateState build() {
    ref.onDispose(() => _cancelToken?.cancel());
    return const AppUpdateState();
  }

  AppUpdateService get _service => ref.read(appUpdateServiceProvider);
  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  /// 启动后静默检查一次更新（离线或服务端未部署清单时静默忽略）。
  Future<void> checkSilentlyOnce() async {
    if (_silentChecked) return;
    _silentChecked = true;
    await check(silent: true);
  }

  /// 检查更新；返回是否发现新版本。
  Future<bool> check({bool silent = false}) async {
    if (state.phase == UpdatePhase.downloading ||
        state.phase == UpdatePhase.verifying) {
      return state.hasUpdate;
    }
    final dismissed = _store.getString(_dismissedKey);
    if (!silent) {
      state = state.copyWith(
        phase: UpdatePhase.checking,
        dismissedVersion: dismissed,
        clearError: true,
      );
    }
    try {
      final candidate = await _service.checkForUpdate();
      if (candidate == null) {
        state = AppUpdateState(
          phase: silent ? UpdatePhase.idle : UpdatePhase.upToDate,
          dismissedVersion: dismissed,
        );
        return false;
      }
      state = state.copyWith(
        phase: UpdatePhase.available,
        candidate: candidate,
        received: 0,
        total: candidate.file.size,
        dismissedVersion: dismissed,
        clearError: true,
      );
      return true;
    } on UpdateException catch (e) {
      if (silent) return false;
      state = state.copyWith(phase: UpdatePhase.error, errorMessage: e.message);
      return false;
    } on Object catch (e) {
      debugPrint('检查更新异常: $e');
      if (silent) return false;
      state = state.copyWith(
        phase: UpdatePhase.error,
        errorMessage: '检查更新失败，请稍后重试',
      );
      return false;
    }
  }

  /// 忽略首页横幅中当前版本的更新提醒（仍可在设置页手动更新）。
  Future<void> dismissBanner() async {
    final v = state.candidate?.version;
    if (v == null) return;
    await _store.setString(_dismissedKey, v);
    state = state.copyWith(dismissedVersion: v);
  }

  /// 下载、校验并调起系统安装器覆盖安装。
  Future<void> downloadAndInstall() async {
    final candidate = state.candidate;
    if (candidate == null) return;
    if (state.phase == UpdatePhase.downloading ||
        state.phase == UpdatePhase.verifying) {
      return;
    }

    final token = CancelToken();
    _cancelToken = token;
    state = state.copyWith(
      phase: UpdatePhase.downloading,
      received: 0,
      total: candidate.file.size,
      clearError: true,
    );

    try {
      final file = await _service.downloadAndVerify(
        candidate,
        cancelToken: token,
        onProgress: (received, total) {
          if (state.phase != UpdatePhase.downloading) return;
          final nextPhase = received >= total && total > 0
              ? UpdatePhase.verifying
              : UpdatePhase.downloading;
          state = state.copyWith(
            phase: nextPhase,
            received: received,
            total: total,
          );
        },
      );
      _cancelToken = null;
      state = state.copyWith(verifiedFile: file);
      await _launchInstall(file);
    } on UpdateException catch (e) {
      _cancelToken = null;
      if (e.message == '已取消下载') {
        state = state.copyWith(
          phase: UpdatePhase.available,
          received: 0,
          clearError: true,
        );
      } else {
        state = state.copyWith(
          phase: UpdatePhase.error,
          errorMessage: e.message,
        );
      }
    } on Object catch (e) {
      _cancelToken = null;
      debugPrint('更新过程异常: $e');
      state = state.copyWith(
        phase: UpdatePhase.error,
        errorMessage: '更新失败，请稍后重试',
      );
    }
  }

  /// 取消进行中的下载。
  void cancelDownload() {
    _cancelToken?.cancel();
    _cancelToken = null;
  }

  /// 权限授予后直接用已校验的安装包继续安装（不再重复下载）。
  Future<void> retryInstall() async {
    final file = state.verifiedFile;
    if (file != null && await file.exists()) {
      await _launchInstall(file);
    } else {
      await downloadAndInstall();
    }
  }

  Future<void> _launchInstall(File file) async {
    final outcome = await _service.install(file);
    switch (outcome) {
      case InstallOutcome.launched:
        state = state.copyWith(phase: UpdatePhase.launched, clearError: true);
      case InstallOutcome.permissionRequired:
        state = state.copyWith(
          phase: UpdatePhase.permissionRequired,
          clearError: true,
        );
      case InstallOutcome.unsupported:
        state = state.copyWith(
          phase: UpdatePhase.error,
          errorMessage: '当前平台暂不支持应用内安装，请前往官网下载更新',
        );
      case InstallOutcome.failed:
        state = state.copyWith(
          phase: UpdatePhase.error,
          errorMessage: _service.isDesktop
              ? '无法启动 Windows 应用安装程序，安装包已保存至：${file.path}'
              : '调起系统安装器失败，请重试或前往官网下载',
        );
    }
  }
}

Future<Directory> _defaultUpdateDir(bool isDesktop) async {
  if (isDesktop) {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) {
      return Directory(p.join(downloads.path, 'JikeLog-Updates'));
    }
  }
  final temp = await getTemporaryDirectory();
  return Directory(p.join(temp.path, 'jikelog-update'));
}

final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  final features = ref.watch(platformFeaturesProvider);
  final tls = ref.watch(tlsPolicyProvider);
  return AppUpdateService(
    baseUrl: AppConfig.apiBaseUrl,
    dio: tls.dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
    ),
    isDesktop: features.isDesktop,
    currentVersion: appVersion,
    updateDir: () => _defaultUpdateDir(features.isDesktop),
    installPackage: features.isDesktop ? installWindowsMsix : installAndroidApk,
  );
});

final appUpdateControllerProvider =
    NotifierProvider<AppUpdateController, AppUpdateState>(
      AppUpdateController.new,
    );
