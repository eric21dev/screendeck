import Foundation
import IOKit.ps
import Darwin

struct StatsSnapshot {
    var cpu: Double = 0
    var cpuHistory: [Double] = Array(repeating: 0, count: 40)
    var memUsed: Double = 0           // 0...1
    var memUsedGB: Double = 0
    var memTotalGB: Double = 0
    var diskUsed: Double = 0          // 0...1
    var diskFreeGB: Double = 0
    var diskTotalGB: Double = 0
    var netDown: Double = 0           // bytes/s
    var netUp: Double = 0
    var netDownHistory: [Double] = Array(repeating: 0, count: 40)
    var netUpHistory: [Double] = Array(repeating: 0, count: 40)
    var batteryPercent: Int? = nil
    var batteryCharging = false
    var onACPower = true
    var uptime: TimeInterval = 0

    /// Datos de ejemplo para vistas previas y capturas.
    static let demo: StatsSnapshot = {
        var s = StatsSnapshot()
        s.cpu = 0.34
        s.cpuHistory = (0..<40).map { (i: Int) -> Double in
            let x = Double(i)
            let wave: Double = 0.2 * sin(x / 4.0)
            let jitter: Double = Double(i % 5) * 0.02
            return 0.25 + wave + jitter
        }
        s.memUsed = 0.62; s.memUsedGB = 14.9; s.memTotalGB = 24
        s.diskUsed = 0.48; s.diskFreeGB = 518; s.diskTotalGB = 994
        s.netDown = 4_800_000; s.netUp = 380_000
        s.netDownHistory = (0..<40).map { (i: Int) -> Double in 3_000_000.0 + 2_000_000.0 * sin(Double(i) / 3.0) }
        s.netUpHistory = (0..<40).map { (i: Int) -> Double in 200_000.0 + 150_000.0 * sin(Double(i) / 5.0 + 1.0) }
        s.batteryPercent = 76; s.batteryCharging = true; s.onACPower = true
        s.uptime = 3 * 86400 + 5 * 3600
        return s
    }()
}

/// Muestrea el sistema una vez por segundo.
final class SystemStats: ObservableObject {
    static let shared = SystemStats()
    @Published private(set) var snapshot = StatsSnapshot()

    private var timer: Timer?
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var lastNet: (down: UInt64, up: UInt64, at: Date)?

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func sample() {
        var s = snapshot
        // CPU
        if let t = cpuTicks() {
            if let l = lastTicks, t.total > l.total {
                s.cpu = min(1, Double(t.busy - l.busy) / Double(t.total - l.total))
            }
            lastTicks = t
        }
        s.cpuHistory = Array((s.cpuHistory + [s.cpu]).suffix(40))
        // Memoria
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        if let used = memoryUsedBytes() {
            s.memUsed = min(1, used / total)
            s.memUsedGB = used / 1_073_741_824
        }
        s.memTotalGB = total / 1_073_741_824
        // Disco
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
           let tot = v.volumeTotalCapacity, let free = v.volumeAvailableCapacityForImportantUsage, tot > 0 {
            s.diskTotalGB = Double(tot) / 1e9
            s.diskFreeGB = Double(free) / 1e9
            s.diskUsed = max(0, min(1, 1 - Double(free) / Double(tot)))
        }
        // Red
        if let n = networkBytes() {
            if let l = lastNet {
                let dt = max(0.2, n.at.timeIntervalSince(l.at))
                s.netDown = Double(wrapDelta(n.down, l.down)) / dt
                s.netUp = Double(wrapDelta(n.up, l.up)) / dt
            }
            lastNet = n
        }
        s.netDownHistory = Array((s.netDownHistory + [s.netDown]).suffix(40))
        s.netUpHistory = Array((s.netUpHistory + [s.netUp]).suffix(40))
        // Batería
        let b = batteryInfo()
        s.batteryPercent = b.percent; s.batteryCharging = b.charging; s.onACPower = b.ac
        s.uptime = ProcessInfo.processInfo.systemUptime
        snapshot = s
    }

    private func wrapDelta(_ new: UInt64, _ old: UInt64) -> UInt64 {
        new >= old ? new - old : (new + 0x1_0000_0000) - old   // los contadores son de 32 bits
    }

    private func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)) }
        var busy: UInt64 = 0, total: UInt64 = 0
        for i in 0..<Int(cpuCount) {
            let o = i * Int(CPU_STATE_MAX)
            let user = UInt64(info[o + Int(CPU_STATE_USER)]), sys = UInt64(info[o + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(info[o + Int(CPU_STATE_NICE)]), idle = UInt64(info[o + Int(CPU_STATE_IDLE)])
            busy += user + sys + nice
            total += user + sys + nice + idle
        }
        return (busy, total)
    }

    private func memoryUsedBytes() -> Double? {
        var st = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &st) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return nil }
        let page = Double(vm_kernel_page_size)
        return (Double(st.active_count) + Double(st.wire_count) + Double(st.compressor_page_count)) * page
    }

    private func networkBytes() -> (down: UInt64, up: UInt64, at: Date)? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
        defer { freeifaddrs(addrs) }
        var down: UInt64 = 0, up: UInt64 = 0
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = p {
            let name = String(cString: ifa.pointee.ifa_name)
            if let a = ifa.pointee.ifa_addr, a.pointee.sa_family == UInt8(AF_LINK), name.hasPrefix("en"),
               let data = ifa.pointee.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                down += UInt64(d.ifi_ibytes); up += UInt64(d.ifi_obytes)
            }
            p = ifa.pointee.ifa_next
        }
        return (down, up, Date())
    }

    private func batteryInfo() -> (percent: Int?, charging: Bool, ac: Bool) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return (nil, false, true) }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  let cap = d[kIOPSCurrentCapacityKey] as? Int else { continue }
            let charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
            let ac = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return (cap, charging, ac)
        }
        return (nil, false, true)
    }
}
