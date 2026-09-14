# LaunchTaskKit contribution guide

## Scope

LaunchTaskKit is a standalone Swift launch-task scheduler. Keep runtime code independent of application-specific dependency injection, logging, analytics, and UIKit launch-option payloads.

## Package integrations

1. Swift Package Manager and CocoaPods compile the same runtime sources under `Sources/LaunchTaskKit`.
2. Consumers import only `LaunchTaskKit`; macro implementations remain in `Sources/LaunchTaskKitMacros`.
3. Keep `Package.swift`, `LaunchTaskKit.podspec`, README files, prebuilt macro names, and release tags consistent.
4. Do not commit generated Xcode projects, workspaces, DerivedData, or SwiftPM build directories.

## Runtime behavior

1. `LaunchTask` and `AsyncLaunchTask` are stateless, non-instantiable class-based entry points.
2. `LaunchPhase` describes trigger timing only. Task base class determines synchronous or asynchronous execution.
3. Synchronous tasks execute on the main actor. Asynchronous tasks run as tracked detached tasks.
4. Each phase triggers at most once until `Launcher.reset()`.
5. Priority controls task start order within a phase, not asynchronous completion order.
6. Automatic discovery scans `__DATA_CONST,__launch_task` in all loaded Mach-O images.

## Macros

1. `@LaunchTaskEntry` requires a final class inheriting exactly one of `LaunchTask` or `AsyncLaunchTask`.
2. After changing macro implementation code, run `./build.sh`.
3. Keep `Prebuilt/LaunchTaskKitMacros` tracked through Git LFS.
4. Keep `Scripts/launch_task_kit_swift_flags.rb` compatible with direct and transitive CocoaPods dependencies.

## Validation

Run `swift test`, build the iOS scheme through `xcodebuild | xcbeautify`, run `pod lib lint LaunchTaskKit.podspec --allow-warnings`, and finish with `git diff --check`.

## Style

Do not add file-header comments to Swift files. Document every public API with DocC-compatible comments.

## Commits

Use English Conventional Commits, for example:

```text
feat(launcher): add asynchronous task execution
fix(macro): preserve task priority metadata
```
