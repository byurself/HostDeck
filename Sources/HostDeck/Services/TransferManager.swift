import Foundation

@MainActor
final class TransferManager {
    private let store: TransferQueueStore

    init(store: TransferQueueStore) {
        self.store = store
    }

    func enqueue(_ job: TransferJob) {
        store.enqueue(job)
        run(jobID: job.id)
    }

    private func run(jobID: TransferJob.ID) {
        store.update(jobID) { job in
            job.status = .running
        }

        Task { @MainActor in
            for step in 1...20 {
                try? await Task.sleep(for: .milliseconds(120))
                store.update(jobID) { job in
                    guard job.status == .running else { return }
                    job.transferredBytes = Int64(Double(job.totalBytes) * (Double(step) / 20.0))
                }
            }

            store.update(jobID) { job in
                if job.status == .running {
                    job.status = .completed
                    job.transferredBytes = job.totalBytes
                }
            }
        }
    }
}
