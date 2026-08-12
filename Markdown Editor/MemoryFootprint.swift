import Foundation
import MachO

/// Samples memory footprint via mach task_info.
///
/// // REQ-126.
nonisolated enum MemoryFootprint {
    struct Sample: Sendable, Equatable {
        let bytes: UInt64
        let peakBytes: UInt64
    }

    static func sample() -> Sample {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return Sample(
                bytes: UInt64(info.phys_footprint),
                peakBytes: UInt64(info.ledger_phys_footprint_peak)
            )
        }
        return Sample(bytes: 0, peakBytes: 0)
    }
}
