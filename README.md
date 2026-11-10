<div align="center">
  <img src="StrokeMouse/Resources/Assets.xcassets/BrandAppIcon.imageset/BrandAppIcon.png" width="128" alt="InMouse 图标" />
  <h1>InMouse</h1>
  <p>macOS 鼠标与触控板手势工具，让窗口操作跟随鼠标。</p>
  <p>
    <a href="https://github.com/istraw/InMouse/releases/latest">下载 InMouse</a> ·
    <a href="https://github.com/istraw/InMouse/issues">反馈问题</a> ·
    <a href="LICENSE">AGPL-3.0 许可证</a>
  </p>
</div>

InMouse 基于 [Licoy/StrokeMouse](https://github.com/Licoy/StrokeMouse) 开发，在原有手势能力上扩展窗口控制、状态栏体验和独立应用内更新。本仓库的默认开发分支为 **`personal`**；`main` 保留用于跟随上游项目。

## 下载与安装

要求 **macOS 14 或以上**。

| Mac 类型 | 安装包 |
| --- | --- |
| Apple Silicon（M 系列） | [下载 arm64 DMG](https://github.com/istraw/InMouse/releases/latest/download/InMouse-macos-arm64.dmg) |
| Intel | [下载 x86_64 DMG](https://github.com/istraw/InMouse/releases/latest/download/InMouse-macos-x86_64.dmg) |

打开 DMG，将 **InMouse.app** 拖入“应用程序”。首次打开后，在系统设置中授予辅助功能权限，即可使用全局手势和窗口操作。

当前安装包使用 Apple Development 证书签名，**尚未通过 Apple 公证**。若 macOS 拦截首次启动，可在“系统设置 → 隐私与安全性”中允许打开。

已安装正式版后，可在应用内点击 **“检查更新”**。安装包与更新列表来自本仓库，更新档案使用独立的 Sparkle Ed25519 密钥签名。

## InMouse 的新增与调整

### 更完整的窗口控制

- 按屏幕可用区域的百分比自定义窗口 **X、Y、宽度和高度**，支持实时预览。
- 提供左半屏、右半屏、居中 80% 等布局预设。
- 恢复窗口前一个位置和大小，重复最大化不会覆盖原来的恢复记录。
- 单独最大化窗口高度或宽度，移动窗口到下一个显示器。
- 最小化目标应用的全部窗口，恢复一个或全部最小化窗口。
- 处理应用最小尺寸等限制，减少窗口已经调整却报告失败的情况。

[窗口操作的完整行为与限制](docs/window-controls.md)

### 对鼠标下的窗口执行手势

新建手势默认选择 **“指针位置所属应用”**：把鼠标放到非激活窗口上，直接按住右键绘制，即可对该窗口执行动作。目标在按下触发键时锁定，绘制途中移到别处不会改变目标。

已有手势保留原设置，也可在编辑器的“手势目标”中切换。快捷键动作会先激活锁定的目标窗口，再发送快捷键。

### 状态栏驻留

- 关闭设置窗口后隐藏 Dock 图标，应用和手势继续运行。
- 保留状态栏入口，可重新打开设置、暂停手势或退出应用。
- 使用面性单色鼠标图标，自动适配 macOS 明暗背景。
- 可在通用设置中调整 Dock 和状态栏显示偏好。

### 独立更新与版本管理

窗口控制、图标与状态栏调整统一在 **0.1.0 整合版（build 1003）**。展示版本与内部构建号独立，Sparkle 按递增的 build 判断更新，因此早期 0.1.1、0.1.2 构建也可更新到整合版。

日常修改先累积并验证，需要正式发布时再统一发版。

[发布与更新说明](docs/inmouse-releases.md)

## 保留的基础能力

继承上游的鼠标绘制、鼠标按键映射、鼠标组合、触控板绘制、实验性多指触控手势、滚动增强、按应用配置、手势导入导出，以及快捷键、打开应用、媒体控制、Shell / AppleScript 等动作。

实验性多指触控使用 Apple 未公开的触控接口，可能受系统更新影响。更多原版能力可参考[上游中文说明](README_zh-Hans.md)和[保留的上游英文说明](README_upstream.md)；这些是原项目文档，安装 InMouse 请使用本页的下载入口。

## 配置与备份

为兼容已有手势，配置文件仍保存在：

```text
~/Library/Application Support/StrokeMouse/gestures.json
```

可在应用的手势列表中点击“导出”备份。切换到 InMouse 的独立正式版后，首次需要重新确认辅助功能授权。

## 本地开发

使用 Swift / SwiftUI、Xcode 和 XcodeGen，工程及 Scheme 名称保留为 `StrokeMouse`。

```bash
brew install xcodegen
./scripts/generate_project.sh
open StrokeMouse.xcodeproj
```

使用本机签名身份构建到 `output/InMouse.app`：

```bash
CODE_SIGN_IDENTITY='<本机签名证书>' ./scripts/build.sh --release
```

## 来源与许可证

感谢 [Licoy/StrokeMouse](https://github.com/Licoy/StrokeMouse) 提供原始实现。InMouse 保留原项目的 [AGPL-3.0 许可证](LICENSE) 和来源信息，本仓库的个人功能修改在 `personal` 分支维护。
