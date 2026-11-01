import Foundation

/// 版本号统一出口（界面、关于、菜单栏共用一份，避免多处不一致）
///
/// 命名规则：26DF10Q1beta{major}.{minor}.{patch}
/// patch 每次发版自增，major/minor 默认 0.0。
enum AppVersion {
    /// 完整版本号
    static let full = "26DF10Q1beta1.0.9"
    /// 市场版本号（Info.plist CFBundleShortVersionString）
    static let marketing = "1.0.9"
    /// 构建号（Info.plist CFBundleVersion）
    static let build = "109"

    /// 设置页「关于」用的完整展示
    static var display: String { "\(full)（\(marketing) · build \(build)）" }
}
