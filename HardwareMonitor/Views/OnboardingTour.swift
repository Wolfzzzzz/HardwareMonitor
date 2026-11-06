//
//  OnboardingTour.swift
//  HardwareMonitor
//
//  首次启动漫游式引导教程（版本 26DF10Q1beta1.0.7）
//
//  设计要点：
//  1. 整窗暗色遮罩 + 圆角矩形挖洞高亮，挖洞用 Path + even-odd 填充实现；
//  2. 气泡位置随锚点矩形弹簧动画平滑移动，绝不瞬移；
//  3. 需要切主标签 / 工具页侧栏的步骤，一定「先翻页、等锚点就绪、再淡入气泡」；
//  4. 键盘 → 下一步、← 上一步、Esc 跳过；点击遮罩不结束（防误触）。
//
//  注意：本工程禁用 Swift 宏（@State / @Observable / @Bindable / #Preview），
//  统一使用 ObservableObject + @Published + @StateObject / @EnvironmentObject。
//

import SwiftUI
import AppKit

// MARK: - 步骤模型

/// 引导步骤
struct TourStep {
    let id: String
    let title: String
    let detail: String
    /// 需要切换主标签时给值（0 监控 / 1 剪贴板 / 2 工具 / 3 专注）
    let tab: Int?
    /// 需要切换工具页侧栏时给值
    let toolTab: Int?
    /// 锚点 id；nil 表示屏幕居中卡片
    let anchor: String?
}

// MARK: - 锚点收集

/// 锚点收集用的 PreferenceKey（id → 全局坐标）
struct TourAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// 锚点中转站。
///
/// `.overlay(...)` 的内容与底层视图是**兄弟层级**，Preference 只能向上冒泡，
/// 覆盖层读不到底层视图发出的 Preference。为了在不改动 MainWindowView 的前提下
/// 也能拿到锚点坐标，`tourAnchor` 会把同一份矩形同时写进这里，由覆盖层订阅。
final class TourAnchorStore: ObservableObject {
    static let shared = TourAnchorStore()

    @Published var rects: [String: CGRect] = [:]

    /// 仅在主线程调用；坐标变化小于 0.5pt 视为未变，避免布局抖动形成回环
    func report(_ id: String, _ rect: CGRect) {
        guard rect.width > 0.5, rect.height > 0.5 else { return }
        if let old = rects[id],
           abs(old.minX - rect.minX) < 0.5,
           abs(old.minY - rect.minY) < 0.5,
           abs(old.width - rect.width) < 0.5,
           abs(old.height - rect.height) < 0.5 {
            return
        }
        rects[id] = rect
    }
}

/// 延后一轮主线程再上报，避免在视图更新过程中发布变更
private func reportTourAnchor(_ id: String, _ rect: CGRect) {
    DispatchQueue.main.async {
        TourAnchorStore.shared.report(id, rect)
    }
}

extension View {
    /// 给视图打上引导锚点，坐标取全局坐标系
    func tourAnchor(_ id: String) -> some View {
        self.background(
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                Color.clear
                    .preference(key: TourAnchorKey.self, value: [id: frame])
                    .onAppear { reportTourAnchor(id, frame) }
                    .onChange(of: frame) { _, newFrame in
                        reportTourAnchor(id, newFrame)
                    }
            }
        )
    }
}

// MARK: - 覆盖层内部状态

/// 覆盖层自己的局部状态（本工程不允许 @State，用 ObservableObject 承载）
final class TourUILocalState: ObservableObject {
    /// 气泡实测高度，用于决定放锚点下方还是上方
    @Published var bubbleHeight: CGFloat = 190
    /// 键盘事件监听句柄，isActive 变化时挂载 / 卸载
    @Published var keyMonitor: Any?
}

/// 气泡高度测量
private struct TourBubbleHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - 控制器

@MainActor
final class OnboardingController: ObservableObject {

    /// 完成标记键（首启引导 V1）
    private static let completedKey = "onboardingCompletedV1"

    /// 切步时广播：请滚动区域把该锚点滚进可视区（监控页 / 专注页的长列表）
    /// object 为锚点 id 字符串
    static let scrollNotification = Notification.Name("hwmon.tourScrollToAnchor")

