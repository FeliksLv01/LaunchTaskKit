# LaunchTaskKit

LaunchTaskKit is a lightweight Swift launch-task scheduler with macro-based automatic registration. It supports synchronous main-actor tasks, tracked asynchronous tasks, lifecycle phases, priorities, run-loop idle scheduling, and launch-source enrichment.

## Requirements

- iOS 15.0+
- macOS 12.0+
- Swift 6.0+

## Swift Package Manager

Add the package dependency and link the `LaunchTaskKit` product to your target:

```swift
dependencies: [
    .package(
        url: "https://github.com/FeliksLv01/LaunchTaskKit.git",
        from: "0.0.2"
    )
]
```

Macro consumers must enable `SymbolLinkageMarkers` in their Swift target (Xcode Other Swift Flags: `-enable-experimental-feature SymbolLinkageMarkers`; SwiftPM target `swiftSettings: [.enableExperimentalFeature("SymbolLinkageMarkers")]`). SwiftPM builds the macro from source without prebuilt downloads.


## Synchronous tasks

Synchronous tasks execute on the main actor:

```swift
import LaunchTaskKit

@LaunchTaskEntry(phase: .main, priority: 100)
final class NetworkConfigurationTask: LaunchTask {
    override class func launch() throws {
        NetworkManager.configure()
    }
}
```

## Asynchronous tasks

Asynchronous tasks are started without blocking the caller, while the launcher tracks their completion and errors:

```swift
@LaunchTaskEntry(phase: .main)
final class AccountRefreshTask: AsyncLaunchTask {
    override class func launch() async throws {
        try await AccountService.refresh()
    }
}
```

## Launcher

Create and retain a launcher in the host application:

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

`start()` discovers all macro-registered tasks, then triggers `.head`, `.main`, and `.idle`. Host lifecycle callbacks can trigger later phases:

```swift
launcher.trigger(.sub)
launcher.trigger(.firstScreenIdle)
```

Each phase triggers once until `reset()` is called. Idle phases execute one task per main-run-loop idle turn.

## Launch source

The initial process-launch callback may run before a scene provides URL, notification, shortcut, or user-activity information. Start tasks immediately, then enrich the current launch without retriggering phases:

```swift
launcher.start()
launcher.updateSource(.url(url))
```

LaunchTaskKit intentionally does not accept UIKit launch-option dictionaries. The host translates platform callbacks into the Sendable `LaunchSource` model.

## Execution model

- `LaunchPhase` describes when work starts.
- `LaunchTask` executes synchronously on the main actor.
- `AsyncLaunchTask` executes asynchronously and is tracked by `Launcher`.
- Priority determines start order within a phase, not asynchronous completion order.
- Launch task types are stateless and cannot be instantiated.


## License

LaunchTaskKit is available under the MIT license.

## Tests and releases

This is a standard SwiftPM package: `Package.swift`, `Sources/` and `Tests/`. SwiftPM is the only supported integration, and macros compile from source. Historical versions remain unchanged.

```sh
bash Scripts/test-macros.sh
bash Scripts/test-ios.sh
```

GitHub Actions runs host macro tests and iOS package tests on pull requests, main updates and version tags. Runtime tests include real macro expansion and automatic registration/database assertions. `xcodebuild` uses pipefail and xcbeautify; logs and xcresults are uploaded even on failure. New numeric version tags create a GitHub Release only after all CI jobs pass. Local release orchestration, CocoaPods and precompiled macro distribution have been removed.
