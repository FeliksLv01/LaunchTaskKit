import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct LaunchTaskKitPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        LaunchTaskEntryMacro.self,
    ]
}
