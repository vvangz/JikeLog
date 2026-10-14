# 发布 Windows 版

> 适用版本：v1.1.0 及以上

Windows 安装包（MSIX）由 GitHub Actions 构建并签名，附在每个版本的 GitHub Release 上，做法与[《发布 APK》](发布APK.md)相同（ADR-013）。

## 1. 流程

1. 合并 Release Please 的发布 PR 后，`release-please.yml` 打上标签并创建 Release，随后调用 `release-windows.yml`（与部署、APK 并行）。
2. **构建**（Windows 构建机，没有密钥、只读权限）：检出标签，确认它在 `main` 上，`flutter build windows`，再用 `dart run msix:create` 打包为未签名的 MSIX（配置见 `apps/mobile/pubspec.yaml` 的 `msix_config`）。
3. **签名并上传**（`windows-signing` 环境）：不检出仓库代码。先核对收到的安装包与构建任务输出的 SHA-256 一致；把 PFX 导入构建机的用户证书存储，用 `signtool` 按指纹签名并加时间戳（HTTPS），核对签名者的 SHA-1 指纹与仓库变量 `WINDOWS_CERT_THUMBPRINT` 一致，再上传：
   - `jikelog-<版本>.msix` 与 `.sha256`
   - `jikelog-windows.cer`（证书公钥，由 PFX 导出）

MSIX 的版本号为 `<版本>.0`；只为正式版本构建。

## 2. 签名证书

| 项目 | 值 |
|---|---|
| 主题（Subject） | `CN=JikeLog`，须与 `msix_config.publisher` 完全一致 |
| 类型 | RSA 3072，只用于代码签名，有效期 10 年（到 2036-10） |
| SHA-1 指纹 | `F44C3F6641E3DB7CE741AB769F6BE2063E4AB890` |
| 文件 | `jikelog-windows.pfx`（私钥，密码在 `windows-pfx-password.txt`）、`jikelog-windows.cer`（公钥，也在仓库的 `deploy/windows/`） |

PFX 与密码和 APK 的签名密钥放在一起离线备份。

- **丢失**：用新证书签名的版本，用户要先导入新证书才能安装。若证书主题仍为 `CN=JikeLog`，已安装的 App 可以直接升级。
- **泄露**：导入过该证书的电脑都会信任别人用它签名的安装包。立即换新证书，在 Release 与 README 中公告，通知用户删除旧证书（`certlm.msc` → 受信任的人 → 证书 → `JikeLog`）。
- **到期前**（2036 年）：用同一主题生成新证书，更新 Secrets 与 `WINDOWS_CERT_THUMBPRINT`，随下一个版本发布新的 `.cer`。

## 3. GitHub 配置

**环境 `windows-signing`**（只允许 `main` 分支）。Secrets 用命令从文件设置：

```bash
cd <证书所在目录>
base64 -w0 jikelog-windows.pfx | gh secret set WINDOWS_PFX_BASE64 --env windows-signing
gh secret set WINDOWS_PFX_PASSWORD --env windows-signing < windows-pfx-password.txt
```

**仓库变量**：`WINDOWS_CERT_THUMBPRINT`（上表中的 SHA-1 指纹），以及与 APK 共用的 `APP_API_BASE`、`APP_E2E_PUBLIC_KEY`。

## 4. 重新构建某个版本

```bash
gh workflow run release-windows.yml --ref main -f version=1.1.0
```

## 5. 在本机构建与调试

需要 Visual Studio 2022 的"使用 C++ 的桌面开发"组件与 ATL（通知、安全存储插件用到），并打开 Windows 的开发者模式（Flutter 插件需要符号链接）。已装生成工具但缺 ATL 时，用 Visual Studio Installer 修改安装，加上 `Microsoft.VisualStudio.Component.VC.ATL`：

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --add Microsoft.VisualStudio.Component.VC.ATL"
start ms-settings:developers
```

```bash
cd apps/mobile
flutter run -d windows                    # 调试（连接本地开发服务器）
flutter build windows --release \
  --dart-define=JIKELOG_API_BASE=https://www.pingvv.top \
  --dart-define=JIKELOG_E2E_PUBLIC_KEY=<公钥>
dart run msix:create --build-windows false   # 生成未签名的 build/windows/x64/runner/Release/jikelog.msix
```

- `flutter run` 时 App 没有包标识：通知不能取消，待发列表为空。提醒相关的功能请用安装后的 MSIX 验证。
- 未签名的 MSIX 不能直接安装。本机验证可用 `signtool` 和证书签名后安装，或从 CI 下载正式发布的安装包。
