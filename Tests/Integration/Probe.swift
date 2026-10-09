import LaunchTaskKit

@MainActor
private enum PROBE_NAMEExecution {
    static var count = 0
}

@LaunchTaskEntry(phase: .sub, priority: 73)
public final class PROBE_NAME: LaunchTask {
    public override class func launch() {
        PROBE_NAMEExecution.count += 1
    }
}

@MainActor
public func PROBE_NAMECheck() -> Bool {
    PROBE_NAMEExecution.count = 0
    var registered = false
    let launcher = Launcher { event in
        if case .taskStarted(let info) = event, info.identifier == PROBE_NAME.identifier {
            registered = info.phase == .sub && info.priority == 73 && info.executionKind == .synchronous
        }
    }
    launcher.start()
    launcher.trigger(.sub)
    launcher.trigger(.sub)
    let passed = registered && PROBE_NAMEExecution.count == 1
    launcher.reset()
    return passed
}
