import Foundation

@MainActor
final class LaunchTaskRegistry {
    private var descriptorsByIdentifier: [String: LaunchTaskDescriptor] = [:]
    private var descriptorsByPhase: [LaunchPhase: [LaunchTaskDescriptor]] = [:]

    func register(_ descriptor: LaunchTaskDescriptor) -> Bool {
        guard descriptorsByIdentifier[descriptor.info.identifier] == nil else {
            return false
        }

        descriptorsByIdentifier[descriptor.info.identifier] = descriptor
        descriptorsByPhase[descriptor.info.phase, default: []].append(descriptor)
        return true
    }

    func tasks(for phase: LaunchPhase) -> [LaunchTaskDescriptor] {
        (descriptorsByPhase[phase] ?? [])
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.info.priority == rhs.element.info.priority {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.info.priority > rhs.element.info.priority
            }
            .map(\.element)
    }

    func removeAll() {
        descriptorsByIdentifier.removeAll()
        descriptorsByPhase.removeAll()
    }
}
