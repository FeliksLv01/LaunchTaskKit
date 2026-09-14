import LaunchTaskKitMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class LaunchTaskEntryMacroTests: XCTestCase {
    private let testMacros: [String: Macro.Type] = [
        "LaunchTaskEntry": LaunchTaskEntryMacro.self,
    ]

    func testEntryGeneratesMetadataAndSectionGetter() {
        assertMacroExpansion(
            """
            @LaunchTaskEntry(phase: .main, priority: 100)
            final class NetworkTask: LaunchTask {
            }
            """,
            expandedSource: """
            final class NetworkTask: LaunchTask {

                override class var identifier: String {
                    String(reflecting: self)
                }

                override class var phase: LaunchPhase {
                    .main
                }

                override class var priority: Int {
                    100
                }

                @section("__DATA_CONST,__launch_task")
                @used
                private static let _launchTaskEntry: @convention(c) () -> UnsafeRawPointer = {
                    unsafeBitCast(NetworkTask.self, to: UnsafeRawPointer.self)
                }
            }
            """,
            macros: testMacros
        )
    }

    func testEntryRejectsNonFinalClass() {
        assertMacroExpansion(
            """
            @LaunchTaskEntry(phase: .main)
            class NetworkTask: LaunchTask {
            }
            """,
            expandedSource: """
            class NetworkTask: LaunchTask {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@LaunchTaskEntry requires a final class.",
                    line: 1,
                    column: 1
                ),
            ],
            macros: testMacros
        )
    }

    func testEntryRejectsUnsupportedBaseClass() {
        assertMacroExpansion(
            """
            @LaunchTaskEntry(phase: .main)
            final class NetworkTask {
            }
            """,
            expandedSource: """
            final class NetworkTask {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@LaunchTaskEntry requires exactly one LaunchTask or AsyncLaunchTask base class.",
                    line: 1,
                    column: 1
                ),
            ],
            macros: testMacros
        )
    }
}
