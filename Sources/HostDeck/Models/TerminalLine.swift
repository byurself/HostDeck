import Foundation

struct TerminalLine: Identifiable, Equatable {
    enum Kind {
        case system
        case command
        case output
        case success
        case error
    }

    let id = UUID()
    var kind: Kind
    var text: String
    var timestamp: Date = .now

    static func system(_ text: String) -> TerminalLine {
        TerminalLine(kind: .system, text: text)
    }

    static func command(_ text: String, prompt: String) -> TerminalLine {
        TerminalLine(kind: .command, text: "\(prompt) \(text)")
    }

    static func output(_ text: String) -> TerminalLine {
        TerminalLine(kind: .output, text: text)
    }

    static func success(_ text: String) -> TerminalLine {
        TerminalLine(kind: .success, text: text)
    }

    static func error(_ text: String) -> TerminalLine {
        TerminalLine(kind: .error, text: text)
    }

    static let welcome: [TerminalLine] = [
        .system("HostDeck terminal"),
        .output("Select a server and connect.")
    ]
}
