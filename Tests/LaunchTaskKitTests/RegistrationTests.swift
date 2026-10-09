import XCTest
import LaunchTaskKit

@MainActor
private enum RegistrationProbeExecution {
    static var count = 0
}

@LaunchTaskEntry(phase: .sub, priority: 73)
public final class RegistrationProbe: LaunchTask {
    public override class func launch() {
        RegistrationProbeExecution.count += 1
    }
}

@MainActor
public func RegistrationProbeCheck() -> Bool {
    RegistrationProbeExecution.count = 0
    var registered = false
    let launcher = Launcher { event in
        if case .taskStarted(let info) = event, info.identifier == RegistrationProbe.identifier {
            registered = info.phase == .sub && info.priority == 73 && info.executionKind == .synchronous
        }
    }
    launcher.start()
    launcher.trigger(.sub)
    launcher.trigger(.sub)
    let passed = registered && RegistrationProbeExecution.count == 1
    launcher.reset()
    return passed
}

@MainActor
final class RegistrationTests: XCTestCase {
    func testMacroIsDiscoveredAtRuntime() { XCTAssertTrue(RegistrationProbeCheck()) }
}
