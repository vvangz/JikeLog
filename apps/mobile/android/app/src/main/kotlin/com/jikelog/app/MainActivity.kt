package com.jikelog.app

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    // 极光厂商通道点按通知时携带的 URI 不是 App 路由，关闭 Flutter 的深链接处理以免打开空白页
    override fun shouldHandleDeeplinking(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // 设备时区（IANA 名称），本地提醒按它计算时刻
        MethodChannel(messenger, "jikelog/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "timeZone" -> result.success(TimeZone.getDefault().id)
                else -> result.notImplemented()
            }
        }

        // 应用内更新：调起系统安装器覆盖安装已校验的 APK
        MethodChannel(messenger, "jikelog/updater").setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("INVALID_PATH", "缺少安装包路径", null)
                        return@setMethodCallHandler
                    }
                    result.success(installApk(path))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun installApk(path: String): String {
        val file = File(path)
        val allowedDir = File(cacheDir, "jikelog-update").canonicalFile
        val canonical = runCatching { file.canonicalFile }.getOrNull() ?: return "failed"
        // 纵深防御：只允许安装缓存更新目录内的 .apk 文件
        val allowedPrefix = allowedDir.path + File.separator
        if (!canonical.isFile ||
            !canonical.path.startsWith(allowedPrefix) ||
            !canonical.name.endsWith(".apk", ignoreCase = true)
        ) {
            return "failed"
        }

        if (!packageManager.canRequestPackageInstalls()) {
            val settingsIntent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            return runCatching {
                startActivity(settingsIntent)
                "permission_required"
            }.getOrDefault("failed")
        }

        val uri = runCatching {
            FileProvider.getUriForFile(this, "$packageName.update.fileprovider", canonical)
        }.getOrNull() ?: return "failed"

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return runCatching {
            startActivity(intent)
            "launched"
        }.getOrDefault("failed")
    }
}
