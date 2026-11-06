import SwiftUI
import AVFoundation
import Accelerate

/// 专注音景（版本 26DF10Q1beta2.1.1 新增）
///
/// 不依赖任何音频素材：用 AVAudioEngine 实时合成白/粉噪声，做成 8 秒无缝循环，
/// 提供雨声 / 海浪 / 风扇三种场景，可单独调音量。全部离线、不上网、不录音。
@MainActor
final class FocusAmbience: ObservableObject {

    enum Scene: String, CaseIterable, Identifiable {
        case rain, waves, fan
        var id: String { rawValue }

        var label: String {
            switch self {
            case .rain: return "雨声"
            case .waves: return "海浪"
            case .fan: return "风扇"
            }
        }

        var icon: String {
            switch self {
            case .rain: return "cloud.rain"
            case .waves: return "water.waves"
            case .fan: return "fanblades"
            }
        }

        var hint: String {
            switch self {
            case .rain: return "细密白噪声，遮掉环境杂音"
            case .waves: return "低频起伏，适合放空"
            case .fan: return "低沉稳态，适合长时间专注"
            }
        }
    }

    // MARK: 状态

    @Published private(set) var isPlaying: Bool = false
    @Published var volume: Double = 0.45 {
        didSet {
            UserDefaults.standard.set(volume, forKey: "focusAmbienceVolume")
            player?.volume = Float(min(1, max(0, volume)))
        }
    }
    @Published var sceneID: String = Scene.rain.rawValue {
        didSet {
            UserDefaults.standard.set(sceneID, forKey: "focusAmbienceScene")
            if isPlaying { restart() }
        }
    }
    /// 出错时给界面看的提示
    @Published private(set) var errorText: String?

    var scene: Scene { Scene(rawValue: sceneID) ?? .rain }

    // MARK: 音频

    private let engine = AVAudioEngine()
    private var player: AVAudioPlayerNode?
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private let sampleRate: Double = 44_100
    private let loopSeconds: Double = 8

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["focusAmbienceVolume": 0.45, "focusAmbienceScene": Scene.rain.rawValue])
        volume = min(1, max(0, d.double(forKey: "focusAmbienceVolume")))
        sceneID = d.string(forKey: "focusAmbienceScene") ?? Scene.rain.rawValue
    }

    // MARK: 控制

    func toggle() { isPlaying ? stop() : play() }

    func play() {
        guard !isPlaying else { return }
        guard let buffer = buffer(for: scene) else {
            errorText = "音频初始化失败"
            return
        }
        do {
            if engine.isRunning == false {
                engine.prepare()
                try engine.start()
            }
            let node = player ?? makePlayerNode()
            player = node
            node.volume = Float(min(1, max(0, volume)))
            node.stop()
            node.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            node.play()
            isPlaying = true
            errorText = nil
        } catch {
            errorText = "无法播放：\(error.localizedDescription)"
            isPlaying = false
        }
    }

    func stop() {
        player?.stop()
        isPlaying = false
        // 停掉引擎，避免空闲占用音频通道
        if engine.isRunning { engine.pause() }
    }

    /// 切换场景时无缝换 buffer
    private func restart() {
        guard isPlaying, let buffer = buffer(for: scene) else { return }
        player?.stop()
        player?.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        player?.play()
    }

    private func makePlayerNode() -> AVAudioPlayerNode {
        let node = AVAudioPlayerNode()
        engine.attach(node)
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        return node
    }

    // MARK: 合成

    private func buffer(for scene: Scene) -> AVAudioPCMBuffer? {
        if let cached = buffers[scene.rawValue] { return cached }
        guard let made = Self.synthesize(scene: scene, seconds: loopSeconds, sampleRate: sampleRate) else { return nil }
        buffers[scene.rawValue] = made
        return made
    }

    /// 生成无缝循环的立体声噪声 buffer
    nonisolated static func synthesize(scene: Scene, seconds: Double, sampleRate: Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(seconds * sampleRate)
        guard frames > 0,
              let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames),
              let data = buf.floatChannelData else { return nil }
        buf.frameLength = frames

        let n = Int(frames)
        var lowL: Float = 0
        var lowR: Float = 0
        var generator = SystemRandomNumberGenerator()
        let fade = Int(0.02 * sampleRate)   // 20ms 首尾淡化，消除循环接缝

        for i in 0..<n {
            let nL = Float.random(in: -1...1, using: &generator)
            let nR = Float.random(in: -1...1, using: &generator)
            var l = nL
            var r = nR

            switch scene {
            case .rain:
                // 轻低通保留一点雨滴的"沙沙"质感
                lowL += (nL - lowL) * 0.62
                lowR += (nR - lowR) * 0.62
                l = lowL * 1.35
                r = lowR * 1.35

            case .waves:
                // 强低通 + 1 周期/8 秒的潮汐起伏
                lowL += (nL - lowL) * 0.055
                lowR += (nR - lowR) * 0.055
                let t = Double(i) / sampleRate
                let phase = 2 * Double.pi * (1.0 / seconds) * t - Double.pi / 2
                let am = Float(0.42 + 0.58 * (0.5 + 0.5 * sin(phase)))
                l = lowL * 7.5 * am
                r = lowR * 7.5 * am

            case .fan:
                // 更深低通，稳态无明显起伏
                lowL += (nL - lowL) * 0.02
                lowR += (nR - lowR) * 0.02
                l = lowL * 11
                r = lowR * 11
            }

            if i < fade {
                let g = Float(i) / Float(fade)
                l *= g; r *= g
            } else if i > n - fade {
                let g = Float(n - i) / Float(fade)
                l *= g; r *= g
            }

            data[0][i] = max(-1, min(1, l))
            data[1][i] = max(-1, min(1, r))
        }
        return buf
    }
}
