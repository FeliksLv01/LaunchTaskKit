import SwiftSyntax
import SwiftSyntaxMacros

public struct LaunchTaskEntryMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let classDeclaration = declaration.as(ClassDeclSyntax.self) else {
            throw LaunchTaskEntryMacroError.requiresClass
        }
        guard classDeclaration.modifiers.contains(where: { $0.name.tokenKind == .keyword(.final) }) else {
            throw LaunchTaskEntryMacroError.requiresFinalClass
        }

        let baseClassNames = classDeclaration.inheritanceClause?.inheritedTypes.compactMap {
            inheritedTypeName($0.type)
        } ?? []
        let supportedBaseClasses = baseClassNames.filter {
            $0 == "LaunchTask" || $0 == "AsyncLaunchTask"
        }
        guard supportedBaseClasses.count == 1 else {
            throw LaunchTaskEntryMacroError.requiresLaunchTaskBaseClass
        }

        let arguments = try arguments(from: node)
        let className = classDeclaration.name.text

        return [
            """
            override class var identifier: String {
                String(reflecting: self)
            }
            """,
            """
            override class var phase: LaunchPhase {
                \(raw: arguments.phase)
            }
            """,
            """
            override class var priority: Int {
                \(raw: arguments.priority)
            }
            """,
            """
            @section("__DATA_CONST,__launch_task")
            @used
            private static let _launchTaskEntry: @convention(c) () -> UnsafeRawPointer = {
                unsafeBitCast(\(raw: className).self, to: UnsafeRawPointer.self)
            }
            """,
        ]
    }

    private static func inheritedTypeName(_ type: TypeSyntax) -> String? {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return member.name.text
        }
        return nil
    }

    private static func arguments(from node: AttributeSyntax) throws -> (
        phase: String,
        priority: String
    ) {
        guard case .argumentList(let arguments) = node.arguments,
              let phaseArgument = arguments.first(where: { $0.label?.text == "phase" }) else {
            throw LaunchTaskEntryMacroError.missingPhase
        }

        let priority = arguments.first(where: { $0.label?.text == "priority" })?
            .expression.trimmedDescription ?? "0"
        return (phaseArgument.expression.trimmedDescription, priority)
    }
}

enum LaunchTaskEntryMacroError: Error, CustomStringConvertible {
    case requiresClass
    case requiresFinalClass
    case requiresLaunchTaskBaseClass
    case missingPhase

    var description: String {
        switch self {
        case .requiresClass:
            return "@LaunchTaskEntry can only be attached to a class."
        case .requiresFinalClass:
            return "@LaunchTaskEntry requires a final class."
        case .requiresLaunchTaskBaseClass:
            return "@LaunchTaskEntry requires exactly one LaunchTask or AsyncLaunchTask base class."
        case .missingPhase:
            return "@LaunchTaskEntry requires a phase argument."
        }
    }
}
