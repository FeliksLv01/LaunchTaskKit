# LaunchTaskKit conventions

- Reply in Chinese. Verify personal Git author/committer identity before committing; use English Conventional Commits. New Swift files have no header comments.
- SwiftPM is the only supported integration. Applications import LaunchTaskKit; compiler plugins stay in Sources/LaunchTaskKitMacros and build from source. Never add CocoaPods, prebuilt macro artifacts, download/cache scripts or LFS rules.
- Keep Package.swift exposing only LaunchTaskKit; preserve existing platform and public API behavior. All scripts belong in Scripts/; versioning uses Git tags.
- Preserve macro-emitted Mach-O sections and runtime scanners together. SymbolLinkageMarkers remains this library's consumer configuration; never place it in generic defaults.

## Runtime behavior

1. `LaunchTask` and `AsyncLaunchTask` are stateless, non-instantiable class-based entry points.
2. `LaunchPhase` describes trigger timing only. Task base class determines synchronous or asynchronous execution.
3. Synchronous tasks execute on the main actor. Asynchronous tasks run as tracked detached tasks.
4. Each phase triggers at most once until `Launcher.reset()`.
5. Priority controls task start order within a phase, not asynchronous completion order.
6. Automatic discovery scans `__DATA_CONST,__launch_task` in all loaded Mach-O images.



## Tests and CI

- GitHub Actions is the verification and release gate. Preserve macro tests, all runtime tests and actual macro expansion/registration assertions. Host macro tests are separate because iOS cannot execute compiler-plugin host test bundles.
- bash Scripts/test-macros.sh runs host macro tests; bash Scripts/test-ios.sh runs the standard package runtime tests. No temporary consumer-project generator, Ruby dependencies or local release orchestrator.
- Every xcodebuild uses pipefail, tee logs and xcbeautify; check Simulator availability. CI uploads logs and xcresults on success or failure. Stale results never validate new sources.
- Numeric version tags create a library Release only after all CI jobs pass. Never add skip-test options or overwrite existing tags/Releases. Preserve historical versions.
- Use rtk for shell tools, finish with git diff --check, and keep English/Chinese docs synchronized. Never commit generated projects, caches or build output. Do not patch dependency checkouts/generated fixtures to hide failures.
