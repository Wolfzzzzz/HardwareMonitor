import SwiftUI

@main
struct HardwareMonitorApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
                .onAppear { model.start() }
        } label: {
            Label("硬件监控", systemImage: model.alertActive ? "flame.fill" : "thermometer.medium")
                .onAppear { model.start() }
                #if DEBUG
                .background(SmokeTestDriver(model: model))
                #endif
        }
        .menuBarExtraStyle(.window)

        Window("硬件监控", id: "main") {
            MainWindowView()
                .environmentObject(model)
        }
        .defaultSize(width: 820, height: 640)

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 460)
        }
    }
}

#if DEBUG
/// 冒烟测试驱动：仅当环境变量 HWMON_SMOKE=1 时生效。
/// 依次打开主窗口、遍历 4 个标签页、进入/退出专注全屏，用于验证渲染路径不崩溃。
struct SmokeTestDriver: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                guard ProcessInfo.processInfo.environment["HWMON_SMOKE"] == "1" else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    openWindow(id: "main")
                    var delay = 1.8
                    for tab in 0...3 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            model.mainTab = tab
                            print("HWMON_SMOKE tab=\(tab)")
                        }
                        delay += 1.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        print("HWMON_SMOKE enter fullscreen")
                        model.enterFocusFullScreen()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1.5) {
                        model.exitFocusFullScreen()
                        print("HWMON_SMOKE_OK")
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay + 2.5) {
                        NSApp.terminate(nil)
                    }
                }
            }
    }
}
#endif
