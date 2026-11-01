//
//  NoiseMonitor.swift
//  HardwareMonitor
//
//  版本 26DF10Q1beta1.0.7 —— 专注模块：麦克风环境噪音检测
//  说明：仅在用户手动开启时占用麦克风；关闭后立即摘除 tap 并停止引擎，
//        系统菜单栏麦克风指示灯会随之熄灭。音频只在内存中计算 RMS，不保存、不上传。
//

import SwiftUI
import AVFoundation
import Accelerate
import QuartzCore

// MARK: - 噪音等级

/// 环境噪音等级（按近似 dB SPL 划分）
enum NoiseBand: Int, CaseIterable {
    case quiet      // 安静
    case normal     // 适中
    case loud       // 吵闹
    case veryLoud   // 太吵

    /// 等级名称
    var label: String {
        switch self {
        case .quiet:    return LZ.t("安静", "Quiet")
        case .normal:   return LZ.t("适中", "Normal")
        case .loud:     return LZ.t("吵闹", "Loud")
        case .veryLoud: return LZ.t("太吵", "Too loud")
        }
    }

    /// 建议文案
    var advice: String {
        switch self {
        case .quiet:    return LZ.t("环境很安静，适合深度专注", "Nice and quiet — great for deep focus")
        case .normal:   return LZ.t("环境噪音正常，可以开始专注", "Noise level is fine for focusing")
        case .loud:     return LZ.t("有点吵，建议戴耳机或换个位置", "A bit noisy — consider headphones")
        case .veryLoud: return LZ.t("环境太吵，建议更换场所或使用降噪耳机", "Too noisy — change place or use ANC")
        }
    }

    /// 等级配色
    var color: Color {
        switch self {
        case .quiet:    return Color(red: 0.30, green: 0.78, blue: 0.45)
        case .normal:   return Color(red: 0.92, green: 0.74, blue: 0.25)
        case .loud:     return Color(red: 0.95, green: 0.55, blue: 0.22)
        case .veryLoud: return Color(red: 0.92, green: 0.30, blue: 0.30)
        }
    }

    /// 由 dB 值判定等级
    static func from(db: Double) -> NoiseBand {
        if db < 45 { return .quiet }
        if db < 60 { return .normal }
        if db < 75 { return .loud }
        return .veryLoud
    }
}

// MARK: - 噪音检测

/// 麦克风噪音检测：AVAudioEngine + installTap，RMS → 近似 dB SPL
@MainActor
final class NoiseMonitor: ObservableObject {

    // MARK: 对外状态

    /// 是否开启（持久化；只写 UserDefaults，不在此调用其他方法，避免初始化期问题）
    @Published var enabled: Bool = UserDefaults.standard.bool(forKey: "noiseMonitorEnabled") {
        didSet { UserDefaults.standard.set(enabled, forKey: "noiseMonitorEnabled") }
    }
    /// 是否已获得麦克风权限
    @Published private(set) var authorized: Bool = false
    /// 引擎是否正在运行
    @Published private(set) var running: Bool = false
    /// 近似 dB SPL（30...110）
    @Published private(set) var db: Double = 35
    /// 峰值 dB
    @Published private(set) var peakDb: Double = 35
    /// 归一化电平 0...1
    @Published private(set) var level: Double = 0
    /// 当前噪音等级
    @Published private(set) var band: NoiseBand = .quiet
    /// 状态文案
    @Published private(set) var statusText: String = ""
    /// 最近 60 个 level 采样（迷你波形）
    @Published private(set) var history: [Double] = []

    // MARK: 内部实现

    private let engine = AVAudioEngine()
    private var tapInstalled = false
    private var lastIngestMono: CFTimeInterval = 0
    private let maxHistory = 60
    /// 节流间隔（约 11Hz，避免 SwiftUI 过载）
    private let ingestInterval: CFTimeInterval = 0.09
    /// 指数平滑系数
    private let smoothingAlpha: Double = 0.25

    init() {
        authorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        statusText = enabled
            ? LZ.t("准备中…", "Preparing…")
            : LZ.t("已关闭", "Off")
    }

