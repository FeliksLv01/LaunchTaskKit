import Foundation

/// A lifecycle point at which registered launch tasks begin execution.
public enum LaunchPhase: Int32, CaseIterable, Comparable, Sendable {
    /// The earliest application initialization work.
    case head = 0
    /// The primary application initialization work.
    case main = 1
    /// Work triggered when the application or scene becomes active.
    case sub = 2
    /// Work deferred until the main run loop becomes idle.
    case idle = 3
    /// Work deferred until the first screen has appeared and the run loop becomes idle.
    case firstScreenIdle = 4

    public static func < (lhs: LaunchPhase, rhs: LaunchPhase) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
