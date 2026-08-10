import Foundation

/// 版本档位
enum ProTier: String {
    case free = "free"
    case deluxe = "deluxe"
    case premium = "premium"

    var displayName: String {
        switch self {
        case .free: return "Standard"
        case .deluxe: return "Deluxe"
        case .premium: return "Premium Deluxe"
        }
    }

    var priceText: String {
        switch self {
        case .free: return "免费"
        case .deluxe: return "¥38"
        case .premium: return "¥68"
        }
    }
}

/// 激活码校验
/// 格式：xxxx-xxxx-xxxx-xxxx-xxxxx-x（4-4-4-4-5-1，去连字符后 22 字符）
/// 前 21 字符为数据（首字符标记档位：D=Deluxe，P=Premium Deluxe，其余=兼容旧码按 Deluxe），末 1 字符为校验码
enum License {
    /// 标准 base32 字母表（RFC4648，32 字符）
    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// 校验激活码是否合法
    static func validate(_ code: String) -> Bool {
        guard let s = cleaned(code), s.count == 22 else { return false }
        return checksumOK(String(s.prefix(21)), check: s.last!)
    }

    /// 解析激活码对应档位（老码无标记 → Deluxe）
    static func tier(of code: String) -> ProTier {
        guard let s = cleaned(code), s.count == 22, checksumOK(String(s.prefix(21)), check: s.last!) else {
            return .free
        }
        switch s.first {
        case "P": return .premium
        case "D": return .deluxe
        default: return .deluxe  // 兼容旧码
        }
    }

    /// 清理输入：只保留合法字符
    static func cleaned(_ code: String) -> String? {
        let s = code.uppercased().filter { alphabet.contains($0) }
        return s.isEmpty ? nil : s
    }

    private static func checksumOK(_ data: String, check: Character) -> Bool {
        var hash: UInt64 = 5381
        for ch in data {
            guard let idx = alphabet.firstIndex(of: ch) else { return false }
            hash = hash &* 33 &+ UInt64(idx)
        }
        let expected = alphabet[Int(hash % UInt64(alphabet.count))]
        return expected == check
    }

    /// 格式化为展示样式（4-4-4-4-5-1）
    static func format(_ code: String) -> String {
        let s = code.uppercased().filter { $0 != "-" && $0 != " " }
        guard s.count == 22 else { return code }
        let parts = [s.prefix(4), s.dropFirst(4).prefix(4), s.dropFirst(8).prefix(4),
                     s.dropFirst(12).prefix(4), s.dropFirst(16).prefix(5), s.suffix(1)]
        return parts.map(String.init).joined(separator: "-")
    }
}
