import Foundation
import Observation

@Observable
@MainActor
final class TransferQueueStore {
    var jobs: [TransferJob] = []

    func enqueue(_ job: TransferJob) {
        jobs.insert(job, at: 0)
    }

    func nextQueuedJob() -> TransferJob? {
        jobs.reversed().first { $0.status == .queued }
    }

    func update(_ id: TransferJob.ID, _ mutate: (inout TransferJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&jobs[index])
    }

    func markRunning(_ id: TransferJob.ID) {
        update(id) { job in
            job.status = .running
            job.startedAt = .now
            job.bytesPerSecond = 0
        }
    }

    func updateProgress(_ id: TransferJob.ID, transferredBytes: Int64, totalBytes: Int64) {
        update(id) { job in
            guard job.status == .running else { return }

            job.transferredBytes = transferredBytes
            job.totalBytes = totalBytes

            let startDate = job.startedAt ?? job.createdAt
            let elapsed = max(Date().timeIntervalSince(startDate), 0.1)
            job.bytesPerSecond = max(0, Int64(Double(transferredBytes) / elapsed))
        }
    }

    func markCompleted(_ id: TransferJob.ID) {
        update(id) { job in
            guard job.status == .running || job.status == .queued else { return }
            job.status = .completed
            job.transferredBytes = job.totalBytes
            job.finishedAt = .now
        }
    }

    func markFailed(_ id: TransferJob.ID, message: String) {
        update(id) { job in
            job.status = .failed
            job.errorMessage = message
            job.finishedAt = .now
        }
    }

    func markCancelled(_ id: TransferJob.ID) {
        update(id) { job in
            guard job.canCancel else { return }
            job.status = .cancelled
            job.finishedAt = .now
            job.bytesPerSecond = 0
        }
    }

    func clearCompleted() {
        jobs.removeAll { $0.status == .completed || $0.status == .cancelled }
    }
}
