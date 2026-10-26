---
title: 下载
description: 下载即刻日志 Android 版（APK）与 Windows 版（MSIX），查看系统要求、安装步骤与安装包校验值。
sidebar: false
aside: false
---

# 下载即刻日志

Android 版与 Windows 版是同一个应用：用同一个账号登录，数据在手机和电脑之间实时同步。

<DownloadCards />

## 安装 Android 版

1. 在手机上下载 APK，打开它。
2. 第一次安装时，系统会提示"允许安装未知应用"，按提示为浏览器或文件管理器开启后再安装。
3. 打开即刻日志，阅读并同意隐私政策后注册账号。详见[快速上手](/guide/quick-start)。

以后发布新版本时，下载新的 APK 直接覆盖安装即可，数据会保留。

## 安装 Windows 版

1. 下载 MSIX 安装包和证书 `jikelog-windows.cer`，放在同一个文件夹。
2. **只在第一次安装前**：核对证书指纹（在下载卡片的"校验信息"中）后，把证书导入"受信任的人"（需要管理员权限）。
3. 双击 MSIX 安装包，点击"安装"。

每一步的截图与命令见 [Windows 版](/guide/windows)。升级时直接双击新版本的安装包，不用再导入证书。

## 核对安装包

展开下载卡片的"校验信息"，其中的 SHA-256 是安装包的校验值，与 GitHub Release 上的 `.sha256` 文件一致。核对方法：

- **Windows**：在下载目录打开 PowerShell，执行 `Get-FileHash .\jikelog-<版本>.msix`。
- **macOS / Linux**：执行 `shasum -a 256 jikelog-<版本>.apk`。

结果与页面上的一致，说明安装包完整、未被篡改。

## 历史版本

每个版本的更新内容见[更新日志](/changelog/)，历史版本的安装包见 [GitHub Release](https://github.com/vvangz/JikeLog/releases)。
