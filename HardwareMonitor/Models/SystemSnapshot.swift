import Foundation

/// 单次采样的系统快照
struct SystemSnapshot {
    // CPU
    var cpuUsage: Double = 0                // 0~1
    var cpuTempC: Double? = nil             // SMC 可用时
    var gpuTempC: Double? = nil
    var cpuTempLabel: String? = nil         // SMC key 名（如 Tp01）

    // 温度列表（SMC 全量扫描结果，key → 值）
    var smcTemperatures: [(key: String, value: Double)] = []
    var smcFans: [(key: String, rpm: Double)] = []
    var smcAvailable: Bool = false

    // HID 传感器温度（Apple Silicon 温度集线器，非 root 可读）
    var hidTemperatures: [(key: String, value: Double)] = []
    var tempSource: String? = nil          // "SMC" / "HID"

    // 内存
    var memTotal: UInt64 = 0
    var memUsed: UInt64 = 0
    var memPercent: Double = 0              // 0~1
    var memActive: UInt64 = 0               // 应用内存
    var memWired: UInt64 = 0                // 联动内存
    var memCompressed: UInt64 = 0           // 压缩内存
    var memFree: UInt64 = 0                 // 空闲（含 inactive）

    // 磁盘
    var diskTotal: UInt64 = 0
    var diskFree: UInt64 = 0
    var diskPercent: Double = 0

    // 亮度 0~1
    var brightness: Double? = nil

    // 电池
    var batteryPercent: Int? = nil          // 0~100
    var batteryHealth: Int? = nil           // 0~100
    var batteryCycles: Int? = nil
    var batteryCharging: Bool = false
    var batteryTempC: Double? = nil         // 电池温度（0.1°C 来源，转 °C）
    var batteryPresent: Bool = false

    // 网络（字节/秒）
    var netDown: Double = 0
    var netUp: Double = 0

    // 进程排行
    var topProcesses: [ProcessItem] = []

    // 汇总指标（给 UI / 告警用）
    var batteryPercentValue: Double? { batteryPercent.map { Double($0) } }
    var diskPercentValue: Double { diskPercent }
    var memPercentValue: Double { memPercent }
    var cpuPercentValue: Double { cpuUsage * 100 }

    /// 当前可展示的"芯片参考温度"：优先 CPU 温度，否则电池温度（标注参考）
    var referenceTempC: Double? { cpuTempC ?? batteryTempC }
    var referenceTempIsBattery: Bool { cpuTempC == nil && batteryTempC != nil }
}

/// 进程资源占用条目
struct ProcessItem: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    var cpuPercent: Double      // 0~100
    var memoryBytes: UInt64

    var id: pid_t { pid }
    var memoryMB: Double { Double(memoryBytes) / 1024 / 1024 }
}

/// 趋势图历史点
struct HistoryPoint: Identifiable {
    let id = UUID()
    let time: Date
    var cpuPercent: Double
    var memPercent: Double
    var cpuTemp: Double?
    var gpuTemp: Double?
    var netDownMBs: Double
    var netUpMBs: Double
}

/// 剪贴板历史条目
struct ClipboardItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var pinned: Bool = false
    let date = Date()
}
