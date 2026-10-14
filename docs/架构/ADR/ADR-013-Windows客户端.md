# ADR-013 Windows 客户端：同一套 Flutter 代码、按平台开关的功能与 MSIX 分发

- 状态：已采纳
- 日期：2026-10-14

## 背景

需求要求开发 Windows 与 Android 客户端，先做 Android。v1.0.0 之后开始 Windows 版。

Android 版依赖的插件中，有几个没有 Windows 实现：

| 插件 | 用途 | Windows |
|---|---|---|
| webview_flutter | 笔记富文本编辑器（打包进 App 的 Tiptap 页面） | 不支持 |
| device_calendar_plus | 备忘录写入系统日历 | 不支持 |
| jpush_flutter | 极光推送 | 不支持 |
| open_filex | 用系统应用打开附件 | 不支持 |
| just_audio | 播放音频附件 | 不支持 |
| 自写的 `jikelog/device` 通道 | 读取 IANA 时区 | 只有 Android |

`flutter_local_notifications` 支持 Windows 的通知（Toast），也能排定定时通知。但只有带包标识（MSIX 安装）的应用才能取消已排定的通知、读取待发列表。提醒依赖这两项：备忘修改或删除后，旧提醒必须取消。

## 决策

### 1. 同一套代码，按平台开关功能

`PlatformFeatures`（`lib/core/platform/platform_features.dart`）集中描述各平台能用的功能，通过 Riverpod 提供，测试中可以覆盖。`flutter test` 中固定为 Android，使本机（Windows）与 CI（Linux）上的测试行为一致。

| 功能 | Android | Windows |
|---|---|---|
| 系统日历 | ✓ | 关闭（设置页不显示开关） |
| 极光推送 | ✓ | 关闭（反正尚未开通） |
| 富文本编辑器 | ✓ | 关闭：笔记用 Markdown 打开，**不改笔记保存的格式**；Windows 上新建的笔记为 Markdown |
| 分享面板 | ✓ | 导出改为选择文件夹保存 |
| 精确闹钟权限 | ✓ | 不需要 |

### 2. 各项替代

- **时区**：C++ 运行器实现同名通道 `jikelog/device`，用 `Windows.Globalization.Calendar.GetTimeZone()` 读取 IANA 时区，Dart 代码不变。
- **音频**：Windows 上的 `Player` 改用 `audioplayers`（Media Foundation）。第三方的 `just_audio_windows` 使用已废弃的 experimental coroutine，新版 MSVC 拒绝编译，且已无人维护。
- **打开附件**：交给系统默认应用（`url_launcher` 打开 `file:` 地址）。可执行文件（`.exe`、`.bat`、`.lnk`、`.ps1` 等）只打开所在文件夹，不直接运行，防止被篡改的附件在桌面上执行。
- **导出**：`file_picker` 的"另存为"要求先把整个文件读进内存，含附件的导出可能很大，所以改为选择文件夹，直接流式下载到那里；重名加序号，失败时删除不完整的文件。
- **快捷键**：Ctrl+F 搜索、Ctrl+N 在当前模块新建，由应用外壳统一处理，只在模块首页位于最上层时生效。
- **窗口**：标题"即刻日志"，默认 1280×800，最小 400×560（再窄时手机布局也放不下）。宽屏布局沿用 M1 的响应式外壳（>840 侧栏常驻）。

### 3. 富文本编辑器：先不提供

Windows 上的 WebView2 插件（`webview_windows` 最后发布于 2024-02，`flutter_inappwebview` 于 2024-10）都已很久没有更新。`just_audio_windows` 已经说明，这类原生插件会随新版编译器失效。用户同意先只提供 Markdown。等 `webview_flutter` 有官方的 Windows 实现后再接入。

正文本来就统一存为 Markdown（ADR-007），所以在 Windows 上编辑富文本笔记不会丢内容；Android 上仍按富文本打开。

### 4. 分发：MSIX + 自签名证书

| 方案 | 结论 |
|---|---|
| 普通安装包（无包标识） | 不能取消已排定的通知，提醒会在备忘修改或删除后照样弹出 |
| Microsoft Store | 需要注册开发者账号、填写商店资料、每次发布等待审核；以后可以再上架 |
| **MSIX + 自签名证书** | 采用。功能完整，免费，发布自动化与 APK 相同 |

- MSIX 由 `msix` 包生成（`pubspec.yaml` 的 `msix_config`）。包标识 `JikeLog.App`，发布者 `CN=JikeLog`。声明 `internetClient` 与 `microphone`（录音）。
- 通知激活器的 CLSID 必须与 App 初始化通知时的 GUID 相同，由测试保证。
- 证书为 RSA 3072 的代码签名证书，有效期 10 年，用 OpenSSL 生成（不经过系统证书存储）。PFX 只放在 `windows-signing` 环境中，公钥 `.cer` 随每个 Release 发布，也保存在 `deploy/windows/`。签名时加时间戳，证书到期后已发布的安装包仍可验证。
- **用户第一次安装前**，要以管理员身份把 `.cer` 导入"受信任的人"（`LocalMachine\TrustedPeople`）。只信任这一张证书，不是根证书，不能用来签发其他证书。
- 发布流程与 APK 相同，分两个任务：构建任务没有密钥，确认标签在 `main` 上后构建并打包未签名的 MSIX；签名任务不检出仓库代码，只用 `signtool` 签名、核对签名者的 SHA-1 指纹，再上传到 Release。

## 后果

- Windows 版第一次安装多一步导入证书。
- Windows 版暂时没有富文本编辑、系统日历与推送。
- 本机用 `flutter run -d windows` 调试时没有包标识，通知不能取消，待发列表为空。这只影响开发，安装 MSIX 后正常。
- 构建 Windows 版需要 Visual Studio 的 C++ 桌面开发组件，以及 Windows 的开发者模式（插件需要符号链接）。CI 的 Windows 构建机已具备。
