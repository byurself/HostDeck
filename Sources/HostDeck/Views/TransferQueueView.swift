import SwiftUI

struct TransferQueueView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        let jobs = appModel.transferStore.jobs

        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Transfer Queue")
                        .font(.headline)
                    Text(summaryText(for: jobs))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    appModel.transferStore.clearCompleted()
                } label: {
                    Label("Clear", systemImage: "checkmark.circle")
                }
                .disabled(!jobs.contains { $0.status == .completed || $0.status == .cancelled })
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)

            Divider()

            if jobs.isEmpty {
                EmptyTransferQueueView {
                    appModel.selectWorkspace(.files)
                }
            } else {
                VStack(spacing: 0) {
                    TransferQueueOverview(jobs: jobs)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)

                    Divider()

                    List(jobs) { job in
                        TransferRow(
                            job: job,
                            onCancel: {
                                appModel.cancelTransfer(job.id)
                            }
                        )
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
            }
        }
    }

    private func summaryText(for jobs: [TransferJob]) -> String {
        guard !jobs.isEmpty else {
            return "Ready for uploads and downloads"
        }

        let runningCount = jobs.filter { $0.status == .running }.count
        let queuedCount = jobs.filter { $0.status == .queued }.count

        if runningCount > 0 {
            return "\(runningCount) active, \(queuedCount) queued"
        }

        if queuedCount > 0 {
            return "\(queuedCount) queued"
        }

        return "\(jobs.count) recent transfer\(jobs.count == 1 ? "" : "s")"
    }
}

private struct TransferRow: View {
    let job: TransferJob
    let onCancel: () -> Void
    @AppStorage(HostDeckPreferenceKeys.transferListFontFamily) private var transferListFontFamily = HostDeckPreferenceDefaults.transferListFontFamily.rawValue
    @AppStorage(HostDeckPreferenceKeys.transferListFontSize) private var transferListFontSize = HostDeckPreferenceDefaults.transferListFontSize

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: iconName)
                .font(.title3.weight(.medium))
                .foregroundStyle(statusColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(job.filename)
                        .font(rowFont(weight: .semibold))
                        .lineLimit(1)

                    Spacer()

                    StatusBadge(status: job.status)
                }

                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)

                HStack(spacing: 14) {
                    Text("\(Formatters.byteCount.string(fromByteCount: job.transferredBytes)) of \(Formatters.byteCount.string(fromByteCount: job.totalBytes))")
                    Text(percentText)
                    Text(directionText)
                    Text(job.speedText)
                    if let errorMessage = job.errorMessage {
                        Text(errorMessage)
                            .lineLimit(1)
                            .foregroundStyle(.red)
                    }
                }
                .font(rowFont(sizeOffset: -2))
                .foregroundStyle(.secondary)
            }

            if job.canCancel {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Cancel Transfer")
            }
        }
        .padding(.vertical, 6)
    }

    private func rowFont(sizeOffset: Double = 0, weight: Font.Weight = .regular) -> Font {
        InterfaceFontFamily.value(for: transferListFontFamily).font(size: transferListFontSize + sizeOffset, weight: weight)
    }

    private var iconName: String {
        switch job.status {
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .cancelled:
            return "xmark.circle"
        case .queued, .running:
            return job.direction == .upload ? "arrow.up.circle" : "arrow.down.circle"
        }
    }

    private var directionText: String {
        job.direction == .upload ? "Upload" : "Download"
    }

    private var percentText: String {
        "\(Int((job.progress * 100).rounded()))%"
    }

    private var statusColor: Color {
        switch job.status {
        case .completed:
            .green
        case .failed:
            .red
        case .cancelled:
            .secondary
        case .queued:
            .secondary
        case .running:
            .accentColor
        }
    }
}

private struct EmptyTransferQueueView: View {
    let onOpenSFTP: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "arrow.up.arrow.down.square")
                    .font(.system(size: 34, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 6) {
                    Text("No Transfers")
                        .font(.title3.weight(.semibold))

                    Text("Upload or download files from the SFTP workspace.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                onOpenSFTP()
            } label: {
                Label("Open SFTP", systemImage: "folder")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct TransferQueueOverview: View {
    let jobs: [TransferJob]

    var body: some View {
        HStack(spacing: 8) {
            QueueMetric(title: "Active", value: count(.running), color: .accentColor)
            QueueMetric(title: "Queued", value: count(.queued), color: .secondary)
            QueueMetric(title: "Done", value: count(.completed), color: .green)
            QueueMetric(title: "Failed", value: count(.failed), color: .red)
            Spacer()
        }
    }

    private func count(_ status: TransferJob.Status) -> Int {
        jobs.filter { $0.status == status }.count
    }
}

private struct QueueMetric: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .fontWeight(.semibold)
        }
        .font(.caption)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct StatusBadge: View {
    let status: TransferJob.Status

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch status {
        case .completed:
            return .green
        case .failed:
            return .red
        case .running:
            return .accentColor
        case .queued, .cancelled:
            return .secondary
        }
    }
}
