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
        from: "0.0.1"
    )
]
```

## CocoaPods

```ruby
pod 'LaunchTaskKit'
```

Pod Target 通过直接或传递依赖使用 `@LaunchTaskEntry` 时，需要在应用 Podfile 中加载编译器插件注入脚本：

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

## License

LaunchTaskKit 使用 MIT License。
