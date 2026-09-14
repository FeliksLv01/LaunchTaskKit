import Foundation
import MachO

private typealias LaunchTaskTypeGetter = @convention(c) () -> UnsafeRawPointer

@MainActor
enum LaunchTaskSectionReader {
    static func taskDescriptors() -> [LaunchTaskDescriptor] {
        var seenTypes: Set<ObjectIdentifier> = []
        var descriptors: [LaunchTaskDescriptor] = []

        for imageIndex in 0..<_dyld_image_count() {
            guard let rawHeader = _dyld_get_image_header(imageIndex) else {
                continue
            }

            let header = UnsafePointer<mach_header_64>(OpaquePointer(rawHeader))
            for type in taskTypes(header: header) {
                let identifier = ObjectIdentifier(type)
                guard seenTypes.insert(identifier).inserted else {
                    continue
                }

                if let synchronousType = type as? LaunchTask.Type {
                    descriptors.append(LaunchTaskDescriptor(synchronousType))
                } else if let asynchronousType = type as? AsyncLaunchTask.Type {
                    descriptors.append(LaunchTaskDescriptor(asynchronousType))
                }
            }
        }

        return descriptors
    }

    private static func taskTypes(header: UnsafePointer<mach_header_64>) -> [Any.Type] {
        var size: UInt = 0
        guard let sectionData = getsectiondata(header, "__DATA_CONST", "__launch_task", &size),
              size > 0 else {
            return []
        }

        let itemSize = MemoryLayout<LaunchTaskTypeGetter>.stride
        let count = Int(size) / itemSize
        let rawPointer = UnsafeRawPointer(sectionData)

        return (0..<count).map { index in
            let getter = rawPointer.load(
                fromByteOffset: index * itemSize,
                as: LaunchTaskTypeGetter.self
            )
            return unsafeBitCast(getter(), to: Any.Type.self)
        }
    }
}
