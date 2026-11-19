import Foundation
import Darwin

enum CpuCollector {
    private static var lastTicks: (user: Int, system: Int, idle: Int, nice: Int)?

    /// Average CPU utilization (0...1) since the previous call.
    static func utilization() -> Double {
        var ncpus: natural_t = 0
        var out: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), HOST_CPU_LOAD_INFO, &ncpus, &out, &count) == KERN_SUCCESS,
              let out else { return 0 }
        defer { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: out)), vm_size_t(Int(count) * MemoryLayout<integer_t>.stride)) }
        var user = 0, system = 0, idle = 0, nice = 0
        for cpu in 0..<Int(ncpus) {
            let base = cpu * Int(CPU_STATE_MAX)
            user += Int(out[base + Int(CPU_STATE_USER)])
            system += Int(out[base + Int(CPU_STATE_SYSTEM)])
            idle += Int(out[base + Int(CPU_STATE_IDLE)])
            nice += Int(out[base + Int(CPU_STATE_NICE)])
        }
        let cur = (user, system, idle, nice)
        defer { lastTicks = cur }
        guard let last = lastTicks else { return 0 }
        let du = cur.0 - last.0, ds = cur.1 - last.1, di = cur.2 - last.2, dn = cur.3 - last.3
        let busy = Double(max(du + ds + dn, 0))
        let total = Double(max(du + ds + dn + di, 1))
        return min(max(busy / total, 0), 1)
    }
}
