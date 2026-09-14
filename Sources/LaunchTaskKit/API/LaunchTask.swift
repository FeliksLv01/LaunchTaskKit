import Foundation

/// A stateless launch task that executes synchronously on the main actor.
open class LaunchTask {
    /// Launch tasks are type-level entry points and cannot be instantiated.
    @available(*, unavailable, message: "LaunchTask cannot be instantiated")
    public init() {}

    /// A stable identifier for registration and observability.
    open class var identifier: String {
        String(reflecting: self)
    }

    /// The lifecycle phase that triggers the task.
    open class var phase: LaunchPhase {
        .main
    }

    /// The ordering priority within the phase. Higher values start first.
    open class var priority: Int {
        0
    }

    /// Performs the launch work on the main actor.
    @MainActor
    open class func launch() throws {}
}

/// A stateless launch task whose completion is tracked asynchronously.
open class AsyncLaunchTask {
    /// Async launch tasks are type-level entry points and cannot be instantiated.
    @available(*, unavailable, message: "AsyncLaunchTask cannot be instantiated")
    public init() {}

    /// A stable identifier for registration and observability.
    open class var identifier: String {
        String(reflecting: self)
    }

    /// The lifecycle phase that triggers the task.
    open class var phase: LaunchPhase {
        .main
    }

    /// The ordering priority within the phase. Higher values start first.
    open class var priority: Int {
        0
    }

    /// Performs the launch work asynchronously.
    open class func launch() async throws {}
}
