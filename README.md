# Mini Computer Use

一个 macOS 原生桌面操控实验。控制程序启动独立的演示 App，通过 Accessibility 读取复选框的角色、标识和值，执行一次 `AXPress`，再回读值确认状态从 0 变为 1。完整模式使用 ScreenCaptureKit 为演示窗口拍前后两张 PNG。

程序使用规则决定动作，所有操作和截图在本机完成。项目只启动和操作自己创建的演示窗口。

## 运行

需要 macOS 14 或更新版本、Xcode Command Line Tools 和已登录的图形桌面会话。若尚未安装 Command Line Tools，运行 `xcode-select --install`。

```sh
git clone https://github.com/jadepam/mini-computer-use.git
cd mini-computer-use
bash build.sh
.build/mini-computer-use status
```

按需请求权限。

```sh
.build/mini-computer-use request-accessibility
.build/mini-computer-use request-screen
```

在「系统设置 → 隐私与安全性」中，给系统提示的发起者开启「辅助功能」和「屏幕与系统音频录制」。从终端运行时，macOS 可能把请求归给 Terminal 或其他终端宿主。以弹窗里的名字为准，按系统提示重新打开它，再跑一次 `status`。

```sh
.build/mini-computer-use run --ax-only
.build/mini-computer-use run
```

`run --ax-only` 只需辅助功能权限。完整模式需要两项权限，把 `before.png` 和 `after.png` 写到 `captures/<本次运行的 ID>/`。窗口会在演示结束后关闭。

预期输出

```text
Before: AXCheckBox Mark done = 0
Action: AXPress
Verified: AXCheckBox Mark done = 1
```

## 两条系统路径

| 路径 | 用途 |
| --- | --- |
| Accessibility | 按进程 ID 读取控件。通过 `AXPress` 触发动作并回读 `AXValue` |
| ScreenCaptureKit | 按进程 ID 和窗口标题选定窗口，生成两张单帧截图 |

`Sources/MiniComputerUse.swift` 是控制程序。`Sources/Target.swift` 是目标窗口，其中自检通过 AppKit 的 `accessibilityPerformPress()` 在进程内触发复选框，可单独验证界面逻辑。自检可额外接收一个已存在的空目录，用于渲染前后两张控件状态图。

```sh
'.build/Mini Computer Use Target.app/Contents/MacOS/Target' --self-test
```

## License

[MIT](LICENSE)
