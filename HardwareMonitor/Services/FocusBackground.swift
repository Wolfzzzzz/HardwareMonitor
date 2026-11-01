import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 专注界面背景照片（版本 26DF10Q1beta1.0.9 新增）
///
/// 规则：照片自动叠加一层可调透明度的黑色蒙版，保证照片可见的同时文字依然清晰；
/// 蒙版下限 0.25，避免调太低导致白色大字在亮照片上看不清。
@MainActor
final class FocusBackground: ObservableObject {

    // MARK: 持久化键

    private enum Key {
        static let enabled = "focusBgEnabled"
        static let overlay = "focusBgOverlay"
        static let file = "focusBgFile"
    }

    /// 图片目录：~/Library/Application Support/HardwareMonitor/Backgrounds
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("HardwareMonitor/Backgrounds", isDirectory: true)
    }

    // MARK: 状态

    /// 是否启用背景照片
    @Published var enabled: Bool = true {
        didSet { UserDefaults.standard.set(enabled, forKey: Key.enabled) }
    }

    /// 黑色蒙版不透明度（0.25...0.9，越大越暗、字越清晰）
    /// 注意：不要在 didSet 里给自身赋值——@Published 会在赋值后再次进入 didSet，造成无限递归爆栈。
    /// 范围限制由 init 与 UI 的 Slider 共同保证。
    @Published var overlayOpacity: Double = 0.52 {
        didSet { UserDefaults.standard.set(overlayOpacity, forKey: Key.overlay) }
    }

    /// 当前照片文件名（存在上面的目录里）
    @Published private(set) var fileName: String?

    /// 解码后的图片缓存（避免每帧重新读盘）
    @Published private(set) var image: NSImage?

    var hasImage: Bool { image != nil }

    /// 界面展示用的说明文字
    var statusText: String {
        guard enabled else { return "未启用背景照片" }
        guard let fileName else { return "尚未选择照片" }
        return fileName
    }

    // MARK: 初始化

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [Key.enabled: true, Key.overlay: 0.52])
        enabled = d.bool(forKey: Key.enabled)
        overlayOpacity = min(0.9, max(0.25, d.double(forKey: Key.overlay)))
        if let name = d.string(forKey: Key.file) {
            fileName = name
            image = Self.loadImage(named: name)
        }
    }

    // MARK: 选择 / 移除

    /// 选择本地照片（png / jpg / heic / tiff / gif），复制进应用支持目录
    func importImage() {
        let panel = NSOpenPanel()
        panel.title = "选择专注界面背景照片"
        panel.prompt = "使用这张照片"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.image]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
        let target = Self.directory.appendingPathComponent("focus-background.\(ext)")

        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            // 换图时先清掉旧文件，避免目录堆积多份大图
            if let old = fileName {
                try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(old))
            }
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: url, to: target)
        } catch {
            NSSound.beep()
            return
        }

        fileName = target.lastPathComponent
        UserDefaults.standard.set(target.lastPathComponent, forKey: Key.file)
        image = Self.loadImage(named: target.lastPathComponent)
        enabled = true
    }

    /// 移除背景照片
    func removeImage() {
        if let name = fileName {
            try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(name))
        }
        fileName = nil
        image = nil
        UserDefaults.standard.removeObject(forKey: Key.file)
    }

    // MARK: 读取

    private static func loadImage(named name: String) -> NSImage? {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }
}

// MARK: - 背景层视图

/// 照片 + 自动黑色蒙版 + 轻微暗角：盖在界面最底层，不影响交互
struct FocusBackgroundLayer: View {
    @ObservedObject var background: FocusBackground

    var body: some View {
        GeometryReader { geo in
            if background.enabled, let img = background.image {
                ZStack {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()

                    // 主体黑色蒙版（透明度可调，下限 0.25）
                    Color.black.opacity(background.overlayOpacity)

                    // 边缘再压暗一点，四角不抢字
                    RadialGradient(
                        colors: [.clear, .black.opacity(0.28)],
                        center: .center,
                        startRadius: 0,
                        endRadius: max(geo.size.width, geo.size.height) * 0.72
                    )
                }
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }
}
