import CoreFoundation
import Foundation

@MainActor
final class RunLoopIdleScheduler {
    private var pendingTasks: [LaunchTaskDescriptor]
    private var observer: CFRunLoopObserver?
    private let execute: @MainActor (LaunchTaskDescriptor) -> Void

    init(
        tasks: [LaunchTaskDescriptor],
        execute: @escaping @MainActor (LaunchTaskDescriptor) -> Void
    ) {
        self.pendingTasks = tasks
        self.execute = execute
    }

    isolated deinit {
        if let observer {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
    }

    func start() {
        guard observer == nil, !pendingTasks.isEmpty else {
            return
        }

        var context = CFRunLoopObserverContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        observer = CFRunLoopObserverCreate(
            kCFAllocatorDefault,
            CFRunLoopActivity.beforeWaiting.rawValue,
            true,
            Int.max,
            { _, _, info in
                guard let info else {
                    return
                }
                let scheduler = Unmanaged<RunLoopIdleScheduler>.fromOpaque(info).takeUnretainedValue()
                MainActor.assumeIsolated {
                    scheduler.executeNext()
                }
            },
            &context
        )

        if let observer {
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
    }

    func stop() {
        guard let observer else {
            return
        }
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = nil
    }

    private func executeNext() {
        guard !pendingTasks.isEmpty else {
            stop()
            return
        }

        execute(pendingTasks.removeFirst())
        if pendingTasks.isEmpty {
            stop()
        }
    }
}
