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
