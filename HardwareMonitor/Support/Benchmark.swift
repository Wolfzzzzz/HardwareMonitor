import Foundation

/// 多负载性能跑分（Geekbench 风格：单核 + 多核，4 类负载）
/// 每类负载用时间箱法（真实跑满固定时长）统计吞吐，换算分数
enum Benchmark {
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

    /// 并行跑全套负载（threads 个线程），返回每负载总分
    private static func runSuite(threads: Int) -> [Int] {
        var sums = [Double](repeating: 0, count: Workload.allCases.count)
        let group = DispatchGroup()
        let lock = NSLock()
        for _ in 0..<threads {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let counts = runAllWorkloads()
                lock.lock()
                for i in 0..<counts.count { sums[i] += counts[i] }
                lock.unlock()
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

    /// 单线程依次跑 4 类负载，返回每负载完成次数（时间箱）
    private static func runAllWorkloads() -> [Double] {
        var out = [Double](repeating: 0, count: Workload.allCases.count)

        // ① 整数运算：LCG 哈希链（计数依赖结果，防优化）
        do {
            let start = DispatchTime.now().uptimeNanoseconds
            var x: UInt64 = 0
            var i: UInt64 = 0
            while true {
                for _ in 0..<1024 {
                    x = x &* 6364136223846793005 &+ 12345
                    i &+= x & 1
                }
                if DispatchTime.now().uptimeNanoseconds - start >= runNanoseconds { break }
            }
            out[0] = Double(i)
        }

        // ② 浮点运算：双精度乘加链（点积风格）
        do {
            let start = DispatchTime.now().uptimeNanoseconds
            var acc: Double = 0
            var a: Double = 0.9999999
            var b: Double = 1.0000001
            var i: UInt64 = 0
            while true {
                for _ in 0..<1024 {
                    acc += a * b
                    a = a * 1.00000001 + 1e-9
                    b = b * 0.99999999 + 1e-9
                    i &+= 1
                }
                if DispatchTime.now().uptimeNanoseconds - start >= runNanoseconds { break }
            }
            out[1] = Double(i) + Double(acc.bitPattern & 1)  // 消耗 acc 防止优化
        }

        // ③ 内存带宽：16MB 数组顺序读写
        do {
            let count = 2_097_152  // 16MB
            var buf = [UInt64](repeating: 0, count: count)
            let start = DispatchTime.now().uptimeNanoseconds
            var p: Int = 0
            var v: UInt64 = 0
            var i: UInt64 = 0
            while true {
                for _ in 0..<1024 {
                    buf[p] &+= 1
                    v ^= buf[p]
                    p = (p + 1) & (count - 1)
                    i &+= 1
                }
                if DispatchTime.now().uptimeNanoseconds - start >= runNanoseconds { break }
            }
            out[2] = Double(i) + Double(v & 1)
        }

        // ④ 位运算加密：xorshift 旋转链
        do {
            let start = DispatchTime.now().uptimeNanoseconds
            var state: UInt64 = 0x9E3779B97F4A7C15
            var i: UInt64 = 0
            while true {
                for _ in 0..<1024 {
                    state ^= state << 13
                    state ^= state >> 7
                    state ^= state << 17
                    i &+= state & 1
                }
                if DispatchTime.now().uptimeNanoseconds - start >= runNanoseconds { break }
            }
            out[3] = Double(i)
        }

        return out
    }
}
