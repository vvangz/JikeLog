# 即刻日志 Android 客户端（Flutter）

```bash
bash ../../scripts/fetch-fonts.sh   # 首次：下载字体
flutter pub get
flutter run                         # 运行到模拟器/真机
flutter analyze && flutter test --coverage
```

- 主题：`lib/app/theme/app_theme.dart`，颜色和尺寸来自生成的 `jk_tokens.g.dart`（请勿手改，改令牌后执行 `pnpm tokens`）
- 组件：`lib/shared/ui/`
- 包名：`com.jikelog.app`，minSdk 26（Android 8.0）

目录约定和开发规范见仓库根目录的 [CONTRIBUTING.md](../../CONTRIBUTING.md)。
