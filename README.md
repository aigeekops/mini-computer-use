# Mini Computer Use

一个用 Electron 和 Swift 实现的 macOS 桌面操控实验。自动在独立的 AppKit 表单里填写 `Monthly report`，勾选 `Mark reviewed`，保存并核对界面回执与实际文件。

## 快速开始

需要 macOS 14 或更新版本、Node.js 22.12 或更新版本、Xcode Command Line Tools，以及已登录的图形桌面。若尚未安装 Command Line Tools，运行 `xcode-select --install`。

```sh
git clone https://github.com/aigeekops/mini-computer-use.git
cd mini-computer-use
npm ci
npm run build:native
npm start
```

1. 点「检查权限」。如果显示 `Accessibility: false`，点「申请辅助功能」，按 macOS 提示启用对应程序。开发模式下授权对象可能显示为 Electron 或启动终端，以系统提示为准。重新打开工作台，确认显示 `Accessibility: true`。
2. 点「运行实验」。工作台会打开演示表单，填入标题、勾选复核、保存草稿，再回读状态。
3. 要保留操作前后截图时，先点「申请屏幕录制」并按提示授权。重开工作台后确认 `Screen recording: true`，再勾选「保存操作前后截图」运行。

逐步日志会显示 `Enter title`、`Mark reviewed` 和 `Save draft`。工作台核对窗口回执和文件内容后，才会显示 `Verified`。

日志中的 `Output` 指向本次运行的独立目录 `runs/<本次运行 ID>/`。打开里面的 `draft.json`，可以核对标题和复核状态。启用截图时，同一目录还包含 `before.png` 和 `after.png`。

```json
{"title":"Monthly report","reviewed":true}
```

## 架构

| 层 | 职责 |
| --- | --- |
| `electron/ui/` | 接收按钮操作，显示权限状态与原生进程的日志 |
| `electron/preload.cjs`、`electron/main.cjs` | 向页面暴露固定指令和日志接口，校验 IPC 来源，启动 Swift 进程 |
| `Sources/MiniComputerUse.swift` | 调度观察、执行和读回状态，核对保存回执与文件 |
| `Sources/DraftWorkflow.swift` | 定义任务目标、按状态选动作、校验草稿内容 |
| `Sources/DesktopDriver.swift` | 按目标 PID 和控件标识使用 Accessibility 执行动作，按需用 ScreenCaptureKit 截取单个窗口 |
| `Sources/Target.swift` | 担任目标应用，提供真实的 AppKit 表单和本地 JSON 保存行为 |

示例使用确定性的规则，运行时无需模型 API。Renderer 加载本地界面，执行器只访问本次启动的演示 App。截图供查看，任务决策使用 AX 状态。

## 命令行与测试

可以同样从终端调用原生执行器。

```sh
.build/mini-computer-use status
.build/mini-computer-use request-accessibility
.build/mini-computer-use run --ax-only
.build/mini-computer-use request-screen
.build/mini-computer-use run
```

下面两项可在未开启系统权限时运行。Electron 冒烟测试检查页面加载和 IPC 通路。AppKit 自检在目标进程内验证表单与文件写入。跨进程验证使用上面的「运行实验」或命令行 `run`，并需要对应的 macOS 授权。

```sh
npm test
'.build/Mini Computer Use Target.app/Contents/MacOS/Target' --self-test
```

## License

[MIT](LICENSE)
