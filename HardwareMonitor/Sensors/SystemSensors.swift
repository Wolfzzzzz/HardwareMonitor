import Foundation
import IOKit
import Darwin
import CoreGraphics

// MARK: - CPU 占用率（host_statistics 两次采样差值）
final class CPUSensor {
    private var prev: host_cpu_load_info?

    /// 返回 0~1 的占用率
    func sample() -> Double {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &load) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ip in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, ip, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return prevUsage ?? 0 }
        let user = UInt64(load.cpu_ticks.0), system = UInt64(load.cpu_ticks.1)
        let idle = UInt64(load.cpu_ticks.2), nice = UInt64(load.cpu_ticks.3)
        let total = user + system + idle + nice
        if let p = prev {
            let puser = UInt64(p.cpu_ticks.0), psys = UInt64(p.cpu_ticks.1)
            let pidle = UInt64(p.cpu_ticks.2), pnice = UInt64(p.cpu_ticks.3)
            let ptotal = puser + psys + pidle + pnice
            let dTotal = total > ptotal ? total - ptotal : 1
            let dIdle = idle > pidle ? idle - pidle : 0
            prev = load
            let v = 1.0 - Double(dIdle) / Double(dTotal)
            prevUsage = v
            return max(0, min(1, v))
        }
        prev = load
        return prevUsage ?? 0
    }
    private var prevUsage: Double?
}

// MARK: - 内存（host_statistics64）
enum MemorySensor {
    /// 返回 (总, 已用, 占用率, active, wired, compressed, free) 字节
    static func sample() -> (total: UInt64, used: UInt64, percent: Double, active: UInt64, wired: UInt64, compressed: UInt64, free: UInt64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ip in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, ip, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, 0, 0, 0, 0, 0, 0) }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let ps = UInt64(pageSize)
        let active = ps * UInt64(stats.active_count)
        let wired = ps * UInt64(stats.wire_count)
        let compressed = ps * UInt64(stats.compressor_page_count)
        let free = ps * UInt64(stats.free_count)
        let total = ps * UInt64(stats.active_count + stats.inactive_count + stats.wire_count + stats.free_count + stats.compressor_page_count)
        let used = active + wired + compressed
        return (total, used, total > 0 ? Double(used) / Double(total) : 0, active, wired, compressed, free)
    }
}

// MARK: - 磁盘
enum DiskSensor {
    static func sample() -> (total: UInt64, free: UInt64, percent: Double)? {
        let url = URL(fileURLWithPath: "/")
        do {
            let v = try url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
            if let t = v.volumeTotalCapacity, let a = v.volumeAvailableCapacityForImportantUsage, t > 0 {
                return (UInt64(t), UInt64(a), 1.0 - Double(a) / Double(t))
            }
        } catch {}
        return nil
    }
}

// MARK: - 电池（IORegistry AppleSmartBattery）
enum BatterySensor {
    static func sample() -> (percent: Int?, health: Int?, cycles: Int?, charging: Bool, present: Bool, tempC: Double?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (nil, nil, nil, false, false, nil) }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return (nil, nil, nil, false, false, nil)
        }

        let cur = dict["CurrentCapacity"] as? Int
        let max = dict["MaxCapacity"] as? Int
        let percent: Int? = (cur != nil && max != nil && max! > 0) ? Int(round(Double(cur!) / Double(max!) * 100)) : nil
        let cycles = dict["CycleCount"] as? Int
        let charging = (dict["IsCharging"] as? Int) == 1
        let present = (dict["BatteryInstalled"] as? Int) == 1

        var health: Int?
        var tempC: Double?
        if let bd = dict["BatteryData"] as? [String: Any] {
            if let full = bd["FullChargeCapacity"] as? Int, let design = bd["DesignCapacity"] as? Int, design > 0 {
                health = Int(round(Double(full) / Double(design) * 100))
            }
            if let t = bd["Temperature"] as? Int { tempC = Double(t) / 10.0 }
            if tempC == nil, let t = bd["VirtualTemperature"] as? Int { tempC = Double(t) / 10.0 }
        }
        return (percent, health, cycles, charging, present, tempC)
    }
}

// MARK: - 屏幕亮度（DisplayServices 私有 API，dlopen 动态解析）
enum BrightnessSensor {
    static func sample() -> Double? {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY) else { return nil }
        defer { dlclose(handle) }
        guard let f = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(f, to: Fn.self)
        var b: Float = 0
        guard fn(CGMainDisplayID(), &b) == 0, b > 0.001 else { return nil }
        return Double(b)
    }
}

