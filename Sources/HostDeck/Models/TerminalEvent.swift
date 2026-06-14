import Foundation

struct TerminalEvent: Identifiable, Equatable {
    enum Kind {
        case reset
        case write
    }

    let id = UUID()
    var kind: Kind
    var data: String = ""
}