    @Published private(set) var isActive: Bool = false
    @Published private(set) var index: Int = 0
    @Published private(set) var bubbleVisible: Bool = false
    /// 当前锚点矩形（全局坐标，来自 PreferenceKey / 中转站）
    @Published private(set) var anchorRect: CGRect?
    @Published private(set) var anchors: [String: CGRect] = [:]

    let steps: [TourStep]

    /// 主数据模型（弱引用，用于切页与读取主题色）
    private weak var model: AppModel?
    /// 当前进行中的过渡任务
    private var stepTask: Task<Void, Never>?
    /// 目标步骤（连续点「下一步」时以它为准，避免 index 尚未更新导致跳错）
    private var target: Int = 0
    /// start() 时若还没绑定 model，则等绑定后补一次开场
    private var needsInitialReveal = false

    init() {
        self.steps = OnboardingController.makeSteps()
    }

    // MARK: 对外状态

    /// 是否已完成过引导
    var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: OnboardingController.completedKey)
    }

    /// 当前步骤
    var currentStep: TourStep? {
        steps.indices.contains(index) ? steps[index] : nil
    }

    var isLastStep: Bool { index >= steps.count - 1 }
    var totalCount: Int { steps.count }

    /// 「第 n / N 步」
    var progressText: String {
        "第 \(min(index + 1, max(steps.count, 1))) / \(steps.count) 步"
    }

    // MARK: 生命周期

    /// 绑定主模型（覆盖层出现时调用）
    func bind(_ model: AppModel) {
        self.model = model
        model.tourRunning = isActive
        if isActive, needsInitialReveal {
            needsInitialReveal = false
            schedule(index, initial: true)
        }
    }

    /// 开始（或重新播放）引导
    func start() {
        guard !isActive else { return }
        index = 0
        target = 0
        anchorRect = nil
        bubbleVisible = false
        isActive = true
        model?.tourRunning = true

        if model == nil {
            // 还没绑定模型，等 bind() 后再开场
            needsInitialReveal = true
        } else {
            schedule(0, initial: true)
        }
    }

    /// 下一步（最后一步自动收尾）
    func next() {
        guard isActive else { return }
        if target >= steps.count - 1 {
            finish()
            return
        }
        schedule(target + 1, initial: false)
    }

    /// 上一步
    func previous() {
        guard isActive, target > 0 else { return }
        schedule(target - 1, initial: false)
    }

    /// 收尾：回到监控主界面 + 持久化完成标记 + 淡出
    func finish() {
        stepTask?.cancel()
        stepTask = nil
        target = 0
        needsInitialReveal = false

        if let model = model {
            model.mainTab = 0
            model.toolTab = 0
            model.tourRunning = false
        }

        UserDefaults.standard.set(true, forKey: OnboardingController.completedKey)

        withAnimation(.easeInOut(duration: 0.3)) {
            bubbleVisible = false
            isActive = false
        }
    }

    // MARK: 锚点

    /// 合并锚点坐标。保留旧值（视图重新显示后不一定再触发回调），只覆盖同 id 的新坐标
    func updateAnchors(_ map: [String: CGRect]) {
        var merged = anchors
        for (key, rect) in map where rect.width > 0.5 && rect.height > 0.5 {
            merged[key] = rect
        }
        guard merged != anchors else { return }
        anchors = merged

        // 窗口缩放 / 滚动时让高亮框跟着走
        guard bubbleVisible,
              let step = currentStep,
              let id = step.anchor,
              let rect = merged[id] else { return }
        if anchorRect != rect {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                anchorRect = rect
            }
        }
    }

    /// 切换到指定步骤：先收气泡 → 切页 → 等锚点 → 再出气泡
    private func schedule(_ newIndex: Int, initial: Bool) {
        guard steps.indices.contains(newIndex) else { return }
        let step = steps[newIndex]
        target = newIndex
        stepTask?.cancel()

        // 是否需要翻页（决定出框前的渲染缓冲时长）
        var tabChanged = false
        if let model = model, let tab = step.tab, model.mainTab != tab {
            tabChanged = true
        }

        stepTask = Task { @MainActor [weak self] in
            guard let self = self else { return }

            // 1) 气泡先淡出，绝不允许瞬移换位置
            withAnimation(.easeOut(duration: 0.18)) {
                self.bubbleVisible = false
            }
            if !initial {
                try? await Task.sleep(nanoseconds: 190_000_000)
                if Task.isCancelled { return }
            }

            // 2) 更新步骤与工具页侧栏
            self.index = newIndex
            if let toolTab = step.toolTab, let model = self.model {
                model.toolTab = toolTab
            }

            // 3) 切主标签（不包动画，避免与新页面首帧渲染争抢）
            if let tab = step.tab, let model = self.model, model.mainTab != tab {
                model.mainTab = tab
            }

            // 4) 等锚点坐标就绪（最长 0.9s）
            if let id = step.anchor {
                // 4.0) 先把目标滚进可视区，避免气泡指向窗口外
                NotificationCenter.default.post(name: OnboardingController.scrollNotification, object: id)

                let deadline = Date().addingTimeInterval(0.9)
                while self.anchors[id] == nil {
                    if Date() >= deadline { break }
                    try? await Task.sleep(nanoseconds: 40_000_000)
                    if Task.isCancelled { return }
                }
                if Task.isCancelled { return }

                // 5) 翻页/滚动缓冲：先让新页面与滚动动画落定，再出框（0.52s / 0.18s）
                try? await Task.sleep(nanoseconds: tabChanged ? 520_000_000 : 180_000_000)
                if Task.isCancelled { return }

                withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                    self.anchorRect = self.anchors[id]
                }
            } else {
                // 居中卡片：高亮收缩到屏幕中心
                withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                    self.anchorRect = nil
                }
                // 同样遵守「先翻页再出框」，带切页的居中步骤也要等新页面渲染
                try? await Task.sleep(nanoseconds: tabChanged ? 400_000_000 : 160_000_000)
                if Task.isCancelled { return }
            }

            // 6) 气泡淡入（配合 scale 0.96 → 1）
            withAnimation(.easeOut(duration: 0.22)) {
                self.bubbleVisible = true
            }
        }
    }

    // MARK: 脚本

    private static func makeSteps() -> [TourStep] {
        [
            TourStep(id: "welcome",
                     title: "欢迎使用硬件监控",
                     detail: "这次引导会带你走一遍全部功能，大约 1 分钟，随时可以跳过。",
                     tab: 0, toolTab: nil, anchor: nil),

            TourStep(id: "header",
                     title: "数据来源与刷新",
                     detail: "顶部会显示温度来自 SMC 还是 HID 传感器，以及数据更新时间和当前刷新间隔，一眼判断数据是否新鲜。",
                     tab: nil, toolTab: nil, anchor: "header"),

            TourStep(id: "tabs",
                     title: "四个主标签",
                     detail: "监控看硬件状态，剪贴板存历史，工具里有 11 个实用小工具，专注是番茄钟与噪音检测。",
                     tab: nil, toolTab: nil, anchor: "tabs"),

            TourStep(id: "overview",
                     title: "硬件概览",
                     detail: "8 张卡片分别看芯片温度、CPU、内存、磁盘、电池、网络、屏幕亮度和风扇转速。",
                     tab: nil, toolTab: nil, anchor: "overview"),

            TourStep(id: "trends",
                     title: "实时趋势",
                     detail: "温度、占用率随时间的曲线，能看出负载变化。",
                     tab: nil, toolTab: nil, anchor: "trends"),

            TourStep(id: "temps",
                     title: "全部温度传感器",
                     detail: "逐个列出传感器读数，超过 60°C 会变色提醒。",
                     tab: nil, toolTab: nil, anchor: "temps"),

            TourStep(id: "process",
                     title: "进程资源 TOP 10",
                     detail: "一眼看出谁在吃 CPU 和内存。",
                     tab: nil, toolTab: nil, anchor: "process"),

            TourStep(id: "clipboard",
                     title: "剪贴板历史",
                     detail: "自动记录复制过的内容，可以搜索、置顶、一键清空。",
                     tab: 1, toolTab: nil, anchor: nil),

            TourStep(id: "tools",
                     title: "工具箱",
                     detail: "二维码、单位换算、编码工具、颜色工具、便签、常用文件夹、高级功能都在这里。",
                     tab: 2, toolTab: nil, anchor: "tools.sidebar"),

            TourStep(id: "focus.clock",
                     title: "精确时钟",
                     detail: "毫秒级显示，基于系统校准时间 + 单调时钟，睡眠唤醒后也不会跑偏。",
                     tab: 3, toolTab: nil, anchor: "focus.clock"),

            TourStep(id: "focus",
                     title: "番茄钟",
                     detail: "圆环倒计时，可调专注时长、短休长休、自动开始下一轮。",
                     tab: 3, toolTab: nil, anchor: "focus.timer"),

            TourStep(id: "focus.fullscreen",
                     title: "专注全屏",
                     detail: "一键进入沉浸式全屏，只剩计时器和进度环，Esc 退出。",
                     tab: 3, toolTab: nil, anchor: "focus.fullscreen"),

            TourStep(id: "focus.noise",
                     title: "麦克风噪音检测",
                     detail: "实时分贝和噪音等级，觉得吵可以开窗或戴耳机；不想用随时关掉，关掉就不占麦克风。",
                     tab: 3, toolTab: nil, anchor: "focus.noise"),

            TourStep(id: "focus.sound",
                     title: "结束提示音",
                     detail: "内置十几种提示音，也可以用自己的音频文件，音量能单独调。",
                     tab: 3, toolTab: nil, anchor: "focus.sound"),

            TourStep(id: "focus.ambience",
                     title: "专注音景",
                     detail: "雨声、海浪、风扇三种环境声，本地合成不联网，戴耳机隔掉杂音更容易进入状态。",
                     tab: 3, toolTab: nil, anchor: "focus.ambience"),

            TourStep(id: "focus.background",
                     title: "背景照片",
                     detail: "挑一张照片当专注背景，系统会自动盖一层黑色蒙版——照片看得见，字也看得清，蒙版深浅可调。",
                     tab: 3, toolTab: nil, anchor: "focus.background"),

            TourStep(id: "done",
                     title: "开始使用",
                     detail: "引导结束，自动回到监控主界面。随时可以在设置里重新播放。",
                     tab: 0, toolTab: nil, anchor: nil)
        ]
    }
}

