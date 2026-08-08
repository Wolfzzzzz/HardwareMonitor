import Foundation

/// 轻量本地化辅助：用于非 SwiftUI 场景（系统通知等）
/// SwiftUI 的 Text/Label/Button 会自动通过 en.lproj/Localizable.strings 本地化，这里只管查不到表的
enum LZ {
    /// 中文环境返回 true；非中文环境（默认英文）返回 false
    static var isChinese: Bool {
        Locale.current.language.languageCode?.identifier.hasPrefix("zh") ?? false
    }

    /// 二选一文案
    static func t(_ zh: String, _ en: String) -> String {
        isChinese ? zh : en
    }
}