    // MARK: 开关

    /// 由视图 onChange 调用：统一处理开关与引擎生命周期
    func setEnabled(_ on: Bool) {
        if enabled != on {
            enabled = on          // didSet 只写 UserDefaults
        }
        if on {
            start()
        } else {
            stop()
        }
    }

    /// 开启检测（会先检查/申请麦克风权限）
    func start() {
        guard enabled else { return }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            authorized = true
            startEngine()

        case .notDetermined:
            statusText = LZ.t("等待麦克风授权…", "Waiting for microphone access…")
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.authorized = granted
                    if granted {
                        if self.enabled { self.startEngine() }
                    } else {
                        self.applySilence(status: LZ.t("麦克风权限被拒绝", "Microphone access denied"))
                    }
                }
            }

        default:
            authorized = false
            applySilence(status: LZ.t("麦克风权限被拒绝，请在系统设置中允许", "Microphone denied — allow it in System Settings"))
        }
    }

    /// 主动申请权限（视图中的「授予麦克风权限」按钮）
    func requestPermission() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            authorized = true
            if enabled { start() }
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.authorized = granted
                if granted {
                    if self.enabled { self.start() }
                } else {
                    self.applySilence(status: LZ.t("麦克风权限被拒绝", "Microphone access denied"))
                }
            }
        }
    }

    /// 刷新权限状态（从系统设置回来时调用）
    func refreshAuthorization() {
        authorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// 关闭检测：必须摘除 tap 并停止引擎，确保麦克风指示灯熄灭
    func stop() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning { engine.stop() }
        running = false
        level = 0
        band = .quiet
        statusText = LZ.t("已关闭", "Off")
    }

    /// 重置峰值
    func resetPeak() {
        peakDb = db
    }

    // MARK: 引擎

    private func startEngine() {
        guard !running else { return }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            applySilence(status: LZ.t("未检测到麦克风输入", "No microphone input"))
            return
        }

        if tapInstalled {
            input.removeTap(onBus: 0)
            tapInstalled = false
        }

        // tap 回调在实时音频线程：只算 RMS，再切回主线程更新状态
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let rawDb = NoiseMonitor.meterDb(from: buffer) else { return }
            Task { @MainActor [weak self] in
                self?.ingest(rawDb: rawDb)
            }
        }
        tapInstalled = true

        engine.prepare()
        do {
            try engine.start()
            running = true
            statusText = LZ.t("正在检测", "Listening")
        } catch {
            running = false
            if tapInstalled {
                input.removeTap(onBus: 0)
                tapInstalled = false
            }
            applySilence(status: LZ.t("麦克风启动失败", "Failed to start microphone"))
        }
    }

    /// 把原始 dB 写入 @Published（节流 + 平滑）
    private func ingest(rawDb: Double) {
        guard running else { return }

        let now = CACurrentMediaTime()
        guard now - lastIngestMono >= ingestInterval else { return }
        lastIngestMono = now

        let smoothed = min(110, max(30, db * (1 - smoothingAlpha) + rawDb * smoothingAlpha))
        db = smoothed
        if rawDb > peakDb { peakDb = min(110, max(30, rawDb)) }
        level = min(1, max(0, (smoothed - 30) / 80))
        band = NoiseBand.from(db: smoothed)

        history.append(level)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
    }

    /// 静默态：清空显示并写入状态文案
    private func applySilence(status: String) {
        running = false
        level = 0
        band = .quiet
        statusText = status
    }

    /// 由采样缓冲计算近似 dB SPL
    nonisolated static func meterDb(from buffer: AVAudioPCMBuffer) -> Double? {
        guard let data = buffer.floatChannelData else { return nil }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return nil }

        var rms: Float = 0
        vDSP_rmsqv(data[0], 1, &rms, vDSP_Length(frames))

        let rmsValue = Double(max(rms, 1e-9))
        let dbfs = 20 * log10(rmsValue)
        // dBFS → 近似 dB SPL（麦克风增益未知，做经验偏移）
        return min(110, max(30, dbfs + 100))
    }
}
