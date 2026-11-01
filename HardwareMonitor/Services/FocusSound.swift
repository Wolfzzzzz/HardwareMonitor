//
//  FocusSound.swift
//  HardwareMonitor
//
//  版本 26DF10Q1beta1.0.7 —— 专注模块：番茄钟结束提示音
//  支持内置系统音（NSSound）与自定义音频文件（AVAudioPlayer），音量独立于系统音量。
//  自定义文件复制到 ~/Library/Application Support/HardwareMonitor/Sounds/。
//

import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// 专注结束提示音播放器
@MainActor
final class FocusSoundPlayer: ObservableObject {

    /// 可选内置音（均为系统自带音效）
    static let systemSounds: [String] = [
        "Glass", "Ping", "Pop", "Tink", "Purr", "Funk", "Hero",
        "Morse", "Basso", "Blow", "Frog", "Submarine", "Sosumi"
    ]

    // MARK: 偏好（UserDefaults 持久化）

    @Published var enabled: Bool = true {
        didSet { UserDefaults.standard.set(enabled, forKey: "focusSoundEnabled") }
    }
    @Published var volume: Double = 0.7 {
        didSet { UserDefaults.standard.set(volume, forKey: "focusSoundVolume") }
    }
    @Published var useCustom: Bool = false {
        didSet { UserDefaults.standard.set(useCustom, forKey: "focusSoundUseCustom") }
    }
    @Published private(set) var customFileName: String? {
        didSet {
            if let name = customFileName {
                UserDefaults.standard.set(name, forKey: "focusSoundCustomFile")
            } else {
                UserDefaults.standard.removeObject(forKey: "focusSoundCustomFile")
            }
        }
    }
    @Published var systemSoundName: String = "Glass" {
        didSet { UserDefaults.standard.set(systemSoundName, forKey: "focusSoundSystemName") }
    }

    // MARK: 播放器（保活，避免播放中被释放）

    private var audioPlayer: AVAudioPlayer?
    private var nsSound: NSSound?

    init() {
        let d = UserDefaults.standard
        enabled = (d.object(forKey: "focusSoundEnabled") as? Bool) ?? true
        volume = (d.object(forKey: "focusSoundVolume") as? Double) ?? 0.7
        useCustom = d.bool(forKey: "focusSoundUseCustom")
        customFileName = d.string(forKey: "focusSoundCustomFile")
        let name = d.string(forKey: "focusSoundSystemName") ?? "Glass"
        systemSoundName = FocusSoundPlayer.systemSounds.contains(name) ? name : "Glass"
    }

    // MARK: 描述

    /// 当前提示音描述（用于界面展示）
    var currentDescription: String {
        if useCustom, let name = customFileName {
            return LZ.t("自定义：\(name)", "Custom: \(name)")
        }
        return LZ.t("内置：\(systemSoundName)", "Built-in: \(systemSoundName)")
    }

    // MARK: 播放

    /// 阶段结束提示音（关闭时直接返回）
    func playFinish() {
        guard enabled else { return }
        play()
    }

    /// 试听（忽略开关状态）
    func preview() {
        play()
    }

    private func play() {
        if useCustom, let url = customFileURL {
            playFile(url)
        } else {
            playSystemSound()
        }
    }

    private func playSystemSound() {
        guard let sound = NSSound(named: NSSound.Name(systemSoundName)) else { return }
        sound.volume = Float(min(1, max(0, volume)))
        sound.stop()
        sound.play()
        nsSound = sound
    }

    private func playFile(_ url: URL) {
        do {
            audioPlayer?.stop()
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = Float(min(1, max(0, volume)))
            player.prepareToPlay()
            player.play()
            audioPlayer = player
        } catch {
            // 文件损坏或格式不支持时退回内置音
            playSystemSound()
        }
    }

    // MARK: 自定义文件

    /// 选择音频文件：复制到应用支持目录后启用并试听
    func importCustomFile() {
        let panel = NSOpenPanel()
        panel.title = LZ.t("选择提示音文件", "Choose a sound file")
        panel.prompt = LZ.t("选择", "Choose")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        var types: [UTType] = [.mp3, .wav, .mpeg4Audio, .aiff]
        if let caf = UTType(filenameExtension: "caf") { types.append(caf) }
        panel.allowedContentTypes = types

        guard panel.runModal() == .OK, let source = panel.url else { return }
        guard let dir = soundsDirectory else { return }

        let dest = dir.appendingPathComponent(source.lastPathComponent)
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: source, to: dest)
        } catch {
            return
        }

        customFileName = dest.lastPathComponent
        useCustom = true
        preview()
    }

    /// 移除自定义文件并回到内置音
    func removeCustom() {
        if let url = customFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        audioPlayer?.stop()
        audioPlayer = nil
        customFileName = nil
        useCustom = false
    }

    /// 应用支持目录下的音频目录（不存在则创建）
    private var soundsDirectory: URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base
            .appendingPathComponent("HardwareMonitor", isDirectory: true)
            .appendingPathComponent("Sounds", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 当前自定义文件地址（不存在则返回 nil）
    private var customFileURL: URL? {
        guard let name = customFileName, let dir = soundsDirectory else { return nil }
        let url = dir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
