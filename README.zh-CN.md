# LaunchTaskKit

LaunchTaskKit 是一个轻量的 Swift 启动任务调度库，通过宏完成自动注册，支持主线程同步任务、可跟踪的异步任务、生命周期阶段、优先级、RunLoop 空闲调度和启动来源补充。

## 环境要求

- iOS 15.0+
- macOS 12.0+
- Swift 6.0+

## Swift Package Manager

添加 Package 依赖，并将 `LaunchTaskKit` product 链接到目标 Target：

```swift
dependencies: [
    .package(
        url: "https://github.com/FeliksLv01/LaunchTaskKit.git",
        from: "0.0.2"
    )
]
```

使用宏的 Swift Target 需要启用 `SymbolLinkageMarkers`：Xcode 的 Other Swift Flags 设置 `-enable-experimental-feature SymbolLinkageMarkers`；SwiftPM Target 使用 `swiftSettings: [.enableExperimentalFeature("SymbolLinkageMarkers")]`。SwiftPM 从源码构建宏，无需下载预编译产物。

## CocoaPods

```ruby
pod 'LaunchTaskKit', '0.0.2'
```

先把本仓库的 `Scripts/launch_task_kit_swift_flags.rb` 和配套的 `Scripts/consumer_macro_flags.rb` 一起复制到应用工程。Pod Target 通过直接或传递依赖使用 `@LaunchTaskEntry` 时，需要在应用 Podfile 中加载编译器插件注入脚本：

```ruby
require_relative 'Scripts/launch_task_kit_swift_flags'

post_install do |installer|
  inject_launch_task_kit_swift_flags_if_needed(installer)
end
```

## 同步任务

同步任务在 MainActor 上执行：

```swift
import LaunchTaskKit

@LaunchTaskEntry(phase: .main, priority: 100)
final class NetworkConfigurationTask: LaunchTask {
    override class func launch() throws {
        NetworkManager.configure()
    }
}
```

## 异步任务

异步任务不会阻塞调用方，Launcher 会跟踪任务完成状态和错误：

```swift
@LaunchTaskEntry(phase: .main)
final class AccountRefreshTask: AsyncLaunchTask {
    override class func launch() async throws {
        try await AccountService.refresh()
    }
}
```

## Launcher

宿主应用创建并持有 Launcher：

```swift
let launcher = Launcher { event in
    switch event {
    case .taskFinished(let result):
        print("\(result.task.identifier): \(result.duration)")
    default:
        break
    }
}

launcher.start()
```

`start()` 会发现所有通过宏注册的任务，并触发 `.head`、`.main` 和 `.idle`。后续阶段由宿主生命周期回调触发：

```swift
launcher.trigger(.sub)
launcher.trigger(.firstScreenIdle)
```

每个阶段在 `reset()` 前最多触发一次。空闲阶段会在主 RunLoop 每次空闲时执行一个任务。

## 启动来源

进程启动回调可能早于 Scene 提供 URL、通知、快捷操作或 UserActivity 信息。任务可以先启动，再补充当前启动的来源，补充来源不会重新触发任务：

```swift
launcher.start()
launcher.updateSource(.url(url))
```

LaunchTaskKit 不接收 UIKit 的 launch options 字典。宿主负责把平台回调转换成可安全跨并发域的 `LaunchSource`。

## 执行模型

- `LaunchPhase` 只描述任务何时开始。
- `LaunchTask` 在 MainActor 上同步执行。
- `AsyncLaunchTask` 异步执行，并由 `Launcher` 跟踪完成状态。
- 优先级决定同阶段任务的启动顺序，不保证异步任务的完成顺序。
- 启动任务类型无状态且不可实例化。

## 宏产物与本地发布

SwiftPM 从源码构建宏。CocoaPods 通过 `prepare_command` 下载 `MacroArtifact.lock.json` 锁定的单个 macOS arm64 插件，不再通过 Git LFS 分发。仅支持 Apple Silicon 构建主机。

```sh
bundle install
./build.sh
./verify
```

构建采用 release、-Osize 和完整符号移除。指纹覆盖宏源码、Package manifest/依赖锁定、构建脚本和选项及工具链；运行时代码、测试和文档变化复用原产物。下载器先验证本地文件和共享 SHA256 缓存 `~/Library/Caches/SwiftMacroArtifacts/v1`，最后下载。可通过 `SWIFT_MACRO_CACHE_DIR` 覆盖；校验或下载失败时终止安装。

`./verify` 不发布内容，每次都运行宏单元测试、调度库测试、缓存测试和真实 SwiftPM/CocoaPods iOS 集成测试，覆盖直接/传递依赖、自动任务发现和单次执行、带空格的 `:path` 目录及重复注入。日志、xcresult 和本次报告保存在 `.distribution/`。

同步配置和 podspec 版本，构建并提交锁文件后运行 `./release 0.0.2`。它要求干净工作区，依次完整验证、推送源码、发布或复用不可变 Macro Release、验证真实下载、推送库 tag、空缓存重跑远程双路径集成，最后创建库 Release。没有跳过测试的选项。`--publish-pod` 显式追加 CocoaPods trunk 发布。失败立即停止，保留证据，不覆盖已有 tag/附件；只可重试同一提交与附件。

`:path` 接入不会运行 `prepare_command`，需显式执行 `ruby Scripts/macro_artifact.rb`；修改宏实现后运行 `./build.sh`。不要提交本地产物或验证输出。

## License

LaunchTaskKit 使用 MIT License。
