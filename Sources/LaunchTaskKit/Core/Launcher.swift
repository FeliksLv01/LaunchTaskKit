import Foundation

/// Discovers, orders, and executes registered launch tasks.
@MainActor
public final class Launcher {
    /// A main-actor callback that receives task and launch-source events.
    public typealias EventHandler = @MainActor (LaunchTaskEvent) -> Void

    /// The latest launch source supplied by the host application.
    public private(set) var source: LaunchSource = .unknown

    private let registry = LaunchTaskRegistry()
    private let eventHandler: EventHandler?
    private var launchStartUptime: TimeInterval?
    private var registeredTasksLoaded = false
    private var scheduledPhases: Set<LaunchPhase> = []
    private var idleSchedulers: [LaunchPhase: RunLoopIdleScheduler] = [:]
    private var asyncTasks: [String: Task<Void, Never>] = [:]

    /// Creates an independent launcher.
    ///
    /// - Parameter eventHandler: An optional callback for execution and source events.
    public init(eventHandler: EventHandler? = nil) {
        self.eventHandler = eventHandler
    }

    init(
        descriptors: [LaunchTaskDescriptor],
        eventHandler: EventHandler? = nil
    ) {
        self.eventHandler = eventHandler
        self.registeredTasksLoaded = true
        for descriptor in descriptors {
            if !registry.register(descriptor) {
                eventHandler?(.duplicateTaskIgnored(descriptor.info.identifier))
            }
        }
    }

    /// Discovers registered tasks and begins the head, main, and idle phases.
    public func start() {
        guard launchStartUptime == nil else {
            return
        }

        launchStartUptime = ProcessInfo.processInfo.systemUptime
        loadRegisteredTasks()
        trigger(.head)
        trigger(.main)
        trigger(.idle)
    }

    /// Supplies or refines the launch source without restarting any task phase.
    public func updateSource(_ source: LaunchSource) {
        self.source = source
        eventHandler?(.sourceUpdated(source))
    }

    /// Triggers a phase once. Idle phases execute one task per main-run-loop idle turn.
    ///
    /// - Parameter phase: The lifecycle phase to trigger.
    public func trigger(_ phase: LaunchPhase) {
        guard launchStartUptime != nil, scheduledPhases.insert(phase).inserted else {
            return
        }

        let tasks = registry.tasks(for: phase)
        guard !tasks.isEmpty else {
            return
        }

        switch phase {
        case .idle, .firstScreenIdle:
            let scheduler = RunLoopIdleScheduler(tasks: tasks) { [weak self] descriptor in
                self?.execute(descriptor)
            }
            idleSchedulers[phase] = scheduler
            scheduler.start()
        case .head, .main, .sub:
            tasks.forEach(execute)
        }
    }

    /// Cancels tracked asynchronous work and returns the launcher to its initial state.
    public func reset() {
        idleSchedulers.values.forEach { $0.stop() }
        idleSchedulers.removeAll()
        asyncTasks.values.forEach { $0.cancel() }
        asyncTasks.removeAll()
        scheduledPhases.removeAll()
        registry.removeAll()
        registeredTasksLoaded = false
        launchStartUptime = nil
        source = .unknown
    }

    private func loadRegisteredTasks() {
        guard !registeredTasksLoaded else {
            return
        }
        registeredTasksLoaded = true

        for descriptor in LaunchTaskSectionReader.taskDescriptors() {
            if !registry.register(descriptor) {
                eventHandler?(.duplicateTaskIgnored(descriptor.info.identifier))
            }
        }
    }

    private func execute(_ descriptor: LaunchTaskDescriptor) {
        switch descriptor.body {
        case .synchronous(let taskType):
            executeSynchronously(taskType, info: descriptor.info)
        case .asynchronous(let taskType):
            executeAsynchronously(taskType, info: descriptor.info)
        }
    }

    private func executeSynchronously(_ taskType: LaunchTask.Type, info: LaunchTaskInfo) {
        let startUptime = ProcessInfo.processInfo.systemUptime
        eventHandler?(.taskStarted(info))

        do {
            try taskType.launch()
            finish(info: info, startUptime: startUptime)
        } catch {
            finish(info: info, startUptime: startUptime, error: error)
        }
    }

    private func executeAsynchronously(_ taskType: AsyncLaunchTask.Type, info: LaunchTaskInfo) {
        let launchStartUptime = launchStartUptime ?? ProcessInfo.processInfo.systemUptime
        eventHandler?(.taskStarted(info))

        let task = Task.detached { [weak self] in
            let startUptime = ProcessInfo.processInfo.systemUptime
            let failure: (String, String)?
            do {
                try await taskType.launch()
                failure = nil
            } catch {
                failure = (
                    String(reflecting: type(of: error)),
                    error.localizedDescription
                )
            }
            let endUptime = ProcessInfo.processInfo.systemUptime

            await self?.finishAsynchronously(
                info: info,
                launchStartUptime: launchStartUptime,
                startUptime: startUptime,
                endUptime: endUptime,
                failure: failure
            )
        }
        asyncTasks[info.identifier] = task
    }

    private func finish(
        info: LaunchTaskInfo,
        startUptime: TimeInterval,
        error: Error? = nil
    ) {
        let endUptime = ProcessInfo.processInfo.systemUptime
        let launchStartUptime = launchStartUptime ?? startUptime
        eventHandler?(.taskFinished(LaunchTaskResult(
            task: info,
            duration: max(0, endUptime - startUptime),
            startOffset: max(0, startUptime - launchStartUptime),
            endOffset: max(0, endUptime - launchStartUptime),
            succeeded: error == nil,
            errorType: error.map { String(reflecting: type(of: $0)) },
            errorDescription: error?.localizedDescription
        )))
    }

    private func finishAsynchronously(
        info: LaunchTaskInfo,
        launchStartUptime: TimeInterval,
        startUptime: TimeInterval,
        endUptime: TimeInterval,
        failure: (String, String)?
    ) {
        asyncTasks[info.identifier] = nil
        eventHandler?(.taskFinished(LaunchTaskResult(
            task: info,
            duration: max(0, endUptime - startUptime),
            startOffset: max(0, startUptime - launchStartUptime),
            endOffset: max(0, endUptime - launchStartUptime),
            succeeded: failure == nil,
            errorType: failure?.0,
            errorDescription: failure?.1
        )))
    }
}
