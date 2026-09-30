import AppKit
import SwiftUI

/// Highlight color choices for text markup annotations.
/// Centralizes the NSColor / SwiftUI.Color mapping so highlight,
/// underline and strike-through all share the same palette.
public enum HighlightColor: String, CaseIterable, Identifiable, Codable {
    case yellow
    case green
    case blue
    case pink
    case orange
    case purple
    case red
    case teal
    case gray
    case custom

    public var id: String { rawValue }

    /// Fixed palette shown in menus and pickers. `.custom` is handled
    /// separately via `PDFReaderState.customHighlightColor`.
    public static var presets: [HighlightColor] {
        allCases.filter { $0 != .custom }
    }

    public var displayName: String {
        switch self {
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .pink: return "Pink"
        case .orange: return "Orange"
        case .purple: return "Purple"
        case .red: return "Red"
        case .teal: return "Teal"
        case .gray: return "Gray"
        case .custom: return "Custom"
        }
    }

    public var nsColor: NSColor {
        switch self {
        case .yellow: return NSColor(red: 1.0, green: 0.95, blue: 0.45, alpha: 1.0)
        case .green: return NSColor(red: 0.65, green: 0.95, blue: 0.65, alpha: 1.0)
        case .blue: return NSColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 1.0)
        case .pink: return NSColor(red: 1.0, green: 0.7, blue: 0.8, alpha: 1.0)
        case .orange: return NSColor(red: 1.0, green: 0.8, blue: 0.5, alpha: 1.0)
        case .purple: return NSColor(red: 0.8, green: 0.75, blue: 1.0, alpha: 1.0)
        case .red: return NSColor(red: 1.0, green: 0.55, blue: 0.55, alpha: 1.0)
        case .teal: return NSColor(red: 0.5, green: 0.9, blue: 0.85, alpha: 1.0)
        case .gray: return NSColor(red: 0.8, green: 0.8, blue: 0.82, alpha: 1.0)
        // Never used directly — resolve via
        // `PDFReaderState.resolvedHighlightNSColor`.
        case .custom: return .clear
        }
    }

    public var swiftUIColor: Color {
        Color(nsColor)
    }
}

/// Active annotation tool selected in the toolbar.
public enum AnnotationMode: String, CaseIterable, Identifiable {
    case select
    case highlight
    case underline
    case strikeThrough
    case note

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .select: return "Select"
        case .highlight: return "Highlight"
        case .underline: return "Underline"
        case .strikeThrough: return "Strikethrough"
        case .note: return "Note"
        }
    }

    public var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .highlight: return "highlighter"
        case .underline: return "underline"
        case .strikeThrough: return "strikethrough"
        case .note: return "note.text"
        }
    }
}
