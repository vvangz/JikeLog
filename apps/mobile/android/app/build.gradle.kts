plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.jikelog.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // 本地通知插件在旧版 Android 上需要 java.time 等新 API
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.jikelog.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26 // Android 8.0，精确闹钟与通知渠道所需
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 极光推送：AppKey 不入库，由环境变量 JPUSH_APPKEY 注入；为空时 App 不初始化推送（只用本地提醒）
        manifestPlaceholders += mapOf(
            "JPUSH_PKGNAME" to "com.jikelog.app",
            "JPUSH_APPKEY" to (System.getenv("JPUSH_APPKEY") ?: ""),
            "JPUSH_CHANNEL" to "developer-default",
        )
    }

    buildTypes {
        release {
            // 正式签名在 v0.9.0 接入：keystore 不入库，由 CI Secrets 注入 key.properties
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
