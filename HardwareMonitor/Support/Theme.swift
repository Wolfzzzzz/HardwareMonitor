import SwiftUI

/// 完整主题皮肤：每套含深色/浅色两套配色，随外观模式自动切换，互不冲突
struct ThemeConfig: Identifiable {
    let id: String
    let name: String
    let accent: Color
    let gradientDark: [Color]      // 深色背景渐变
    let gradientLight: [Color]     // 浅色背景渐变
    let cardDark: Color
    let cardLight: Color
    let borderDark: Color
    let borderLight: Color

    func gradient(isDark: Bool) -> [Color] { isDark ? gradientDark : gradientLight }
    func card(isDark: Bool) -> Color { isDark ? cardDark : cardLight }
    func border(isDark: Bool) -> Color { isDark ? borderDark : borderLight }
}

enum AppThemes {
    static let all: [ThemeConfig] = [
        ThemeConfig(
            id: "aurora", name: "极光紫",
            accent: Color(red: 0.68, green: 0.46, blue: 0.95),
            gradientDark: [Color(red: 0.07, green: 0.05, blue: 0.15), Color(red: 0.13, green: 0.09, blue: 0.24)],
            gradientLight: [Color(red: 0.96, green: 0.94, blue: 1.00), Color(red: 0.92, green: 0.89, blue: 0.98)],
            cardDark: Color(red: 0.15, green: 0.11, blue: 0.25),
            cardLight: Color.white,
            borderDark: Color(red: 0.26, green: 0.20, blue: 0.40),
            borderLight: Color(red: 0.84, green: 0.79, blue: 0.94)
        ),
        ThemeConfig(
            id: "ocean", name: "深空蓝",
            accent: Color(red: 0.33, green: 0.58, blue: 0.95),
            gradientDark: [Color(red: 0.04, green: 0.09, blue: 0.18), Color(red: 0.08, green: 0.15, blue: 0.27)],
            gradientLight: [Color(red: 0.94, green: 0.97, blue: 1.00), Color(red: 0.90, green: 0.94, blue: 0.98)],
            cardDark: Color(red: 0.10, green: 0.17, blue: 0.29),
            cardLight: Color.white,
            borderDark: Color(red: 0.18, green: 0.28, blue: 0.44),
            borderLight: Color(red: 0.80, green: 0.87, blue: 0.95)
        ),
        ThemeConfig(
            id: "forest", name: "森林绿",
            accent: Color(red: 0.28, green: 0.72, blue: 0.48),
            gradientDark: [Color(red: 0.04, green: 0.11, blue: 0.08), Color(red: 0.07, green: 0.18, blue: 0.13)],
            gradientLight: [Color(red: 0.94, green: 0.98, blue: 0.95), Color(red: 0.90, green: 0.96, blue: 0.92)],
            cardDark: Color(red: 0.08, green: 0.20, blue: 0.14),
            cardLight: Color.white,
            borderDark: Color(red: 0.16, green: 0.32, blue: 0.24),
            borderLight: Color(red: 0.78, green: 0.90, blue: 0.83)
        ),
        ThemeConfig(
            id: "magma", name: "熔岩橙",
            accent: Color(red: 0.95, green: 0.55, blue: 0.25),
            gradientDark: [Color(red: 0.16, green: 0.07, blue: 0.04), Color(red: 0.24, green: 0.11, blue: 0.05)],
            gradientLight: [Color(red: 1.00, green: 0.96, blue: 0.93), Color(red: 0.98, green: 0.92, blue: 0.86)],
            cardDark: Color(red: 0.26, green: 0.13, blue: 0.07),
            cardLight: Color.white,
            borderDark: Color(red: 0.42, green: 0.24, blue: 0.13),
            borderLight: Color(red: 0.94, green: 0.84, blue: 0.74)
        ),
        ThemeConfig(
            id: "sakura", name: "樱花粉",
            accent: Color(red: 0.95, green: 0.50, blue: 0.62),
            gradientDark: [Color(red: 0.15, green: 0.06, blue: 0.10), Color(red: 0.22, green: 0.10, blue: 0.16)],
            gradientLight: [Color(red: 1.00, green: 0.95, blue: 0.97), Color(red: 0.98, green: 0.90, blue: 0.93)],
            cardDark: Color(red: 0.24, green: 0.12, blue: 0.18),
            cardLight: Color.white,
            borderDark: Color(red: 0.38, green: 0.22, blue: 0.30),
            borderLight: Color(red: 0.95, green: 0.82, blue: 0.87)
        ),
        ThemeConfig(
            id: "graphite", name: "石墨黑",
            accent: Color(red: 0.55, green: 0.60, blue: 0.70),
            gradientDark: [Color(red: 0.05, green: 0.06, blue: 0.08), Color(red: 0.09, green: 0.10, blue: 0.13)],
            gradientLight: [Color(red: 0.96, green: 0.97, blue: 0.98), Color(red: 0.92, green: 0.93, blue: 0.95)],
            cardDark: Color(red: 0.11, green: 0.12, blue: 0.16),
            cardLight: Color.white,
            borderDark: Color(red: 0.20, green: 0.22, blue: 0.28),
            borderLight: Color(red: 0.82, green: 0.84, blue: 0.88)
        ),
    ]

    static func byID(_ id: String) -> ThemeConfig {
        all.first { $0.id == id } ?? all[0]
    }
}
