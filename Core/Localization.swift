import Foundation

/// Uses the application's standard `Localizable.strings` table. Keeping this
/// wrapper for dynamically constructed labels prevents them from bypassing the
/// same macOS localization mechanism that SwiftUI uses for string literals.
enum L10n {
    static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: .main, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
}
