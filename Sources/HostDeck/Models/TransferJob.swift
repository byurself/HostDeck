import Foundation

struct TransferJob: Identifiable, Codable, Hashable {
    enum Direction: String, Codable {
        case upload
        case download
    }

    enum Status: String, Codable {
        case queued
        case running
        case completed
        case failed
        case cancelled
    }

    var id = UUID()
    var direction: Direction
    var filename: String
    var sourcePath: String
    var destinationPath: String
    var totalBytes: Int64
    var transferredBytes: Int64 = 0
    var bytesPerSecond: Int64 = 0
    var status: Status = .queued
    var createdAt: Date = .now
    var startedAt: Date?
    var finishedAt: Date?
    var errorMessage: String?

    var progress: Double {
        if status == .completed { return 1 }
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(transferredBytes) / Double(totalBytes))
    }

    var canCancel: Bool {
        status == .queued || status == .running
    }

    var speedText: String {
        guard status == .running, bytesPerSecond > 0 else { return "--/s" }
        return "\(Formatters.byteCount.string(fromByteCount: bytesPerSecond))/s"
    }
}

enum WorkspaceKind: String, CaseIterable, Identifiable {
    case terminal
    case files
    case transfers

    var id: String { rawValue }

    var label: String {
        switch self {
        case .terminal:
            "Terminal"
        case .files:
            "SFTP"
        case .transfers:
            "Transfers"
        }
    }

    var systemImage: String {
        switch self {
        case .terminal:
            "terminal"
        case .files:
            "folder"
        case .transfers:
            "arrow.up.arrow.down"
        }
    }
}
