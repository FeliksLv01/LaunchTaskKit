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
3. Never commit `Prebuilt/`, macro executables, or macro LFS rules/endpoints. SwiftPM builds from source; CocoaPods downloads the immutable executable pinned in `MacroArtifact.lock.json`.
4. Keep `Scripts/launch_task_kit_swift_flags.rb` compatible with direct and transitive CocoaPods dependencies.

## Validation

Run `./verify` for macro unit tests, existing launcher tests, cache/distribution tests and actual SwiftPM/CocoaPods iOS consumer tests. Every xcodebuild pipeline must enable `pipefail`, keep logs, and use `xcbeautify`. Finish with `git diff --check`. Use `rtk` for shell tools and `bundle exec` for Ruby tools.

## Style

Do not add file-header comments to Swift files. Document every public API with DocC-compatible comments.

## Commits

Use English Conventional Commits, for example:

```text
feat(launcher): add asynchronous task execution
fix(macro): preserve task priority metadata
```

## Distribution and release gates

- `MacroDistribution.json` configures the library and build; its version must match the podspec. `MacroArtifact.lock.json` is checked in and pins the executable URL, input fingerprint, SHA256, architecture, minimum macOS and toolchain. Never use a mutable `latest` URL.
- Runtime/docs/test-only changes reuse the same artifact. Macro sources, package manifest/locked dependencies, build script/options or toolchain changes require a new fingerprint and artifact. Run `./build.sh` and commit its resulting lock before releasing. Do not hand-edit a checksum to bypass validation.
- `./verify` must run distribution/cache tests, host macro unit tests, iOS runtime tests and BOTH real SwiftPM/CocoaPods consumer tests. Download success, `pod lib lint`, or macro compilation alone is not integration validation. Never add a skip-tests release option.
- CocoaPods tests cover application, direct and transitive Pod macro usage and actual runtime discovery. SwiftPM uses a fresh Git candidate and package checkout; it must never run the CocoaPods artifact installer. Simulator availability is checked before testing.
- Artifact caching is keyed by binary SHA256 across library versions. Verify local/cache bytes, serialize writes, install atomically and chmod executable. Failed downloads/checksums fail closed. Default cache is `~/Library/Caches/SwiftMacroArtifacts/v1`; CI/local tests may override `SWIFT_MACRO_CACHE_DIR`.
- `:path` development Pods do not execute `prepare_command`: run `ruby Scripts/macro_artifact.rb` to install a pinned artifact, or `./build.sh` after editing the macro. No implicit source-build fallback.
- `./release X.Y.Z` requires a clean committed worktree and matching config/podspec/lock. It runs all gates, pushes the verified source commit, publishes/reuses an immutable macro asset, verifies its real download, pushes the library tag, re-tests BOTH remote integrations with empty caches, then creates the library Release. `--publish-pod` explicitly adds trunk publication. Merely implementing scripts or running `verify` must not publish anything.
- Existing remote tags/assets must match the source commit/SHA256 on retries. Never overwrite tags/assets or rewrite history. If remote integration fails after tagging, stop before the library Release/trunk; retain evidence and retry the same commit. Never reuse old verification reports as proof of a new run.
- `.distribution/` contains per-run logs, xcresult bundles and JSON reports (including failures); never commit it. All xcodebuild pipelines must use `pipefail`, tee a log and pass through xcbeautify.
- Keep the existing `inject_launch_task_kit_swift_flags_if_needed` entrypoint compatible. Its companion `consumer_macro_flags.rb` must be copied alongside it. Preserve inherited flags, quote plugin paths, support multiple Pods projects/development Pods and make injection idempotent.
- Default prebuilt support is macOS arm64 only. Keep SwiftSyntax's license in `ThirdPartyNotices/` and attach it to binary releases. Validate binary architecture, minimum macOS and linked library portability.
- CocoaPods/Xcodeproj versions are pinned by Gemfile.lock. Run commands with `rtk`; use `bundle exec` for Ruby distribution tools. Do not mutate generated fixtures or dependency checkouts to make tests pass.

- `SymbolLinkageMarkers` is required by LaunchTaskKit’s Mach-O registration and belongs in this library configuration, not the generic template. Integration probes must verify automatic section discovery, generated phase/priority metadata and once-only task execution through the public Launcher API. Keep existing synchronous/asynchronous scheduler tests.
- Release macro executables use `release`, `-Osize` and full symbol stripping. Changing the stripping/build script changes the artifact fingerprint; re-run all integration gates.
