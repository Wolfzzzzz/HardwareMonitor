import SwiftUI
import AppKit

/// 无边框置顶悬浮小窗（可拖动、可缩放、深浅色自适应、圆角毛玻璃）
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var hosting: NSHostingView<AnyView>?

    /// 显示悬浮窗（已存在则前置）
    func show<Content: View>(@ViewBuilder content: () -> Content) {
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        let view = AnyView(content())
        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
                            styleMask: [.borderless, .fullSizeContentView, .resizable],
                            backing: .buffered,
                            defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 360, height: 480)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        let container = NSVisualEffectView()
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 18
        container.layer?.masksToBounds = true

        let wrapper = NSView()
        wrapper.wantsLayer = true
        wrapper.layer?.cornerRadius = 18
        wrapper.layer?.masksToBounds = true
        wrapper.addSubview(hosting)
        hosting.frame = wrapper.bounds
        hosting.autoresizingMask = [.width, .height]

        container.addSubview(wrapper)
        wrapper.frame = container.bounds
        wrapper.autoresizingMask = [.width, .height]

        panel.contentView = container
        self.panel = panel
        self.hosting = hosting

        // 初始位置：主屏右上角
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: vf.maxX - size.width - 16, y: vf.maxY - size.height - 16))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle<Content: View>(isVisible: Bool, @ViewBuilder content: () -> Content) {
        if isVisible { show(content: content) } else { hide() }
    }

    func windowWillClose(_ notification: Notification) {
        // 通知 UI 同步开关状态
        NotificationCenter.default.post(name: .floatingPanelClosed, object: nil)
    }
}

extension Notification.Name {
    static let floatingPanelClosed = Notification.Name("hwmon.floatingPanelClosed")
}
