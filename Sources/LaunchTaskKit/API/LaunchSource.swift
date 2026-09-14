import Foundation

/// A normalized source associated with an application launch.
public enum LaunchSource: Hashable, Sendable {
    /// The launch source has not been determined yet.
    case unknown
    /// A regular launch without an external entry.
    case normal
    /// A custom URL opened the application.
    case url(URL)
    /// A universal link opened the application.
    case universalLink(URL)
    /// A remote notification opened the application.
    case remoteNotification
    /// A Home Screen quick action opened the application.
    case shortcut(String)
    /// An `NSUserActivity` opened the application.
    case userActivity(String)
    /// A host-defined launch source.
    case custom(String)
}
