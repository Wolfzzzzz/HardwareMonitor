import Foundation

/// 采样调度中心：后台队列按配置间隔采集全部传感器，合成 SystemSnapshot 后回主线程
final class SensorHub {
    private let smc = SMCReader()
    private let hid = HIDSensorReader()
    private let cpu = CPUSensor()
    private let net = NetworkSensor()
    private let proc = ProcessSensor()

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "cn.zzn.hwmon.sensor", qos: .utility)
    private var lastSampleTime: TimeInterval = 0

    /// 每次采样完成的回调（主线程）
    var onSnapshot: ((SystemSnapshot, TimeInterval) -> Void)?

    var smcAvailable: Bool { smc.isAvailable }
    var hidAvailable: Bool { hid.isAvailable }

    func start(interval: TimeInterval) {
        stop()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.2, repeating: interval, leeway: .milliseconds(100))
        t.setEventHandler { [weak self] in self?.sampleOnce() }
        timer = t
        t.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// 立即采样一次（用于启动时快速出数据）
    func sampleNow() {
        queue.async { [weak self] in self?.sampleOnce() }
    }

    private func sampleOnce() {
        let now = Date().timeIntervalSinceReferenceDate
        let elapsed = lastSampleTime > 0 ? now - lastSampleTime : 1.0
        lastSampleTime = now

        var snap = SystemSnapshot()

        // CPU
        snap.cpuUsage = cpu.sample()

        // 内存
        let mem = MemorySensor.sample()
        snap.memTotal = mem.total
        snap.memUsed = mem.used
        snap.memPercent = mem.percent
        snap.memActive = mem.active
        snap.memWired = mem.wired
        snap.memCompressed = mem.compressed
        snap.memFree = mem.free

        // 磁盘
        if let disk = DiskSensor.sample() {
            snap.diskTotal = disk.total
            snap.diskFree = disk.free
            snap.diskPercent = disk.percent
        }

        // 电池
        let bat = BatterySensor.sample()
        snap.batteryPercent = bat.percent
        snap.batteryHealth = bat.health
        snap.batteryCycles = bat.cycles
        snap.batteryCharging = bat.charging
        snap.batteryPresent = bat.present
        snap.batteryTempC = bat.tempC

        // 亮度
        snap.brightness = BrightnessSensor.sample()

        // 网络（需要两次采样差值）
        let netNow = net.sample(elapsed: elapsed)
        snap.netDown = netNow.down
        snap.netUp = netNow.up

        // 进程排行（低频：每 6 次采样一次，约 6s；全量扫描开销最大，6s 足够 TOP 排行）
        tick += 1
        if tick % 6 == 1 {
            cachedProcesses = proc.sample(elapsed: elapsed, top: 10)
        }
        snap.topProcesses = cachedProcesses

        // 温度与风扇（低频：每 3 次采样一次，约 3s；温度变化慢，省 IPC 开销）
        if tick % 3 == 1 {
            // SMC 与 HID 同时采样，CPU 温度取两者更高值（对齐第三方工具读数）
            var hidTemps: [(key: String, value: Double)] = []
            var smcTemps: [(key: String, value: Double)] = []
            var candidates: [Double] = []
            var gpuCandidates: [Double] = []
            if smc.isAvailable {
                let r = smc.sample()
                smcTemps = r.temps
                cachedFans = r.fans
                if let t = r.cpuTemp { candidates.append(t) }
                if let t = r.gpuTemp { gpuCandidates.append(t) }
            }
            if hid.isAvailable {
                let h = hid.sample()
                hidTemps = h.temps
                if let t = h.cpuTemp { candidates.append(t) }
                if let t = h.gpuTemp { gpuCandidates.append(t) }
            }
            cachedTemps = smc.isAvailable ? smcTemps : hidTemps
            cachedCpuTemp = candidates.max()
            cachedGpuTemp = gpuCandidates.max()
            cachedSource = smc.isAvailable ? "SMC" : (hidTemps.isEmpty ? nil : "HID")
        }
        snap.smcAvailable = smc.isAvailable
        snap.smcTemperatures = smc.isAvailable ? cachedTemps : []
        snap.smcFans = cachedFans
        snap.cpuTempC = cachedCpuTemp
        snap.gpuTempC = cachedGpuTemp
        snap.hidTemperatures = smc.isAvailable ? [] : cachedTemps
        snap.tempSource = cachedSource

        DispatchQueue.main.async { [weak self] in
            self?.onSnapshot?(snap, elapsed)
        }
    }

    private var tick = 0
    private var cachedTemps: [(key: String, value: Double)] = []
    private var cachedFans: [(key: String, rpm: Double)] = []
    private var cachedCpuTemp: Double?
    private var cachedGpuTemp: Double?
    private var cachedSource: String?
    private var cachedProcesses: [ProcessItem] = []
}
