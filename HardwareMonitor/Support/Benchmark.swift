import Foundation

/// 多负载性能跑分（Geekbench 风格：单核 + 多核，4 类负载）
/// 每类负载用时间箱法（真实跑满固定时长）统计吞吐，换算分数
enum Benchmark {
    /// 跑分阶段（用于独立跑分界面驱动进度）
    enum Stage: String, CaseIterable {
        case idle, single, multi, done
        var title: String {
            switch self {
            case .idle: return "待开始"
            case .single: return "单核测试中"
            case .multi: return "多核测试中"
            case .done: return "完成"
            }
        }
    }
    /// 子负载类型
    enum Workload: String, CaseIterable {
        case integer = "整数运算"
        case float   = "浮点运算"
        case memory  = "内存带宽"
        case bitwise = "位运算加密"
    }

    /// 跑分结果
    struct Result {
        let singleScore: Int
        let multiScore: Int
        let workloads: [Workload]
        let singleSub: [Int]   // 各负载单核分
        let multiSub: [Int]    // 各负载多核分
    }

    /// 每类负载时间箱（0.35 秒）
    private static let runNanoseconds: UInt64 = 350_000_000

    /// 各负载吞吐 → 分数换算除数（本机实测校准：单核各负载 ~3000-3800，多核总分 ~22000 对齐 Geekbench 6）
    private static let divisors: [Workload: Double] = [
        .integer: 142_000,
        .float: 200_000,
        .memory: 634_000,
        .bitwise: 108_000,
    ]

    /// 跑分主入口：单核 + 多核
    static func run(cores: Int) -> Result {
        let ws = Workload.allCases
        let single = runSuite(threads: 1)
        let multi = runSuite(threads: cores)
        return Result(
            singleScore: Int(mean(single)),
            multiScore: Int(mean(multi)),
            workloads: ws,
            singleSub: single,
            multiSub: multi
        )
    }

    /// 并行跑全套负载（threads 个线程各跑完整套），返回每负载总分
    static func runSuite(threads: Int) -> [Int] {
        var sums = [Double](repeating: 0, count: Workload.allCases.count)
        let group = DispatchGroup()
        let lock = NSLock()
        for _ in 0..<threads {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for (i, w) in Workload.allCases.enumerated() {
                    let c = runOneWorkload(w)
                    lock.lock(); sums[i] += c; lock.unlock()
                }
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + 30)
        return Workload.allCases.enumerated().map { i, w in
            let throughput = sums[i] / (Double(runNanoseconds) / 1e9)
            return Int(min(10000, max(1, throughput / (divisors[w] ?? 42_000))))
        }
    }

    private static func mean(_ arr: [Int]) -> Double {
        guard !arr.isEmpty else { return 0 }
        return Double(arr.reduce(0, +)) / Double(arr.count)
    }

    /// 跑单个负载，返回完成迭代数（线程并行跑同一负载）
    static func runSingleWorkload(workload: Workload, threads: Int) -> Double {
        var total: Double = 0
        let group = DispatchGroup()
        let lock = NSLock()
        for _ in 0..<threads {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let count = runOneWorkload(workload)
                lock.lock(); total += count; lock.unlock()
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + 10)
        return total
    }

    /// 单线程跑单个负载（时间箱），返回完成迭代数
    private static func runOneWorkload(_ w: Workload) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        switch w {
        case .integer:
            var x: UInt64 = 0; var i: UInt64 = 0
            while true {
                for _ in 0..<1024 { x = x &* 6364136223846793005 &+ 12345; i &+= x & 1 }
                if DispatchTime.now().uptimeNanoseconds - start >= runNanoseconds { break }
            }
            return Double(i)
        case .float:
            var acc: Double = 0; var a = 0.9999999; var b = 1.0000001; var i: UInt64 = 0
            while true {
                for _ in 0..<1024 { acc += a * b; a = a * 1.00000001 + 1e-9; b = b * 0.99999999 + 1e-9; i &+= 1 }
                if DispatchTime.now().uptimeNanoseconds - start >= runNanoseconds { break }
            }
            return Double(i) + Double(acc.bitPattern & 1)
        case .memory:
            let count = 2_097_152
            var buf = [UInt64](repeating: 0, count: count)
            var p = 0; var v: UInt64 = 0; var i: UInt64 = 0
            while true {
                for _ in 0..<1024 { buf[p] &+= 1; v ^= buf[p]; p = (p + 1) & (count - 1); i &+= 1 }
                if DispatchTime.now().uptimeNanoseconds - start >= runNanoseconds { break }
            }
            return Double(i) + Double(v & 1)
        case .bitwise:
            var state: UInt64 = 0x9E3779B97F4A7C15; var i: UInt64 = 0
            while true {
                for _ in 0..<1024 { state ^= state << 13; state ^= state >> 7; state ^= state << 17; i &+= state & 1 }
                if DispatchTime.now().uptimeNanoseconds - start >= runNanoseconds { break }
            }
            return Double(i)
        }
    }

}
