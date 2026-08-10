import Foundation

/// Pro 激活码校验
/// 格式：xxxx-xxxx-xxxx-xxxx-xxxxx-x（4-4-4-4-5-1，去连字符后 22 字符）
/// 前 21 字符为数据（随机），末 1 字符为校验码（DJB2 哈希 mod 32）
enum License {
    /// 去易混淆字符（0/O/1/I/L）的 base32 字母表
    static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    /// 校验激活码是否合法
    static func validate(_ code: String) -> Bool {
        let s = code.uppercased().filter { $0 != "-" && $0 != " " }
        guard s.count == 22 else { return false }
        guard s.allSatisfy({ alphabet.contains($0) }) else { return false }
        let data = s.prefix(21)
        var hash: UInt64 = 5381
        for ch in data {
            guard let idx = alphabet.firstIndex(of: ch) else { return false }
            hash = hash &* 33 &+ UInt64(idx)
        }
        let expected = alphabet[Int(hash % UInt64(alphabet.count))]
        return expected == s.last
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
