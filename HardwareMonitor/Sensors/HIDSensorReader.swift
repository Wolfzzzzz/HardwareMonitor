import Foundation
import CoreFoundation
import Darwin

/// HID 传感器读取器（Apple Silicon 温度集线器，非 root 可读）
///
/// BuhoCleaner 等工具的温度数据即来自此路径：IOHIDEventSystemClient 枚举
/// usagePage 0xFF00 的传感器服务（PMU tdie / tdev / NAND / gas gauge 等），
/// 通过 IOHIDServiceClientCopyEvent 拉取当前值（vendor defined 事件，字段 0 为温度 °C）。
/// 私有 API 未 Swift 化，使用 dlopen + dlsym 动态调用。
final class HIDSensorReader {

    private var client: CFTypeRef?
    private var services: [(ref: CFTypeRef, name: String, usage: UInt32)] = []
    private(set) var isAvailable = false

    // 函数指针
    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias SetMatchingFn = @convention(c) (CFTypeRef, CFDictionary?) -> Void
    private typealias CopyServicesFn = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventFn = @convention(c) (CFTypeRef, UInt32, UInt32, UInt32, UInt32) -> Unmanaged<CFTypeRef>?
    private typealias EventTypeFn = @convention(c) (CFTypeRef) -> UInt32
    private typealias EventFloatFn = @convention(c) (CFTypeRef, UInt32) -> Double

    private var createFn: CreateFn?
    private var setMatchingFn: SetMatchingFn?
    private var copyServicesFn: CopyServicesFn?
    private var copyPropertyFn: CopyPropertyFn?
    private var copyEventFn: CopyEventFn?
    private var eventTypeFn: EventTypeFn?
    private var eventFloatFn: EventFloatFn?

    init() {
        guard dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) != nil else { return }
        createFn = load("IOHIDEventSystemClientCreate")
        setMatchingFn = load("IOHIDEventSystemClientSetMatching")
        copyServicesFn = load("IOHIDEventSystemClientCopyServices")
        copyPropertyFn = load("IOHIDServiceClientCopyProperty")
        copyEventFn = load("IOHIDServiceClientCopyEvent")
        eventTypeFn = load("IOHIDEventGetType")
        eventFloatFn = load("IOHIDEventGetFloatValue")

        // init 里只需确保服务/属性三个能加载；温度事件相关的 fn 在 sample() 里再 guard
        guard let create = createFn, let setMatching = setMatchingFn,
              let copyServices = copyServicesFn else { return }

        guard let client = create(nil)?.takeRetainedValue() else { return }
        self.client = client

        // 匹配 usagePage 0xFF00（Apple Silicon 传感器）
        let dict = ["PrimaryUsagePage": 0xFF00] as CFDictionary
        setMatching(client, dict)

        guard let arr = copyServices(client)?.takeRetainedValue() as? [Any] else { return }
        for item in arr {
            let svc = item as CFTypeRef
            let name = propertyString(svc, "Product") ?? "?"
            let usage = UInt32(propertyInt(svc, "PrimaryUsage") ?? 0)
            // 温度类服务：usage 5（温度）且名字包含温度相关关键词
            if usage == 5, isTemperatureName(name) {
                services.append((ref: svc, name: name, usage: usage))
            }
        }
        isAvailable = !services.isEmpty
    }

    private func load<T>(_ name: String) -> T? {
        let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        guard h != nil else { return nil }
        guard let sym = dlsym(h, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    private func cfString(_ s: String) -> CFString {
        CFStringCreateWithCString(nil, s, CFStringEncoding(0x08000100))!
    }

    private func propertyString(_ svc: CFTypeRef, _ key: String) -> String? {
        guard let fn = copyPropertyFn else { return nil }
        guard let raw = fn(svc, cfString(key)) else { return nil }
        let v: CFTypeRef = raw.takeRetainedValue()
        guard CFGetTypeID(v) == CFStringGetTypeID() else { return nil }
        return v as? String
    }

    private func propertyInt(_ svc: CFTypeRef, _ key: String) -> Int? {
        guard let fn = copyPropertyFn else { return nil }
        guard let raw = fn(svc, cfString(key)) else { return nil }
        let v: CFTypeRef = raw.takeRetainedValue()
        guard CFGetTypeID(v) == CFNumberGetTypeID() else { return nil }
        var i = 0
        CFNumberGetValue(unsafeBitCast(v, to: CFNumber.self), .intType, &i)
        return i
    }

    private func isTemperatureName(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("tdie") || n.contains("tdev") || n.contains("temp")
            || n.contains("nand") || n.contains("gauge") || n.contains("tcal")
    }

    /// 拉取全部温度，返回 (传感器列表, CPU 温度=tdie 最大值, GPU=nil)
    func sample() -> (temps: [(key: String, value: Double)], cpuTemp: Double?, gpuTemp: Double?) {
        guard isAvailable else { return ([], nil, nil) }
        guard let copyEvent = copyEventFn,
              let eventType = eventTypeFn, let eventFloat = eventFloatFn else {
            return ([], nil, nil)
        }
        var temps: [(String, Double)] = []
        var tdieMax: Double?
        for svc in services {
            guard let ev = copyEvent(svc.ref, 15, 0, 0xFF00, svc.usage)?.takeRetainedValue() else { continue }
            let t = eventType(ev)
            let v = eventFloat(ev, (t << 16) | 0)
            // 过滤无效读数
            guard v.isFinite, v > -50, v < 150 else { continue }
            temps.append((svc.name, v))
            if svc.name.lowercased().contains("tdie") {
                tdieMax = max(tdieMax ?? -1000, v)
            }
        }
        temps.sort { $0.0 < $1.0 }
        return (temps, tdieMax, nil)
    }
}
