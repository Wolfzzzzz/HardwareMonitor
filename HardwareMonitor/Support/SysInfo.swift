import Foundation
import CoreWLAN

// MARK: - WiFi 详情

struct WiFiInfo {
    var ssid: String?
    var rssi: Int?
    var noise: Int?
    var channel: Int?
    var linkSpeedMbps: Double?
    var ip: String?
    var gateway: String?
    var dns: [String] = []
}

/// 采集 WiFi 信息（CoreWLAN + 系统命令）
func fetchWiFiInfo() -> WiFiInfo {
    var info = WiFiInfo()
    if let iface = CWWiFiClient.shared().interface() {
        info.ssid = iface.ssid()
        info.rssi = iface.rssiValue()
        info.noise = iface.noiseMeasurement()
        info.channel = iface.wlanChannel()?.channelNumber
        info.linkSpeedMbps = iface.transmitRate()
    }
    info.ip = localIPv4Address()
    info.gateway = defaultGateway()
    info.dns = dnsServers()
    return info
}

/// 本机 IPv4（getifaddrs，取 en0 非 loopback）
private func localIPv4Address() -> String? {
    var addr: String?
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
    for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
        let family = ptr.pointee.ifa_addr.pointee.sa_family
        if family == UInt8(AF_INET) {
            let name = String(cString: ptr.pointee.ifa_name)
            if name.hasPrefix("en") {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                            &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                let s = String(cString: host)
                if !s.hasPrefix("127.") { addr = s; break }
            }
        }
    }
    freeifaddrs(ifaddr)
    return addr
}

/// 默认网关（route -n get default）
private func defaultGateway() -> String? {
    guard let out = runCommandCapture("/sbin/route", ["-n", "get", "default"]) else { return nil }
    for line in out.components(separatedBy: "\n") {
        let parts = line.split(separator: ":")
        if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "gateway" {
            return parts[1].trimmingCharacters(in: .whitespaces)
        }
    }
    return nil
}

/// DNS 服务器（scutil --dns，取前 3 个）
private func dnsServers() -> [String] {
    guard let out = runCommandCapture("/usr/sbin/scutil", ["--dns"]) else { return [] }
    var result: [String] = []
    for line in out.components(separatedBy: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("nameserver[") {
            let v = t.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? ""
            if !v.isEmpty, !result.contains(v) { result.append(v) }
            if result.count >= 3 { break }
        }
    }
    return result
}

/// 执行命令并捕获输出
func runCommandCapture(_ path: String, _ args: [String]) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let outPipe = Pipe()
    let errPipe = Pipe()
    p.standardOutput = outPipe
    p.standardError = errPipe
    do {
        try p.run()
        p.waitUntilExit()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    } catch {
        return nil
    }
}

// MARK: - 磁盘 S.M.A.R.T 健康检测

struct DiskHealth {
    var device: String = "disk0"
    var smartStatus: String = "未知"   // Verified / Failing / Not supported
    var model: String = "?"
    var capacity: String = "?"
    var mediaType: String = "?"
    var powerOnHours: Int?            // smartctl 可选
    var reallocatedSectors: Int?      // smartctl 可选
    var rawTemp: Int?                 // smartctl 可选
    var isFailing: Bool { smartStatus.lowercased().contains("fail") }
}

/// 磁盘健康：优先 smartctl（通电时长/坏道），否则 diskutil（SMART 状态）
func fetchDiskHealth() -> DiskHealth {
    var h = DiskHealth()
    // 1. diskutil info disk0 基本信息 + SMART 状态
    if let out = runCommandCapture("/usr/sbin/diskutil", ["info", "disk0"]) {
        for line in out.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("SMART Status:") {
                h.smartStatus = t.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "未知"
            } else if t.hasPrefix("Device / Media Name:") {
                h.model = t.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "?"
            } else if t.hasPrefix("Disk Size:") {
                h.capacity = t.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "?"
            } else if t.hasPrefix("Media Type:") {
                h.mediaType = t.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "?"
            }
        }
    }
    // 2. smartctl 增强（如已安装 smartmontools）
    if let out = runCommandCapture("/opt/homebrew/sbin/smartctl", ["-H", "-A", "-d", "auto", "/dev/disk0"]) {
        for line in out.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("SMART overall-health") {
                let v = t.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? ""
                if v.lowercased().contains("passed") { h.smartStatus = "健康 (Verified)" }
                else if !v.isEmpty { h.smartStatus = v }
            }
            let cols = t.split(separator: " ").map(String.init)
            if cols.count >= 10 {
                if cols[0] == "Power_On_Hours" { h.powerOnHours = Int(cols[9]) }
                if cols[0] == "Reallocated_Sector_Ct" { h.reallocatedSectors = Int(cols[9]) }
                if cols[0] == "Temperature_Celsius" { h.rawTemp = Int(cols[9]) }
            }
        }
    }
    return h
}

