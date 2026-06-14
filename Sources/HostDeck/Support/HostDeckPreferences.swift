import SwiftUI

enum HostDeckPreferenceKeys {
    static let appearanceMode = "appearanceMode"
    static let terminalFontFamily = "terminalFontFamily"
    static let terminalFontSize = "terminalFontSize"
    static let terminalCursorBlink = "terminalCursorBlink"
    static let terminalScrollback = "terminalScrollback"
    static let transferListFontFamily = "transferListFontFamily"
    static let transferListFontSize = "transferListFontSize"
    static let serverListFontFamily = "serverListFontFamily"
    static let serverListFontSize = "serverListFontSize"
    static let fileBrowserFontFamily = "fileBrowserFontFamily"
    static let fileBrowserFontSize = "fileBrowserFontSize"
    static let fileTransferSplitRatio = "fileTransferSplitRatio"
    static let maxConcurrentTransfers = "maxConcurrentTransfers"
    static let confirmUnknownHostKeys = "confirmUnknownHostKeys"
}

enum HostDeckPreferenceDefaults {
    static let appearanceMode = AppearanceMode.system
    static let terminalFontFamily = TerminalFontFamily.sfMono
    static let terminalFontSize = 14.0
    static let terminalCursorBlink = true
    static let terminalScrollback = 2_000
    static let transferListFontFamily = InterfaceFontFamily.system
    static let transferListFontSize = 13.0
    static let serverListFontFamily = InterfaceFontFamily.system
    static let serverListFontSize = 13.0
    static let fileBrowserFontFamily = InterfaceFontFamily.monospaced
    static let fileBrowserFontSize = 12.0
    static let fileTransferSplitRatio = 0.5
    static let maxConcurrentTransfers = 3
    static let confirmUnknownHostKeys = true
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system:
            "Sync with OS"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    static func value(for rawValue: String) -> AppearanceMode {
        AppearanceMode(rawValue: rawValue) ?? HostDeckPreferenceDefaults.appearanceMode
    }
}

enum TerminalFontFamily: String, CaseIterable, Identifiable {
    case sfMono
    case menlo
    case monaco
    case courierNew

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sfMono:
            "SF Mono"
        case .menlo:
            "Menlo"
        case .monaco:
            "Monaco"
        case .courierNew:
            "Courier New"
        }
    }

    var cssFamily: String {
        switch self {
        case .sfMono:
            "SFMono-Regular, Menlo, Monaco, Consolas, monospace"
        case .menlo:
            "Menlo, SFMono-Regular, Monaco, Consolas, monospace"
        case .monaco:
            "Monaco, Menlo, SFMono-Regular, Consolas, monospace"
        case .courierNew:
            "Courier New, Courier, monospace"
        }
    }

    static func value(for rawValue: String) -> TerminalFontFamily {
        TerminalFontFamily(rawValue: rawValue) ?? HostDeckPreferenceDefaults.terminalFontFamily
    }
}

enum InterfaceFontFamily: String, CaseIterable, Identifiable {
    case system
    case rounded
    case monospaced
    case serif
    case menlo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system:
            "System"
        case .rounded:
            "Rounded"
        case .monospaced:
            "SF Mono"
        case .serif:
            "New York"
        case .menlo:
            "Menlo"
        }
    }

    func font(size: Double, weight: Font.Weight = .regular) -> Font {
        let size = max(9, min(size, 28))
        switch self {
        case .system:
            return .system(size: size, weight: weight)
        case .rounded:
            return .system(size: size, weight: weight, design: .rounded)
        case .monospaced:
            return .system(size: size, weight: weight, design: .monospaced)
        case .serif:
            return .system(size: size, weight: weight, design: .serif)
        case .menlo:
            return .custom("Menlo", size: size).weight(weight)
        }
    }

    static func value(for rawValue: String) -> InterfaceFontFamily {
        InterfaceFontFamily(rawValue: rawValue) ?? .system
    }
}
