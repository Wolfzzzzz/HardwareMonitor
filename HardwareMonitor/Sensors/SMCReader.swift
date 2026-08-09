import Foundation
import IOKit

/// SMC 读取器 —— 80 字节协议（社区验证布局，Intel + Apple Silicon 通用）
///
/// Apple Silicon 注意：温度/风扇为 `flt `(IEEE754) 类型，key 前缀 Tp*/Tg*/F*Ac；
/// 运行时全量扫描自动发现，不硬编码 key。
/// macOS 27 beta（M5）上系统可能拒绝该接口 —— 此时 `isAvailable == false`，UI 自动降级。
final class SMCReader {

    enum Command: UInt8 {
        case readKey = 5
        case getKeyFromIdx = 8
        case getKeyInfo = 9
    }

    // 80 字节布局偏移
    private let offKey = 0, offCmd = 40, offData32 = 44, offBytes = 48, offResult = 38
    private let offKeyInfo = 26, offKeyInfoType = 30

    private var conn: io_connect_t = 0
    private(set) var isAvailable = false
    private var temperatureKeys: [String] = []
    private var fanKeys: [String] = []

    init() {
        // 匹配 AppleSMCKeysEndpoint（新系统）或 AppleSMC（旧系统）
        var service: io_service_t = 0
        for name in ["AppleSMCKeysEndpoint", "AppleSMC"] {
            let s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(name))
            if s != 0 { service = s; break }
        }
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        let r = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard r == KERN_SUCCESS else { return }

