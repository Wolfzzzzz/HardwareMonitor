import Foundation

enum Fmt {
    static func bytes(_ v: UInt64) -> String {
        let b = Double(v)
        switch b {
        case 0..<1024: return String(format: "%.0f B", b)
        case 1024..<(1024*1024): return String(format: "%.1f KB", b/1024)
        case (1024*1024)..<(1024*1024*1024): return String(format: "%.1f MB", b/1024/1024)
        default: return String(format: "%.2f GB", b/1024/1024/1024)
        }
    }

    static func speed(_ bytesPerSec: Double) -> String {
        switch bytesPerSec {
        case 0..<1024: return String(format: "%.0f B/s", bytesPerSec)
        case 1024..<(1024*1024): return String(format: "%.1f KB/s", bytesPerSec/1024)
        case (1024*1024)..<(1024*1024*1024): return String(format: "%.2f MB/s", bytesPerSec/1024/1024)
        default: return String(format: "%.2f GB/s", bytesPerSec/1024/1024/1024)
        }
    }

    static func percent(_ v: Double, digits: Int = 0) -> String {
        String(format: "%.\(digits)f%%", v)
    }

    static func temp(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "--" }
        return String(format: "%.0f°C", v)
    }

    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}
