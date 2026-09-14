/// Registers a `LaunchTask` or `AsyncLaunchTask` subclass for automatic discovery.
///
/// - Parameters:
///   - phase: The lifecycle phase that triggers the task.
///   - priority: The ordering priority within the phase. Higher values start first.
@attached(
    member,
    names: named(identifier), named(phase), named(priority), named(_launchTaskEntry)
)
public macro LaunchTaskEntry(
    phase: LaunchPhase,
    priority: Int = 0
) = #externalMacro(module: "LaunchTaskKitMacros", type: "LaunchTaskEntryMacro")
