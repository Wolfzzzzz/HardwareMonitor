import Foundation

/// 芯片识别 + 参考基准（Geekbench 6 多核分数量级）
enum ChipDB {
    struct Chip: Identifiable {
        let id: String
        let name: String
        let score: Int       // 参考多核分数
        let tier: String     // 档位标签
    }

    static let all: [Chip] = [
        Chip(id: "i5-10", name: "Intel i5 (10代)", score: 4500, tier: "入门"),
        Chip(id: "i7-9750h", name: "Intel i7-9750H", score: 6100, tier: "主流"),
        Chip(id: "m1", name: "Apple M1", score: 5900, tier: "主流"),
        Chip(id: "m1pro", name: "M1 Pro", score: 9900, tier: "高性能"),
        Chip(id: "m1max", name: "M1 Max", score: 12400, tier: "高性能"),
        Chip(id: "m2", name: "Apple M2", score: 8800, tier: "主流"),
        Chip(id: "m2pro", name: "M2 Pro", score: 15000, tier: "高性能"),
        Chip(id: "m2max", name: "M2 Max", score: 18500, tier: "高性能"),
        Chip(id: "m3", name: "Apple M3", score: 12000, tier: "主流"),
        Chip(id: "m3pro", name: "M3 Pro", score: 14000, tier: "高性能"),
        Chip(id: "m3max", name: "M3 Max", score: 21000, tier: "旗舰"),
        Chip(id: "i9-12900k", name: "Intel i9-12900K", score: 17500, tier: "高性能"),
        Chip(id: "m4", name: "Apple M4", score: 15000, tier: "主流"),
        Chip(id: "m4pro", name: "M4 Pro", score: 22000, tier: "高性能"),
        Chip(id: "m4max", name: "M4 Max", score: 29000, tier: "旗舰"),
        Chip(id: "m2ultra", name: "M2 Ultra", score: 27000, tier: "旗舰"),
    ]

    /// 从 CPU 品牌字符串自动识别芯片（长关键字优先）
    static func detect(from brand: String) -> Chip? {
        let b = brand.lowercased()
        let table: [(String, String)] = [
            ("m1 ultra", "m1ultra"), ("m1 pro", "m1pro"), ("m1 max", "m1max"), ("m1", "m1"),
            ("m2 ultra", "m2ultra"), ("m2 pro", "m2pro"), ("m2 max", "m2max"), ("m2", "m2"),
            ("m3 pro", "m3pro"), ("m3 max", "m3max"), ("m3", "m3"),
            ("m4 pro", "m4pro"), ("m4 max", "m4max"), ("m4", "m4"),
            ("i9-12900k", "i9-12900k"), ("i7-9750h", "i7-9750h"), ("i5", "i5-10"),
        ]
        for (kw, id) in table where b.contains(kw) {
            return all.first { $0.id == id }
        }
        return nil
    }
}
