package com.jikelog.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    // 极光厂商通道点按通知时携带的 URI 不是 App 路由，关闭 Flutter 的深链接处理以免打开空白页
    override fun shouldHandleDeeplinking(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 设备时区（IANA 名称），本地提醒按它计算时刻
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "jikelog/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "timeZone" -> result.success(TimeZone.getDefault().id)
                else -> result.notImplemented()
            }
        }
    }
}
