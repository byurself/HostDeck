import Foundation

enum ConnectionState: Equatable {
    case disconnected
    case connecting(String)
    case connected(String)
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .disconnected:
            "Disconnected"
        case .connecting(let name):
            "Connecting \(name)"
        case .connected(let name):
            "Connected \(name)"
        case .failed:
            "Failed"
        }
    }
}
