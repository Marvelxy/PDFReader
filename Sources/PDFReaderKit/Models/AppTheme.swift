import SwiftUI

/// App-wide appearance themes.
///
/// Keeps the old Light / Dark behaviors and adds three extra curated
/// themes: Monokai Light, Monokai Dark and Dark Pro.
public enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark
    case monokaiLight
    case monokaiDark
    case darkPro

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .monokaiLight: return "Monokai Light"
        case .monokaiDark: return "Monokai Dark"
        case .darkPro: return "Dark Pro"
        }
    }

    public var symbolName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        case .monokaiLight: return "sunrise"
        case .monokaiDark: return "moon.stars"
        case .darkPro: return "moon.fill"
        }
    }

    public var tooltip: String {
        switch self {
        case .system: return "Follow system appearance"
        case .light: return "Light theme"
        case .dark: return "Dark theme"
        case .monokaiLight: return "Monokai Light — warm paper, pink accent"
        case .monokaiDark: return "Monokai Dark — classic Monokai editor background"
        case .darkPro: return "Dark Pro — true-black contrast theme"
        }
    }

    /// Nil means "follow system".
    public var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light, .monokaiLight: return .light
        case .dark, .monokaiDark, .darkPro: return .dark
        }
    }

    /// Whether PDF pages should be color-inverted (white paper -> dark).
    public var invertsPages: Bool {
        switch self {
        case .dark, .monokaiDark, .darkPro: return true
        case .system, .light, .monokaiLight: return false
        }
    }

    public var accent: Color {
        switch self {
        case .system, .light, .dark: return .accentColor
        case .monokaiLight: return Color(red: 0.97, green: 0.15, blue: 0.45)
        case .monokaiDark: return Color(red: 0.65, green: 0.89, blue: 0.18)
        case .darkPro: return Color(red: 1.0, green: 0.62, blue: 0.04)
        }
    }

    /// Window background used behind the viewer / welcome screen.
    public var windowBackground: Color {
        switch self {
        case .system: return Color(nsColor: .windowBackgroundColor)
        case .light: return Color(nsColor: .windowBackgroundColor)
        case .dark: return Color(nsColor: .windowBackgroundColor)
        case .monokaiLight: return Color(red: 0.98, green: 0.96, blue: 0.92)
        case .monokaiDark: return Color(red: 0.15, green: 0.16, blue: 0.13)
        case .darkPro: return Color.black
        }
    }

    /// Sidebar / status-bar background.
    public var chromeBackground: Color {
        switch self {
        case .system, .light, .dark:
            return Color(nsColor: .controlBackgroundColor)
        case .monokaiLight: return Color(red: 0.94, green: 0.92, blue: 0.84)
        case .monokaiDark: return Color(red: 0.12, green: 0.12, blue: 0.11)
        case .darkPro: return Color(red: 0.04, green: 0.04, blue: 0.05)
        }
    }
}