// MARK: - 挖洞遮罩形状

/// 整窗遮罩 + 圆角矩形挖洞。
/// 通过 animatableData 让洞口的 rect 可插值，配合 spring 平滑移动。
private struct TourMaskShape: Shape {
    var hole: CGRect
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(AnimatablePair(hole.origin.x, hole.origin.y),
                           AnimatablePair(hole.size.width, hole.size.height))
        }
        set {
            hole = CGRect(x: newValue.first.first,
                          y: newValue.first.second,
                          width: newValue.second.first,
                          height: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        if hole.width > 0.5, hole.height > 0.5 {
            path.addRoundedRect(in: hole,
                                cornerSize: CGSize(width: cornerRadius, height: cornerRadius),
                                style: .continuous)
        }
        return path
    }
}

// MARK: - 覆盖层

struct OnboardingOverlay: View {
    @EnvironmentObject var tour: OnboardingController
    @EnvironmentObject var model: AppModel

    @StateObject private var ui = TourUILocalState()

    var body: some View {
        ZStack {
            if tour.isActive {
                content
                    .transition(.opacity)
            }
        }
        .onAppear {
            tour.bind(model)
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: tour.isActive) { _, active in
            if active {
                installKeyMonitor()
            } else {
                removeKeyMonitor()
            }
        }
        .onReceive(TourAnchorStore.shared.$rects) { map in
            tour.updateAnchors(map)
        }
        .onPreferenceChange(TourAnchorKey.self) { map in
            // 覆盖层若被放在锚点视图的祖先位置（例如 ZStack 内），这条路径同样生效
            tour.updateAnchors(map)
        }
    }

