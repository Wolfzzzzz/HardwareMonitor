import SwiftUI

/// 完整主题皮肤：渐变背景 + 卡片色 + 强调色 + 图标色调
struct ThemeConfig: Identifiable {
    let id: String
    let name: String
    let accent: Color
    let gradient: [Color]       // 背景渐变（上→下）
    let card: Color             // 卡片底色
    let cardBorder: Color       // 卡片描边
    let iconTint: Color         // 装饰图标色调
}

enum AppThemes {
    static let all: [ThemeConfig] = [
        ThemeConfig(
            id: "aurora", name: "极光紫",
            accent: Color(red: 0.72, green: 0.50, blue: 1.00),
            gradient: [Color(red: 0.07, green: 0.05, blue: 0.15), Color(red: 0.13, green: 0.09, blue: 0.24)],
            card: Color(red: 0.15, green: 0.11, blue: 0.25),
            cardBorder: Color(red: 0.26, green: 0.20, blue: 0.40),
            iconTint: Color(red: 0.82, green: 0.66, blue: 1.00)
        ),
        ThemeConfig(
            id: "ocean", name: "深空蓝",
            accent: Color(red: 0.35, green: 0.62, blue: 1.00),
            gradient: [Color(red: 0.04, green: 0.09, blue: 0.18), Color(red: 0.08, green: 0.15, blue: 0.27)],
            card: Color(red: 0.10, green: 0.17, blue: 0.29),
            cardBorder: Color(red: 0.18, green: 0.28, blue: 0.44),
            iconTint: Color(red: 0.55, green: 0.78, blue: 1.00)
        ),
        ThemeConfig(
            id: "forest", name: "森林绿",
            accent: Color(red: 0.30, green: 0.80, blue: 0.55),
            gradient: [Color(red: 0.04, green: 0.11, blue: 0.08), Color(red: 0.07, green: 0.18, blue: 0.13)],
            card: Color(red: 0.08, green: 0.20, blue: 0.14),
            cardBorder: Color(red: 0.16, green: 0.32, blue: 0.24),
            iconTint: Color(red: 0.55, green: 0.95, blue: 0.72)
        ),
        ThemeConfig(
            id: "magma", name: "熔岩橙",
            accent: Color(red: 1.00, green: 0.62, blue: 0.30),
            gradient: [Color(red: 0.16, green: 0.07, blue: 0.04), Color(red: 0.24, green: 0.11, blue: 0.05)],
            card: Color(red: 0.26, green: 0.13, blue: 0.07),
            cardBorder: Color(red: 0.42, green: 0.24, blue: 0.13),
            iconTint: Color(red: 1.00, green: 0.75, blue: 0.48)
        ),
        ThemeConfig(
            id: "sakura", name: "樱花粉",
            accent: Color(red: 1.00, green: 0.55, blue: 0.68),
            gradient: [Color(red: 0.15, green: 0.06, blue: 0.10), Color(red: 0.22, green: 0.10, blue: 0.16)],
            card: Color(red: 0.24, green: 0.12, blue: 0.18),
            cardBorder: Color(red: 0.38, green: 0.22, blue: 0.30),
            iconTint: Color(red: 1.00, green: 0.70, blue: 0.80)
        ),
        ThemeConfig(
            id: "graphite", name: "石墨黑",
            accent: Color(red: 0.60, green: 0.65, blue: 0.75),
            gradient: [Color(red: 0.05, green: 0.06, blue: 0.08), Color(red: 0.09, green: 0.10, blue: 0.13)],
            card: Color(red: 0.11, green: 0.12, blue: 0.16),
            cardBorder: Color(red: 0.20, green: 0.22, blue: 0.28),
            iconTint: Color(red: 0.72, green: 0.77, blue: 0.86)
        ),
    ]

    static func byID(_ id: String) -> ThemeConfig {
        all.first { $0.id == id } ?? all[0]
    }
}