// MARK: - 网络测速

struct SpeedTestResult {
    var pingMs: Double?
    var downloadMbps: Double?
    var uploadMbps: Double?
    var date = Date()
    var note: String?
}

/// 轻量测速引擎：延迟(ping) + 下载(Cloudflare) + 上传(Cloudflare)
/// 进度基于真实字节传输（下载 = 已接收/24MB，上传 = 已发送/12MB），避免模拟进度误导
final class SpeedTestEngine: NSObject, URLSessionDataDelegate {
    private let downURL = URL(string: "https://speed.cloudflare.com/__down?bytes=25165824")!  // 24MB
    private let upURL = URL(string: "https://speed.cloudflare.com/__up")!
    private let upBytes = 12_582_912  // 12MB

    // 进度状态（delegate 回调写入）
    private var receivedBytes: Int64 = 0
    private var expectedBytes: Int64 = 0
    private var downProgressCb: ((Double) -> Void)?
    private var upProgressCb: ((Double) -> Void)?

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        expectedBytes = response.expectedContentLength > 0 ? response.expectedContentLength : 25_165_824
        receivedBytes = 0
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedBytes += Int64(data.count)
        if expectedBytes > 0 {
            downProgressCb?(min(1.0, Double(receivedBytes) / Double(expectedBytes)))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if totalBytesExpectedToSend > 0 {
            upProgressCb?(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
        }
    }

    /// 完整测速：延迟 → 下载 → 上传，每阶段回调进度(0-1)与阶段名
    func run(progress: @escaping (Double, String) -> Void, completion: @escaping (SpeedTestResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var r = SpeedTestResult()
            // 1. 延迟
            progress(0.1, "测延迟中…")
            if let ping = self.measurePing() { r.pingMs = ping }
            // 2. 下载
            progress(0.2, "测下载中…")
            if let down = self.measureDownload(progress: { p in progress(0.2 + p * 0.4, "测下载中…") }) {
                r.downloadMbps = down
            }
            // 3. 上传
            progress(0.65, "测上传中…")
            if let up = self.measureUpload(progress: { p in progress(0.65 + p * 0.35, "测上传中…") }) {
                r.uploadMbps = up
            }
            if r.pingMs == nil && r.downloadMbps == nil && r.uploadMbps == nil {
                r.note = "测速失败：请检查网络连接（需要能访问 speed.cloudflare.com）"
            }
            DispatchQueue.main.async { completion(r) }
        }
    }

    private func measurePing() -> Double? {
        // 轮流 ping 多个公网 DNS，取第一个能通的
        for target in ["114.114.114.114", "223.5.5.5", "8.8.8.8"] {
            if let v = pingOnce(target) { return v }
        }
        return nil
    }

    private func pingOnce(_ host: String) -> Double? {
        guard let out = runCommandCapture("/sbin/ping", ["-c", "3", "-q", host]) else { return nil }
        for line in out.components(separatedBy: "\n") where line.contains("round-trip") {
            // round-trip min/avg/max/stddev = 12.3/15.6/20.1/3.2 ms
            if let part = line.split(separator: "=").last {
                let vals = part.trimmingCharacters(in: .whitespaces).split(separator: "/").map(String.init)
                if vals.count >= 2, let avg = Double(vals[1]) { return avg }
            }
        }
        return nil
    }

    private func measureDownload(progress: @escaping (Double) -> Void) -> Double? {
        let sema = DispatchSemaphore(value: 0)
        var result: Double?
        var didFinish = false
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        downProgressCb = progress
        receivedBytes = 0
        expectedBytes = 0
        let start = Date()
        let task = session.dataTask(with: downURL) { data, _, error in
            defer { sema.signal() }
            guard error == nil, let data, data.count > 0 else { return }
            let secs = Date().timeIntervalSince(start)
            if secs > 0.05 {
                result = Double(data.count) * 8 / secs / 1_000_000  // Mbps
            }
            didFinish = true
        }
        task.resume()
        // 等待完成；delegate 已在 didReceive 上报真实字节进度
        _ = sema.wait(timeout: .now() + 30)
        _ = didFinish
        return result
    }

    private func measureUpload(progress: @escaping (Double) -> Void) -> Double? {
        let sema = DispatchSemaphore(value: 0)
        var result: Double?
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        upProgressCb = progress
        var req = URLRequest(url: upURL)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let body = Data(count: upBytes)
        let start = Date()
        let task = session.uploadTask(with: req, from: body) { _, _, error in
            defer { sema.signal() }
            guard error == nil else { return }
            let secs = Date().timeIntervalSince(start)
            if secs > 0.05 {
                result = Double(self.upBytes) * 8 / secs / 1_000_000
            }
        }
        task.resume()
        _ = sema.wait(timeout: .now() + 30)
        return result
    }
}