    // MARK: 主体

    private var content: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let origin = proxy.frame(in: .global).origin
            let anchor = localRect(from: tour.anchorRect, origin: origin)
            // 有锚点时挖洞并外扩 6pt；无锚点时洞口收缩到窗口中心（尺寸 0，不可见）
            let hole = anchor.map { $0.insetBy(dx: -6, dy: -6) }
                ?? CGRect(x: size.width / 2, y: size.height / 2, width: 0, height: 0)
            let dim: Double = anchor == nil ? 0.7 : 0.55
            let bubblePoint = bubbleOrigin(size: size, anchor: anchor)

            ZStack(alignment: .topLeading) {
                // 遮罩（even-odd 挖洞），拦截所有点击，点击空白不结束
                TourMaskShape(hole: hole, cornerRadius: 12)
                    .fill(Color.black.opacity(dim), style: FillStyle(eoFill: true))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // 防误触：什么都不做
                    }
                    .animation(.easeInOut(duration: 0.25), value: dim)

                // 高亮描边 + 外发光
                if hole.width > 0.5, hole.height > 0.5 {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(model.accentColor, lineWidth: 2)
                        .frame(width: hole.width, height: hole.height)
                        .position(x: hole.midX, y: hole.midY)
                        .shadow(color: model.accentColor.opacity(0.7), radius: 12)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                // 气泡
                if let step = tour.currentStep {
                    bubble(step: step)
                        .background(
                            GeometryReader { g in
                                Color.clear
                                    .preference(key: TourBubbleHeightKey.self, value: g.size.height)
                            }
                        )
                        .offset(x: bubblePoint.x, y: bubblePoint.y)
                        .opacity(tour.bubbleVisible ? 1 : 0)
                        .scaleEffect(tour.bubbleVisible ? 1 : 0.96, anchor: .top)
                        .allowsHitTesting(tour.bubbleVisible)
                        .onPreferenceChange(TourBubbleHeightKey.self) { height in
                            if height > 1, abs(height - ui.bubbleHeight) > 0.5 {
                                ui.bubbleHeight = height
                            }
                        }
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .animation(.spring(response: 0.5, dampingFraction: 0.86), value: tour.anchorRect)
        }
        .ignoresSafeArea()
        .allowsHitTesting(tour.isActive)
    }

