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

## CocoaPods

```ruby
pod 'LaunchTaskKit', '0.0.2'
```

Copy both `Scripts/launch_task_kit_swift_flags.rb` and `Scripts/consumer_macro_flags.rb` from this repository into your application. When Pod targets use `@LaunchTaskEntry` through a direct or transitive dependency, load the bundled compiler-plugin helper from the application Podfile:

```ruby
require_relative 'Scripts/launch_task_kit_swift_flags'

post_install do |installer|
  inject_launch_task_kit_swift_flags_if_needed(installer)
end
```

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

## Macro artifacts and local releases

SwiftPM builds macros from source and never downloads the prebuilt executable. CocoaPods runs `prepare_command` to install the single macOS arm64 plugin pinned by `MacroArtifact.lock.json`. Generated executables are ignored, not stored in Git or LFS.

```sh
bundle install
./build.sh
./verify
```

The build fingerprint covers macro sources, locked dependencies, build options and the toolchain. Runtime, documentation and test-only changes reuse the artifact. Prebuilts support Apple Silicon only; toolchain upgrades require verification.

The installer validates local bytes, then a shared SHA256-keyed cache at `~/Library/Caches/SwiftMacroArtifacts/v1`, then downloads. Library versions sharing one artifact reuse the cache. Override `SWIFT_MACRO_CACHE_DIR` when needed. Download and checksum failures stop installation.

`./verify` publishes nothing. It always runs macro unit tests, library tests, distribution/cache tests and real SwiftPM/CocoaPods iOS consumer integration tests. CocoaPods tests include direct/transitive macro consumers and automatic task discovery, generated metadata and once-only execution. Logs, xcresult bundles and JSON reports live under `.distribution/`.

Synchronize the version in the distribution config and podspec, build and commit the artifact lock, then run:

```sh
./release 0.0.2
# Also publish the podspec:
./release 0.0.2 --publish-pod
```

Release requires a clean committed worktree and never skips tests. It verifies a local candidate, pushes verified sources, publishes/reuses the immutable macro Release, verifies hosted downloads, pushes the library tag, repeats both remote integrations with fresh caches, then creates the library Release. Failures stop publication; tags/assets are never overwritten. A failed remote test can leave the tag in place; retry the same commit.

Development Pods using `:path` do not run `prepare_command`. Run `ruby Scripts/macro_artifact.rb` for a pinned artifact, or `./build.sh` after changing macro implementation. Never commit generated artifacts or verification output.

## License

LaunchTaskKit is available under the MIT license.
