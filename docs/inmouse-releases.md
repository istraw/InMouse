# InMouse 发布与应用内更新

InMouse 使用独立的 Sparkle Ed25519 更新签名、公钥及 `com.istraw.inmouse` Release Bundle ID。旧手势 JSON 仍位于 `~/Library/Application Support/StrokeMouse/gestures.json`，首次启动正式版会导入先前开发版的偏好设置。首次安装正式版需要重新授权辅助功能。

## 更新来源

“检查更新”通过 Sparkle 获取与运行架构对应的更新列表：

- `https://github.com/istraw/StrokeMouse/releases/latest/download/appcast-arm64.xml`
- `https://github.com/istraw/StrokeMouse/releases/latest/download/appcast-x86_64.xml`

0.0.41 的旧版本仍是手动更新入口，需先手动安装 0.1.0；后续版本可以检查、下载并安装更新。相同版本会提示已是最新版本。

更新签名私钥保存在本机登录钥匙串中，Sparkle account 为 `inmouse-istraw`。项目只保存公钥，禁止提交或上传私钥到公开仓库。未来发布须使用同一密钥，换电脑前可用 Sparkle 的 `generate_keys --account inmouse-istraw -x <安全文件>` 导出并妥善备份。

## 本机构建

在 `project.yml` 更新 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION` 后生成工程。Build 必须递增，使用 `major * 1000000 + minor * 1000 + patch`，例如 0.1.0 对应 1000。

```bash
./scripts/generate_project.sh
# SPARKLE_PUBLIC_KEY 使用 project.yml 中的公钥；签名证书选本机可用身份。
SPARKLE_PUBLIC_KEY='<项目公钥>' CODE_SIGN_IDENTITY='<签名证书>' ARCH=arm64 ./scripts/package-app.sh
SPARKLE_PUBLIC_KEY='<项目公钥>' CODE_SIGN_IDENTITY='<签名证书>' ARCH=x86_64 ./scripts/package-app.sh
./scripts/generate-personal-appcasts.sh
```

安装包使用当前本机 SDK 时，通过 `EXPECTED_MACOS_SDK_MAJOR` 指定主版本；支持的最低系统仍为 macOS 14。

发布到同一 GitHub Release：两个架构的 ZIP、DMG、TAR.GZ，以及 `appcast-arm64.xml`、`appcast-x86_64.xml`、`SHA256SUMS.txt`。先上传全部资产到草稿，检查完成后再发布，避免用户读到不完整的更新源。必须是正式发布（非 prerelease），GitHub 的 `/latest/` 链接才会指向它。

## Apple 签名状态

0.1.0 使用本机 Apple Development 证书签名，并使用独立 Ed25519 密钥签署更新档案；未进行 Apple 公证。首次从网络下载时，macOS 可能阻止启动，需要到“系统设置 → 隐私与安全性”允许打开。这与 Sparkle 更新包签名是两回事，不能宣称该包已通过 Developer ID 公证。

若需要常规对外分发体验，后续须配置 Developer ID Application 证书与公证凭据，并保留现有 Sparkle 密钥。现有 GitHub Actions Release 工作流改为手动触发，仅在对应发布证书／公证 secrets 配好后使用；本地发布不导出 Apple 证书私钥到 GitHub。

## 0.1.1 状态栏模式

升级后首次启动会启用“隐藏 Dock 图标”，保持状态栏入口可见，并选用新的鼠标＋环绕轨迹单色模板图标。打开设置时 Dock 图标临时显示，关闭设置后自动隐藏，应用与手势继续运行；从状态栏菜单可以重新打开设置或退出。之后可在通用设置自行调整，后续启动不会反复覆盖选择。