    // MARK: 气泡

    private func bubble(step: TourStep) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(step.title)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Text(tour.progressText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Text(step.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("跳过") {
                    tour.finish()
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                if tour.index > 0 {
                    Button("上一步") {
                        tour.previous()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    if tour.isLastStep {
                        tour.finish()
                    } else {
                        tour.next()
                    }
                } label: {
                    Text(tour.isLastStep ? "完成" : "下一步")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(model.accentColor)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 10)
    }

    // MARK: 布局计算

    /// 全局矩形 → 覆盖层内坐标
    private func localRect(from global: CGRect?, origin: CGPoint) -> CGRect? {
        guard let g = global, g.width > 1, g.height > 1 else { return nil }
        return CGRect(x: g.minX - origin.x,
                      y: g.minY - origin.y,
                      width: g.width,
                      height: g.height)
    }

    /// 气泡左上角坐标：优先锚点下方 14pt，下方放不下改放上方，水平居中并夹紧 16pt 边距
    private func bubbleOrigin(size: CGSize, anchor: CGRect?) -> CGPoint {
        let margin: CGFloat = 16
        let gap: CGFloat = 14
        let width: CGFloat = 320
        let height = max(80, ui.bubbleHeight)

        guard let anchor = anchor else {
            return CGPoint(x: max(margin, (size.width - width) / 2),
                           y: max(margin, (size.height - height) / 2))
        }

        var x = anchor.midX - width / 2
        x = min(max(margin, x), max(margin, size.width - width - margin))

        var y = anchor.maxY + gap
        if y + height + margin > size.height {
            let above = anchor.minY - gap - height
            if above >= margin {
                y = above
            } else {
                y = max(margin, size.height - height - margin)
            }
        }
        return CGPoint(x: x, y: y)
    }

    // MARK: 键盘

    private func installKeyMonitor() {
        guard ui.keyMonitor == nil else { return }
        let controller = tour
        ui.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 124:   // →
                Task { @MainActor in controller.next() }
                return nil
            case 123:   // ←
                Task { @MainActor in controller.previous() }
                return nil
            case 53:    // Esc
                Task { @MainActor in controller.finish() }
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = ui.keyMonitor {
            NSEvent.removeMonitor(monitor)
            ui.keyMonitor = nil
        }
    }
}
