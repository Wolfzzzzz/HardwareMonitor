//
//  FocusFullScreen.swift
//  HardwareMonitor
//
//  版本 26DF10Q1beta1.0.7 —— 专注模块：沉浸式全屏专注窗口
//  用无边框 NSWindow 覆盖主屏，层级高于菜单栏；Esc 退出用 NSEvent 本地监听（最保守写法）。
//

import SwiftUI
import AppKit

// MARK: - 无边框可成为主窗口的窗口（borderless 默认不能成为 key window）

private final class FocusOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - 全屏窗口控制器

/// 专注全屏窗口控制器（由 AppModel 持有，避免视图重建导致窗口丢失）
@MainActor
final class FocusFullScreenController {

    private var window: NSWindow?
    private var escMonitor: Any?
    private weak var hostModel: AppModel?

    /// 是否正在显示
    var isShowing: Bool { window != nil }

    /// 显示全屏（已显示则前置）
    func show(model: AppModel, engine: FocusEngine, noise: NoiseMonitor, sound: FocusSoundPlayer) {
        hostModel = model

        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let window = FocusOverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .mainMenu + 1
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setFrame(screen.frame, display: true)

        let root = FocusFullScreenView(
            model: model,
            engine: engine,
            noise: noise,
            sound: sound,
            onExit: { [weak self] in self?.close() }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: screen.frame.size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
        installEscMonitor()
    }

    /// 关闭全屏并移除键盘监听
    func close() {
        removeEscMonitor()
        window?.orderOut(nil)
        window = nil
        hostModel?.isFocusFullScreen = false
        hostModel = nil
    }

    // MARK: Esc 监听

    private func installEscMonitor() {
        removeEscMonitor()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }   // 53 = Esc
            Task { @MainActor in self?.close() }
            return nil
        }
    }

    private func removeEscMonitor() {
        if let monitor = escMonitor {
            NSEvent.removeMonitor(monitor)
            escMonitor = nil
        }
    }
}

// MARK: - 全屏视图

struct FocusFullScreenView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: FocusEngine
    @ObservedObject var noise: NoiseMonitor
    @ObservedObject var sound: FocusSoundPlayer

    /// 退出动作（由控制器注入）
    var onExit: () -> Void

    var body: some View {
        GeometryReader { geo in
            let side = max(240, min(geo.size.width, geo.size.height) * 0.58)
            ZStack {
                breathingBackground

                // 自定义背景照片 + 自动黑色蒙版（未设置时透明，保持原呼吸氛围）
                FocusBackgroundLayer(background: model.focusBackground)

                VStack(spacing: 22) {
                    Text(engine.phaseLabel)
                        .font(.system(size: 14, weight: .medium))
                        .tracking(4)
                        .foregroundStyle(.white.opacity(0.55))

                    ZStack {
                        ring(side: side)

                        VStack(spacing: 10) {
                            Text(engine.remainingText)
                                .font(.system(size: max(100, min(140, side * 0.25)), weight: .ultraLight, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)

                            Text(engine.preciseTimeText)
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.40))
                        }
                    }

                    if noise.enabled {
                        noiseMiniBar
                    }

                    buttons
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack {
                    HStack {
                        Spacer()
                        Text("按 Esc 退出")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    Spacer()
                }
                .padding(22)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    // MARK: 呼吸背景

    /// 用 TimelineView 驱动呼吸感（不依赖 @State，避免宏问题）
    private var breathingBackground: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let pulse = 0.5 + 0.5 * sin(t * 0.7)

            ZStack {
                Color.black
                RadialGradient(
                    colors: [
                        model.accentColor.opacity(0.34 + 0.10 * pulse),
                        model.accentColor.opacity(0.06),
                        Color.black
                    ],
                    center: .center,
                    startRadius: 8,
                    endRadius: 660
                )
                .scaleEffect(1 + 0.045 * pulse)

                RadialGradient(
                    colors: [Color.white.opacity(0.05), Color.clear],
                    center: .top,
                    startRadius: 10,
                    endRadius: 720
                )
            }
            .ignoresSafeArea()
        }
    }

    // MARK: 进度环

    private func ring(side: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 8)

            Circle()
                .trim(from: 0, to: max(0.001, engine.progress))
                .stroke(
                    AngularGradient(
                        colors: [model.accentColor, model.accentColor.opacity(0.35), model.accentColor],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: engine.progress)
        }
        .frame(width: side, height: side)
    }

    // MARK: 噪音迷你条

    private var noiseMiniBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "waveform")
                .font(.system(size: 10))
                .foregroundStyle(noise.band.color)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(noise.band.color.opacity(0.85))
                        .frame(width: max(0, min(1, noise.level)) * geo.size.width)
                        .animation(.easeInOut(duration: 0.25), value: noise.level)
                }
            }
            .frame(width: 180, height: 5)

            Text(String(format: "%.0f dB", noise.db))
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: 按钮组

    private var buttons: some View {
        HStack(spacing: 12) {
            Button {
                engine.toggle()
            } label: {
                Label(engine.isRunning ? "暂停" : "继续",
                      systemImage: engine.isRunning ? "pause.fill" : "play.fill")
                    .frame(minWidth: 74)
            }

            Button {
                engine.skip()
            } label: {
                Label("跳过", systemImage: "forward.end")
            }

            Button {
                engine.reset()
            } label: {
                Label("重置", systemImage: "arrow.counterclockwise")
            }

            Button {
                onExit()
            } label: {
                Label("退出全屏", systemImage: "xmark")
            }
        }
        .font(.system(size: 12, weight: .medium))
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(.white)
        .padding(.top, 4)
    }
}
