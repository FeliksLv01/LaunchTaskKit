import XCTest
@testable import LaunchTaskKit

@MainActor
private enum TestExecutionLog {
    static var values: [String] = []
}

private final class LowPriorityTask: LaunchTask {
    override class var identifier: String { "low" }
    override class var phase: LaunchPhase { .main }
    override class var priority: Int { 0 }

    override class func launch() {
        TestExecutionLog.values.append(identifier)
    }
}

private final class HighPriorityTask: LaunchTask {
    override class var identifier: String { "high" }
    override class var phase: LaunchPhase { .main }
    override class var priority: Int { 100 }

    override class func launch() {
        TestExecutionLog.values.append(identifier)
    }
}

private actor AsyncExecutionLog {
    static let shared = AsyncExecutionLog()

    private(set) var count = 0

    func record() {
        count += 1
    }

    func reset() {
        count = 0
    }
}

private final class TrackedAsyncTask: AsyncLaunchTask {
    override class var identifier: String { "async" }
    override class var phase: LaunchPhase { .main }

    override class func launch() async {
        await AsyncExecutionLog.shared.record()
    }
}

@LaunchTaskEntry(phase: .sub, priority: 7)
private final class MacroDiscoveredTask: LaunchTask {
    override class func launch() {}
}

@MainActor
final class LauncherTests: XCTestCase {
    func testSynchronousTasksExecuteInPriorityOrderAndOnlyOnce() {
        TestExecutionLog.values = []
        let launcher = Launcher(descriptors: [
            LaunchTaskDescriptor(LowPriorityTask.self),
            LaunchTaskDescriptor(HighPriorityTask.self),
        ])

        launcher.start()
        launcher.trigger(.main)

        XCTAssertEqual(TestExecutionLog.values, ["high", "low"])
    }

    func testAsyncTaskEmitsTrackedCompletion() async {
        await AsyncExecutionLog.shared.reset()
        let expectation = expectation(description: "async task completed")
        let launcher = Launcher(
            descriptors: [LaunchTaskDescriptor(TrackedAsyncTask.self)],
            eventHandler: { event in
                guard case .taskFinished(let result) = event,
                      result.task.identifier == TrackedAsyncTask.identifier else {
                    return
                }
                XCTAssertTrue(result.succeeded)
                expectation.fulfill()
            }
        )

        launcher.start()
        await fulfillment(of: [expectation], timeout: 2)

        let executionCount = await AsyncExecutionLog.shared.count
        XCTAssertEqual(executionCount, 1)
    }

    func testSourceUpdateDoesNotRetriggerTasks() {
        TestExecutionLog.values = []
        var observedSource: LaunchSource?
        let launcher = Launcher(
            descriptors: [LaunchTaskDescriptor(HighPriorityTask.self)],
            eventHandler: { event in
                if case .sourceUpdated(let source) = event {
                    observedSource = source
                }
            }
        )

        launcher.start()
        launcher.updateSource(.shortcut("compose"))

        XCTAssertEqual(launcher.source, .shortcut("compose"))
        XCTAssertEqual(observedSource, .shortcut("compose"))
        XCTAssertEqual(TestExecutionLog.values, ["high"])
    }

    func testMacroTaskIsDiscoveredFromMachOSection() {
        let descriptor = LaunchTaskSectionReader.taskDescriptors().first {
            $0.info.identifier == MacroDiscoveredTask.identifier
        }

        XCTAssertEqual(descriptor?.info.phase, .sub)
        XCTAssertEqual(descriptor?.info.priority, 7)
        XCTAssertEqual(descriptor?.info.executionKind, .synchronous)
    }
}
