# 发布 APK

> 适用版本：v1.0.0 及以上

正式版 Android 安装包由 GitHub Actions 构建并签名，附在每个版本的 [GitHub Release](https://github.com/vvangz/JikeLog/releases) 上。

## 1. 流程

1. 合并 Release Please 的发布 PR 后，`release-please.yml` 打上 `v<版本>` 标签并创建 Release。
2. 随后调用 `release-apk.yml`（与部署并行），分两个任务，签名密钥不与仓库代码同处一台机器：
   1. **构建**（没有密钥、只读权限）：检出该版本的标签，确认标签指向的提交在 `main` 上，构建 `flutter build apk --release`（Gradle 用调试密钥签名），作为产物交给下一步；
   2. **签名并上传**（`apk-signing` 环境）：不检出仓库代码，只用 `apksigner` 把签名换成正式密钥，核对签名证书指纹与仓库变量 `APK_CERT_SHA256` 一致后，把 `jikelog-<版本>.apk` 和 `jikelog-<版本>.apk.sha256` 上传到 Release。
3. 用户从 Release 页面下载安装，新版本直接覆盖安装。

`versionCode` 由版本号推出：`1.2.3` → `10203`，保证每次升级递增。因此只为正式版本（不带 `-rc` 等后缀）构建 APK，次版本号与修订号不超过 99。

## 2. 签名密钥

签名密钥（keystore）决定了"谁能发布这个 App 的更新"：

- **丢失**：已安装的 App 无法再覆盖升级，用户只能卸载（本机数据随之删除）后重装。
- **泄露**：别人可以做出能覆盖安装你 App 的安装包。

所以 keystore 和密码要**离线备份**，并且只放在 GitHub 的 `apk-signing` 环境中。

| 项目 | 值 |
|---|---|
| 文件 | `jikelog-release.jks`（PKCS12，RSA 4096，有效期约 27 年） |
| 别名 | `jikelog` |
| 密码 | 在同目录的 `key.properties` 中（storePassword 与 keyPassword 相同） |
| 证书 SHA-256 | `0B:34:89:42:D7:97:4D:35:59:70:41:64:86:4F:73:C3:2C:8C:0E:93:BD:BA:C8:E3:83:44:58:0B:95:BE:EE:73` |

备份方法：把 `jikelog-release.jks` 和 `key.properties` 两个文件一起存进密码管理器（作为附件）或加密 U 盘，至少两处。上传到 GitHub、完成备份后，删除电脑上其他位置的明文副本（如下载目录）。

## 3. GitHub 配置

**环境 `apk-signing`**（Settings → Environments）：只允许 `main` 分支（不要加 `v*` 标签：从标签运行时，工作流文件取自标签，能推送标签的人就能改写它）。Secrets 用命令从文件设置，不要从终端复制粘贴（Windows 换行符会让密钥无法读取）：

```bash
cd <keystore 所在目录>
base64 -w0 jikelog-release.jks | gh secret set ANDROID_KEYSTORE_BASE64 --env apk-signing
gh secret set ANDROID_KEY_PROPERTIES --env apk-signing < key.properties
```

**仓库变量**（Settings → Secrets and variables → Actions → Variables，不是机密）：

| 变量 | 值 |
|---|---|
| `APP_API_BASE` | 正式服务器地址：`https://www.pingvv.top` |
| `APP_E2E_PUBLIC_KEY` | 传输加密公钥，服务器上 `init-env.sh` 的输出 |
| `APK_CERT_SHA256` | 上表中的证书 SHA-256 指纹 |

## 4. 重新构建某个版本

在 Actions 页面运行"发布 APK"工作流并填写版本，或者：

```bash
gh workflow run release-apk.yml --ref main -f version=1.0.0
```

已上传的同名文件会被替换。

## 5. 在本机构建

```bash
cd apps/mobile
JIKELOG_KEY_PROPERTIES=<keystore 所在目录>/key.properties \
flutter build apk --release --build-number=10000 \
  --dart-define=JIKELOG_API_BASE=https://www.pingvv.top \
  --dart-define=JIKELOG_E2E_PUBLIC_KEY=<公钥>
```

- 不设 `JIKELOG_KEY_PROPERTIES`（也没有 `android/key.properties`）时，release 构建用调试密钥签名，只能自己测试，不能发给用户。
- 核对签名：`apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk`，`certificate SHA-256 digest` 应与上表一致。

## 6. 需要发布新版 App 的情况

下列改动编译进了 App，改完后必须发布新版本，已安装的旧版本不会自动跟上：

- 服务器地址（`APP_API_BASE`）。
- 传输加密密钥轮换：先在服务器上把旧私钥填到 `JIKELOG_E2E_PREVIOUS_PRIVATE_KEY`，新旧版本共存期间都能连接；所有用户升级后再去掉。
- 服务器证书不再由 Let's Encrypt 签发：正式版只信任 Let's Encrypt 的根证书（ISRG Root X1、X2），必须先发布信任新证书颁发机构的 App。
- 附件改存其他域名的对象存储（例如阿里云 OSS）：同上，App 要信任该域名的证书。