// MARK: - 网络速率（getifaddrs 两次采样差值）
final class NetworkSensor {
    private var prev: (rx: UInt64, tx: UInt64)?
    private var lastCalc: (down: Double, up: Double) = (0, 0)

    /// 传入距上次采样的秒数，返回 (下行, 上行) 字节/秒
    func sample(elapsed: Double) -> (down: Double, up: Double) {
        var rx: UInt64 = 0, tx: UInt64 = 0
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else { return lastCalc }
        defer { freeifaddrs(ifaddrPtr) }
        var ptr = ifaddrPtr
        while let p = ptr {
            if let addr = p.pointee.ifa_addr,
               addr.pointee.sa_family == UInt8(AF_LINK),
               let data = p.pointee.ifa_data {
                let name = String(cString: p.pointee.ifa_name)
                if name.hasPrefix("en") {
                    let d = data.assumingMemoryBound(to: if_data.self).pointee
                    rx += UInt64(d.ifi_ibytes)
                    tx += UInt64(d.ifi_obytes)
                }
            }
            ptr = p.pointee.ifa_next
        }
        if let p = prev {
            let dt = max(elapsed, 0.3)
            let down = Double(rx >= p.rx ? rx - p.rx : 0) / dt
            let up = Double(tx >= p.tx ? tx - p.tx : 0) / dt
            lastCalc = (down, up)
        }
        prev = (rx, tx)
        return lastCalc
    }
}

// MARK: - 进程排行（proc_listallpids + proc_taskinfo，CPU 自校准 ticks/秒，按核心数归一化）
final class ProcessSensor {
    private var cpuCache: [pid_t: (user: Double, system: Double, time: TimeInterval)] = [:]
    private var lastSampleTime: TimeInterval = 0
    private let coreCount: Double = Double(max(1, ProcessInfo.processInfo.activeProcessorCount))
    /// 自校准：pti_total_user/system 是平台相关的 tick（实测 Apple M5 ≈ 10 ns/tick），用睡眠 0.5s 测增量
    private var ticksPerSecond: Double = 0

    private func readSelfTicks() -> (Double, Double) {
        var info = proc_taskinfo()
        let sz = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, &info, sz) == sz else { return (0, 0) }
        return (Double(info.pti_total_user), Double(info.pti_total_system))
    }

    private func calibrate() {
        let (u1, s1) = readSelfTicks()
        Thread.sleep(forTimeInterval: 0.5)
        let (u2, s2) = readSelfTicks()
        let delta = max(1, (u2 - u1) + (s2 - s1))
        ticksPerSecond = delta / 0.5
    }

    func sample(elapsed: Double, top: Int = 10) -> [ProcessItem] {
        if ticksPerSecond == 0 { calibrate() }

        var pids = [pid_t](repeating: 0, count: 4096)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }

        let now = Date().timeIntervalSinceReferenceDate
        let dt = lastSampleTime > 0 ? max(now - lastSampleTime, 0.3) : max(elapsed, 0.3)
        lastSampleTime = now
        // delta_ticks → 秒 → /dt → 占比 → *100 / coreCount → 0~100%
        let cpuFactor = 100.0 / (coreCount * ticksPerSecond * dt)

        var items: [ProcessItem] = []
        items.reserveCapacity(Int(count))
        var newCache: [pid_t: (Double, Double, TimeInterval)] = [:]
        let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)

        for i in 0..<Int(count) {
            let pid = pids[i]
            var info = proc_taskinfo()
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, taskSize) == taskSize else { continue }
            var nameBuf = [CChar](repeating: 0, count: 64)
            proc_name(pid, &nameBuf, 64)
            let rawName = String(cString: nameBuf)
            let name = rawName.isEmpty ? "\(pid)" : rawName

            let user = Double(info.pti_total_user)
            let system = Double(info.pti_total_system)
            newCache[pid] = (user, system, now)
            var cpuPct: Double = 0
            if let prev = cpuCache[pid] {
                let deltaTicks = max(0, (user - prev.0) + (system - prev.1))
                cpuPct = min(100.0, deltaTicks * cpuFactor)
            }
            items.append(ProcessItem(pid: pid, name: name, cpuPercent: cpuPct, memoryBytes: info.pti_resident_size))
        }
        cpuCache = newCache

        // 过滤系统噪音（内存 > 30MB 或 CPU > 1% 才上榜）
        let meaningful = items.filter { $0.memoryBytes > 30 * 1024 * 1024 || $0.cpuPercent > 1 }
        let byCPU = meaningful.sorted { $0.cpuPercent > $1.cpuPercent }
        if let first = byCPU.first, first.cpuPercent > 1 {
            return Array(byCPU.prefix(top))
        }
        return Array(meaningful.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(top))
    }
}