        // 验证：读 #KEY
        guard let (data, _) = readKey("#KEY"), data.count >= 4 else {
            IOServiceClose(conn)
            conn = 0
            return
        }
        let keyCount = Int(UInt32(data[0]) << 24 | UInt32(data[1]) << 16 | UInt32(data[2]) << 8 | UInt32(data[3]))
        guard keyCount > 0, keyCount < 20000 else {
            IOServiceClose(conn)
            conn = 0
            return
        }
        isAvailable = true
        discoverKeys(count: keyCount)
    }

    deinit {
        if conn != 0 { IOServiceClose(conn) }
    }

    // MARK: - 底层调用

    private func call(_ input: [UInt8]) -> (kr: kern_return_t, out: [UInt8])? {
        let size = 80
        let inCnt = size
        var out = [UInt8](repeating: 0, count: size)
        var outCnt = size
        let kr = input.withUnsafeBytes { iptr in
            out.withUnsafeMutableBytes { optr in
                IOConnectCallStructMethod(conn, 2, iptr.baseAddress, inCnt, optr.baseAddress, &outCnt)
            }
        }
        guard kr == 0 else { return nil }
        return (kr, out)
    }

    private func readU32LE(_ b: [UInt8], _ off: Int) -> UInt32 {
        UInt32(b[off]) | UInt32(b[off+1]) << 8 | UInt32(b[off+2]) << 16 | UInt32(b[off+3]) << 24
    }

    private func u32Bytes(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)]
    }

    private func fourCC(_ raw: UInt32) -> String {
        var cs: [UInt8] = []
        for s in stride(from: 24, through: 0, by: -8) { cs.append(UInt8((raw >> s) & 0xff)) }
        return String(bytes: cs, encoding: .ascii) ?? "????"
    }

    private func typeString(_ b: [UInt8]) -> String { fourCC(readU32LE(b, offKeyInfoType).bigEndian) }

    private func baseInput(_ key: String) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 80)
        let kb = Array(key.utf8.prefix(4))
        if kb.count == 4 { b[offKey...offKey+3] = kb[0...3] }
        return b
    }

    // MARK: - 读取

    private func keyInfo(_ key: String) -> (size: Int, type: String)? {
        var input = baseInput(key)
        input[offCmd] = Command.getKeyInfo.rawValue
        guard let res = call(input), res.out[offResult] == 0 else { return nil }
        return (Int(readU32LE(res.out, offKeyInfo)), typeString(res.out))
    }

    private func readKey(_ key: String) -> (data: [UInt8], type: String)? {
        guard let info = keyInfo(key), info.size > 0 else { return nil }
        var input = baseInput(key)
        let sz = u32Bytes(UInt32(info.size))
        input[offKeyInfo...offKeyInfo+3] = sz[0...3]
        input[offCmd] = Command.readKey.rawValue
        guard let res = call(input), res.out[offResult] == 0 else { return nil }
        guard offBytes + info.size <= res.out.count else { return nil }
        return (Array(res.out[offBytes..<offBytes + info.size]), info.type)
    }

    /// 解码 SMC 值（sp78/fpe2/flt /ui8/ui16/ui32/si8）
    private func decode(_ data: [UInt8], _ type: String) -> Double? {
        switch type.trimmingCharacters(in: .whitespaces) {
        case "flt":
            guard data.count >= 4 else { return nil }
            let raw = UInt32(data[0]) | UInt32(data[1]) << 8 | UInt32(data[2]) << 16 | UInt32(data[3]) << 24
            return Double(Float(bitPattern: raw))
        case "sp78":
            guard data.count >= 2 else { return nil }
            return Double(Int16(data[0]) << 8 | Int16(data[1])) / 256.0
        case "fpe2":
            guard data.count >= 2 else { return nil }
            return Double(UInt16(data[0]) << 8 | UInt16(data[1])) / 4.0
        case "ui8": return data.first.map { Double($0) }
        case "ui16":
            guard data.count >= 2 else { return nil }
            return Double(UInt16(data[0]) << 8 | UInt16(data[1]))
        case "ui32":
            guard data.count >= 4 else { return nil }
            return Double(UInt32(data[0]) << 24 | UInt32(data[1]) << 16 | UInt32(data[2]) << 8 | UInt32(data[3]))
        case "si8": return data.first.map { Double(Int8(bitPattern: $0)) }
        default: return nil
        }
    }

    private func keyName(at index: Int) -> String? {
        var input = baseInput("")
        input[offCmd] = Command.getKeyFromIdx.rawValue
        let v = u32Bytes(UInt32(index))
        input[offData32...offData32+3] = v[0...3]
        guard let res = call(input), res.out[offResult] == 0 else { return nil }
        let name = fourCC(readU32LE(res.out, offKey).bigEndian)
        return name.count == 4 ? name : nil
    }

    // MARK: - 发现

    /// 全量扫描，发现温度 key（T 开头）与风扇 key（F 开头 + 数字）
    private func discoverKeys(count: Int) {
        var temps: [String] = []
        var fans: [String] = []
        for i in 0..<min(count, 800) {
            guard let name = keyName(at: i) else { continue }
            guard let (data, type) = readKey(name) else { continue }
            let t = type.trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("T"), let v = decode(data, t), v.isFinite, v > -50, v < 150 {
                temps.append(name)
            } else if name.hasPrefix("F"), name.count == 4, name.dropFirst().first?.isNumber == true,
                      let v = decode(data, t), v.isFinite, v > 0, v < 20000 {
                fans.append(name)
            }
        }
        temperatureKeys = temps
        fanKeys = fans
    }

    // MARK: - 对外采样

    /// 读取全部温度与风扇（供快照合成）
    func sample() -> (temps: [(key: String, value: Double)], fans: [(key: String, rpm: Double)], cpuTemp: Double?, gpuTemp: Double?) {
        guard isAvailable else { return ([], [], nil, nil) }

        var temps: [(String, Double)] = []
        for key in temperatureKeys {
            if let (data, type) = readKey(key), let v = decode(data, type), v.isFinite {
                temps.append((key, v))
            }
        }

        var fans: [(String, Double)] = []
        for key in fanKeys {
            if let (data, type) = readKey(key), let v = decode(data, type), v.isFinite {
                fans.append((key, v))
            }
        }

        // CPU 温度：Apple Silicon 取 Tp*/Tf* 最大值作为参考（P-core），GPU 取 Tg*/Tf1*
        var cpuTemp: Double?
        var gpuTemp: Double?
        for (key, v) in temps {
            let k = key.uppercased()
            if k.hasPrefix("TG") || (k.hasPrefix("TF") && k.dropFirst(2).first == "1") {
                gpuTemp = max(gpuTemp ?? -1000, v)
            } else if k.hasPrefix("TP") || k.hasPrefix("TC") || k.hasPrefix("TE") || k.hasPrefix("TF") {
                cpuTemp = max(cpuTemp ?? -1000, v)
            }
        }
        // 风扇 key 排序，取 Ac 结尾为实际转速
        fans.sort { $0.0 < $1.0 }
        return (temps, fans, cpuTemp, gpuTemp)
    }
}
