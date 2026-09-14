import Foundation

enum LaunchTaskBody {
    case synchronous(LaunchTask.Type)
    case asynchronous(AsyncLaunchTask.Type)
}

struct LaunchTaskDescriptor {
    let info: LaunchTaskInfo
    let body: LaunchTaskBody

    init(_ type: LaunchTask.Type) {
        self.info = LaunchTaskInfo(
            identifier: type.identifier,
            phase: type.phase,
            priority: type.priority,
            executionKind: .synchronous
        )
        self.body = .synchronous(type)
    }

    init(_ type: AsyncLaunchTask.Type) {
        self.info = LaunchTaskInfo(
            identifier: type.identifier,
            phase: type.phase,
            priority: type.priority,
            executionKind: .asynchronous
        )
        self.body = .asynchronous(type)
    }
}
