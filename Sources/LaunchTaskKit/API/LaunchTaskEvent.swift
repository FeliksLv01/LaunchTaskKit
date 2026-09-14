import Foundation

/// The execution model of a registered launch task.
public enum LaunchTaskExecutionKind: Equatable, Sendable {
    /// A main-actor synchronous task.
    case synchronous
    /// An asynchronously tracked task.
    case asynchronous
}

/// Stable metadata describing a registered launch task.
public struct LaunchTaskInfo: Sendable {
    /// The task identifier.
    public let identifier: String
    /// The phase that triggers the task.
    public let phase: LaunchPhase
    /// The ordering priority within the phase.
    public let priority: Int
    /// The task execution model.
    public let executionKind: LaunchTaskExecutionKind
}

/// The completion result of a launch task.
public struct LaunchTaskResult: Sendable {
    /// Metadata for the completed task.
    public let task: LaunchTaskInfo
    /// The elapsed task duration in seconds.
    public let duration: TimeInterval
    /// The task start offset from `Launcher.start()` in seconds.
    public let startOffset: TimeInterval
    /// The task end offset from `Launcher.start()` in seconds.
    public let endOffset: TimeInterval
    /// Whether the task completed without throwing an error.
    public let succeeded: Bool
    /// The dynamic error type when execution failed.
    public let errorType: String?
    /// The localized error description when execution failed.
    public let errorDescription: String?
}

/// An observable event emitted by a launcher.
public enum LaunchTaskEvent: Sendable {
    /// A task began execution.
    case taskStarted(LaunchTaskInfo)
    /// A task finished execution.
    case taskFinished(LaunchTaskResult)
    /// The host supplied or refined the launch source.
    case sourceUpdated(LaunchSource)
    /// A duplicate task identifier was ignored during registration.
    case duplicateTaskIgnored(String)
}
