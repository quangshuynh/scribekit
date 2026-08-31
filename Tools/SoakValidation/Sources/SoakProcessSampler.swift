//
//  SoakProcessSampler.swift
//  SoakValidation
//

import Darwin
import Foundation

/// Reads the running process's own resource counters.
///
/// Sampling from inside the process keeps the instrument cheap enough that a
/// reading costs less than a millisecond, so a soak's own measurements do not
/// show up in its measurements. Nothing here allocates during a reading beyond
/// the fixed-size structures the kernel fills in.
nonisolated enum SoakProcessSampler {

    /// Takes one reading.
    static func sample() -> SoakProcessSample {
        SoakProcessSample(
            footprintBytes: footprint(),
            cpuSeconds: cpuSeconds(),
            threadCount: threadCount(),
            thermalState: thermalState()
        )
    }

    /// Resident footprint, the figure Activity Monitor shows as Memory.
    private static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    /// User plus system CPU seconds charged to this process.
    private static func cpuSeconds() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }

    /// Live threads, counted by asking the kernel for the list and releasing it.
    private static func threadCount() -> Int {
        var threads: thread_act_array_t?
        var count = mach_msg_type_number_t(0)
        guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS,
              let threads else { return 0 }
        for index in 0..<Int(count) {
            mach_port_deallocate(mach_task_self_, threads[index])
        }
        vm_deallocate(
            mach_task_self_,
            vm_address_t(UInt(bitPattern: threads)),
            vm_size_t(Int(count) * MemoryLayout<thread_t>.stride)
        )
        return Int(count)
    }

    /// The system's thermal pressure as a word, for the report.
    private static func thermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}
