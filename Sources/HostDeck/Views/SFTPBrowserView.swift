import SwiftUI
import AppKit

struct SFTPBrowserView: View {
    @Bindable var appModel: AppModel
    @State private var selectedLocalFileID: LocalFile.ID?
    @State private var selectedRemoteFileID: RemoteFile.ID?
    @State private var selectedLocalFileIDs: Set<LocalFile.ID> = []
    @State private var selectedRemoteFileIDs: Set<RemoteFile.ID> = []
    @State private var localPathText = ""
    @State private var remotePathText = ""
    @State private var pendingConflict: TransferConflict?
    @State private var isTransferQueueExpanded = true
    @AppStorage(HostDeckPreferenceKeys.fileTransferSplitRatio) private var filePaneSplitRatio = HostDeckPreferenceDefaults.fileTransferSplitRatio

    @MainActor private var selectedLocalFiles: [LocalFile] {
        appModel.localFiles.filter { selectedLocalFileIDs.contains($0.id) }
    }

    @MainActor private var selectedRemoteFiles: [RemoteFile] {
        appModel.remoteFiles.filter { selectedRemoteFileIDs.contains($0.id) && $0.name != ".." }
    }

    @MainActor private var localFilePane: some View {
        FilePane(
            title: NSUserName(),
            pathText: $localPathText,
            systemImage: "internaldrive",
            rows: appModel.localFiles.map(FilePaneRow.local),
            selectedIDs: $selectedLocalFileIDs,
            activeSelectedID: $selectedLocalFileID,
            showsPermissions: false,
            columnWidthsStorageKey: FilePaneColumnWidths.StorageKey.local,
            emptyTitle: "No Local Files",
            emptyDescription: appModel.localDirectoryError ?? "This folder is empty.",
            onPathSubmit: {
                appModel.openLocalPath(localPathText)
                localPathText = appModel.localPath.path
            },
            onGoUp: {
                appModel.goUpLocalDirectory()
                localPathText = appModel.localPath.path
            },
            onRefresh: appModel.refreshLocalDirectory,
            onSelect: { row in
                selectedLocalFileID = row.selectableID
            },
            onOpen: { row in
                switch row {
                case .local(let file):
                    if file.kind == .directory {
                        appModel.openLocalFile(file)
                    } else {
                        beginUpload(file)
                    }
                case .remote:
                    break
                }
                localPathText = appModel.localPath.path
            }
        )
    }

    @MainActor private var remoteFilePane: some View {
        FilePane(
            title: appModel.selectedServer?.host ?? "Remote",
            pathText: $remotePathText,
            systemImage: "network",
            rows: appModel.remoteFiles.map(FilePaneRow.remote),
            selectedIDs: $selectedRemoteFileIDs,
            activeSelectedID: $selectedRemoteFileID,
            showsPermissions: true,
            columnWidthsStorageKey: FilePaneColumnWidths.StorageKey.remote,
            emptyTitle: "No Remote Files",
            emptyDescription: appModel.connectionState.isConnected ? "This folder is empty." : "Connect to browse remote files.",
            onPathSubmit: {
                Task {
                    await appModel.openRemotePath(remotePathText)
                    remotePathText = appModel.remotePath
                }
            },
            onGoUp: {
                Task {
                    await appModel.goUpRemoteDirectory()
                    remotePathText = appModel.remotePath
                }
            },
            onRefresh: {
                Task {
                    await appModel.refreshRemoteDirectory()
                    remotePathText = appModel.remotePath
                }
            },
            onSelect: { row in
                selectedRemoteFileID = row.selectableID
            },
            onOpen: { row in
                switch row {
                case .remote(let file):
                    if file.kind == .directory {
                        Task {
                            await appModel.openRemoteFile(file)
                            remotePathText = appModel.remotePath
                        }
                    } else {
                        beginDownload(file)
                    }
                case .local:
                    break
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    beginUpload(selectedLocalFiles)
                } label: {
                    Label(selectedLocalFiles.count > 1 ? "Upload \(selectedLocalFiles.count)" : "Upload", systemImage: "arrow.right")
                }
                .disabled(selectedLocalFiles.isEmpty)

                Button {
                    beginDownload(selectedRemoteFiles)
                } label: {
                    Label(selectedRemoteFiles.count > 1 ? "Download \(selectedRemoteFiles.count)" : "Download", systemImage: "arrow.left")
                }
                .disabled(selectedRemoteFiles.isEmpty)

                Spacer()

                Button {
                    Task { await appModel.prepareFileTransferWorkspace() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Both Panes")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)

            Divider()

            FileTransferSplitView(splitRatio: $filePaneSplitRatio) {
                localFilePane
            } trailing: {
                remoteFilePane
            }

            if !appModel.visibleTransferJobs.isEmpty {
                Divider()
                TransferQueueStrip(
                    jobs: appModel.visibleTransferJobs,
                    isExpanded: $isTransferQueueExpanded,
                    onCancel: { job in
                        appModel.cancelTransfer(job.id)
                    }
                )
            }
        }
        .onAppear {
            appModel.refreshLocalDirectory()
            localPathText = appModel.localPath.path
            remotePathText = appModel.remotePath
        }
        .onChange(of: appModel.localPath) {
            localPathText = appModel.localPath.path
            selectedLocalFileID = nil
            selectedLocalFileIDs.removeAll()
        }
        .onChange(of: appModel.remotePath) {
            remotePathText = appModel.remotePath
            selectedRemoteFileID = nil
            selectedRemoteFileIDs.removeAll()
        }
        .onChange(of: appModel.selectedServerID) {
            selectedRemoteFileID = nil
            selectedRemoteFileIDs.removeAll()
            remotePathText = appModel.remotePath
        }
        .sheet(item: $pendingConflict) { conflict in
            TransferConflictSheet(
                conflict: conflict,
                onCancel: {
                    pendingConflict = nil
                },
                onSkip: {
                    pendingConflict = nil
                    skipTransfer(conflict)
                },
                onReplace: {
                    pendingConflict = nil
                    commitTransfer(conflict, renamedName: nil)
                },
                onRename: {
                    pendingConflict = nil
                    commitTransfer(conflict, renamedName: conflict.suggestedName)
                }
            )
        }
    }

    @MainActor private func beginUpload(_ file: LocalFile?) {
        guard let file else { return }
        beginUpload([file])
    }

    @MainActor private func beginUpload(_ files: [LocalFile]) {
        processUpload(files, existingNames: Set(appModel.remoteFiles.map(\.name)))
    }

    @MainActor private func processUpload(_ files: [LocalFile], existingNames: Set<String>) {
        var remainingFiles = files
        var destinationNames = existingNames

        while !remainingFiles.isEmpty {
            let file = remainingFiles.removeFirst()

            if destinationNames.contains(file.name) {
                pendingConflict = TransferConflict(
                    direction: .upload,
                    localFile: file,
                    remoteFile: nil,
                    originalName: file.name,
                    suggestedName: uniqueTransferName(for: file.name, existingNames: destinationNames),
                    remainingLocalFiles: remainingFiles,
                    remainingRemoteFiles: [],
                    existingNames: destinationNames
                )
                return
            }

            appModel.queueUpload(file)
            destinationNames.insert(file.name)
        }
    }

    @MainActor private func beginDownload(_ file: RemoteFile?) {
        guard let file, file.name != ".." else { return }
        beginDownload([file])
    }

    @MainActor private func beginDownload(_ files: [RemoteFile]) {
        processDownload(files.filter { $0.name != ".." }, existingNames: Set(appModel.localFiles.map(\.name)))
    }

    @MainActor private func processDownload(_ files: [RemoteFile], existingNames: Set<String>) {
        var remainingFiles = files
        var destinationNames = existingNames

        while !remainingFiles.isEmpty {
            let file = remainingFiles.removeFirst()

            if destinationNames.contains(file.name) {
                pendingConflict = TransferConflict(
                    direction: .download,
                    localFile: nil,
                    remoteFile: file,
                    originalName: file.name,
                    suggestedName: uniqueTransferName(for: file.name, existingNames: destinationNames),
                    remainingLocalFiles: [],
                    remainingRemoteFiles: remainingFiles,
                    existingNames: destinationNames
                )
                return
            }

            appModel.queueDownload(file)
            destinationNames.insert(file.name)
        }
    }

    @MainActor private func commitTransfer(_ conflict: TransferConflict, renamedName: String?) {
        switch conflict.direction {
        case .upload:
            appModel.queueUpload(conflict.localFile, remoteName: renamedName)
            continueUpload(after: conflict, destinationName: renamedName ?? conflict.originalName)
        case .download:
            appModel.queueDownload(conflict.remoteFile, localName: renamedName)
            continueDownload(after: conflict, destinationName: renamedName ?? conflict.originalName)
        }
    }

    @MainActor private func skipTransfer(_ conflict: TransferConflict) {
        appModel.noteTransferSkipped(conflict.originalName)

        switch conflict.direction {
        case .upload:
            processUpload(conflict.remainingLocalFiles, existingNames: conflict.existingNames)
        case .download:
            processDownload(conflict.remainingRemoteFiles, existingNames: conflict.existingNames)
        }
    }

    @MainActor private func continueUpload(after conflict: TransferConflict, destinationName: String) {
        var destinationNames = conflict.existingNames
        destinationNames.insert(destinationName)
        processUpload(conflict.remainingLocalFiles, existingNames: destinationNames)
    }

    @MainActor private func continueDownload(after conflict: TransferConflict, destinationName: String) {
        var destinationNames = conflict.existingNames
        destinationNames.insert(destinationName)
        processDownload(conflict.remainingRemoteFiles, existingNames: destinationNames)
    }

    private func uniqueTransferName(for name: String, existingNames: Set<String>) -> String {
        let nsName = name as NSString
        let stem = nsName.deletingPathExtension
        let pathExtension = nsName.pathExtension
        let base = stem.isEmpty ? name : stem
        let suffix = pathExtension.isEmpty ? "" : ".\(pathExtension)"

        var candidate = "\(base) copy\(suffix)"
        var index = 2
        while existingNames.contains(candidate) {
            candidate = "\(base) copy \(index)\(suffix)"
            index += 1
        }
        return candidate
    }
}

struct SFTPDetachedWindowView: View {
    @Bindable var appModel: AppModel
    @Bindable var session: FileTransferWindowSession
    @State private var selectedLocalFileID: LocalFile.ID?
    @State private var selectedRemoteFileID: RemoteFile.ID?
    @State private var selectedLocalFileIDs: Set<LocalFile.ID> = []
    @State private var selectedRemoteFileIDs: Set<RemoteFile.ID> = []
    @State private var localPathText = ""
    @State private var remotePathText = ""
    @State private var pendingConflict: TransferConflict?
    @State private var isTransferQueueExpanded = true
    @AppStorage(HostDeckPreferenceKeys.fileTransferSplitRatio) private var filePaneSplitRatio = HostDeckPreferenceDefaults.fileTransferSplitRatio

    @MainActor private var selectedLocalFiles: [LocalFile] {
        session.localFiles.filter { selectedLocalFileIDs.contains($0.id) }
    }

    @MainActor private var selectedRemoteFiles: [RemoteFile] {
        session.remoteFiles.filter { selectedRemoteFileIDs.contains($0.id) && $0.name != ".." }
    }

    @MainActor private var localFilePane: some View {
        FilePane(
            title: NSUserName(),
            pathText: $localPathText,
            systemImage: "internaldrive",
            rows: session.localFiles.map(FilePaneRow.local),
            selectedIDs: $selectedLocalFileIDs,
            activeSelectedID: $selectedLocalFileID,
            showsPermissions: false,
            columnWidthsStorageKey: FilePaneColumnWidths.StorageKey.local,
            emptyTitle: "No Local Files",
            emptyDescription: session.localDirectoryError ?? "This folder is empty.",
            onPathSubmit: {
                session.openLocalPath(localPathText)
                localPathText = session.localPath.path
            },
            onGoUp: {
                session.goUpLocalDirectory()
                localPathText = session.localPath.path
            },
            onRefresh: session.refreshLocalDirectory,
            onSelect: { row in
                selectedLocalFileID = row.selectableID
            },
            onOpen: { row in
                switch row {
                case .local(let file):
                    if file.kind == .directory {
                        session.openLocalFile(file)
                    } else {
                        beginUpload(file)
                    }
                case .remote:
                    break
                }
                localPathText = session.localPath.path
            }
        )
    }

    @MainActor private var remoteFilePane: some View {
        FilePane(
            title: session.profile.host,
            pathText: $remotePathText,
            systemImage: "network",
            rows: session.remoteFiles.map(FilePaneRow.remote),
            selectedIDs: $selectedRemoteFileIDs,
            activeSelectedID: $selectedRemoteFileID,
            showsPermissions: true,
            columnWidthsStorageKey: FilePaneColumnWidths.StorageKey.remote,
            emptyTitle: "No Remote Files",
            emptyDescription: session.connectionState.isConnected ? "This folder is empty." : "Connect to browse remote files.",
            onPathSubmit: {
                Task {
                    await session.openRemotePath(remotePathText)
                    remotePathText = session.remotePath
                }
            },
            onGoUp: {
                Task {
                    await session.goUpRemoteDirectory()
                    remotePathText = session.remotePath
                }
            },
            onRefresh: {
                Task {
                    await session.refreshRemoteDirectory()
                    remotePathText = session.remotePath
                }
            },
            onSelect: { row in
                selectedRemoteFileID = row.selectableID
            },
            onOpen: { row in
                switch row {
                case .remote(let file):
                    if file.kind == .directory {
                        Task {
                            await session.openRemoteFile(file)
                            remotePathText = session.remotePath
                        }
                    } else {
                        beginDownload(file)
                    }
                case .local:
                    break
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    beginUpload(selectedLocalFiles)
                } label: {
                    Label(selectedLocalFiles.count > 1 ? "Upload \(selectedLocalFiles.count)" : "Upload", systemImage: "arrow.right")
                }
                .disabled(selectedLocalFiles.isEmpty)

                Button {
                    beginDownload(selectedRemoteFiles)
                } label: {
                    Label(selectedRemoteFiles.count > 1 ? "Download \(selectedRemoteFiles.count)" : "Download", systemImage: "arrow.left")
                }
                .disabled(selectedRemoteFiles.isEmpty)

                Spacer()

                Button {
                    Task {
                        session.refreshLocalDirectory()
                        await session.refreshRemoteDirectory()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Both Panes")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)

            Divider()

            FileTransferSplitView(splitRatio: $filePaneSplitRatio) {
                localFilePane
            } trailing: {
                remoteFilePane
            }

            if !appModel.visibleTransferJobs.isEmpty {
                Divider()
                TransferQueueStrip(
                    jobs: appModel.visibleTransferJobs,
                    isExpanded: $isTransferQueueExpanded,
                    onCancel: { job in
                        appModel.cancelTransfer(job.id)
                    }
                )
            }
        }
        .task(id: session.id) {
            await session.connect()
            localPathText = session.localPath.path
            remotePathText = session.remotePath
        }
        .onChange(of: session.localPath) {
            localPathText = session.localPath.path
            selectedLocalFileID = nil
            selectedLocalFileIDs.removeAll()
        }
        .onChange(of: session.remotePath) {
            remotePathText = session.remotePath
            selectedRemoteFileID = nil
            selectedRemoteFileIDs.removeAll()
        }
        .sheet(item: $pendingConflict) { conflict in
            TransferConflictSheet(
                conflict: conflict,
                onCancel: {
                    pendingConflict = nil
                },
                onSkip: {
                    pendingConflict = nil
                    skipTransfer(conflict)
                },
                onReplace: {
                    pendingConflict = nil
                    commitTransfer(conflict, renamedName: nil)
                },
                onRename: {
                    pendingConflict = nil
                    commitTransfer(conflict, renamedName: conflict.suggestedName)
                }
            )
        }
    }

    @MainActor private func beginUpload(_ file: LocalFile?) {
        guard let file else { return }
        beginUpload([file])
    }

    @MainActor private func beginUpload(_ files: [LocalFile]) {
        processUpload(files, existingNames: Set(session.remoteFiles.map(\.name)))
    }

    @MainActor private func processUpload(_ files: [LocalFile], existingNames: Set<String>) {
        var remainingFiles = files
        var destinationNames = existingNames

        while !remainingFiles.isEmpty {
            let file = remainingFiles.removeFirst()

            if destinationNames.contains(file.name) {
                pendingConflict = TransferConflict(
                    direction: .upload,
                    localFile: file,
                    remoteFile: nil,
                    originalName: file.name,
                    suggestedName: uniqueTransferName(for: file.name, existingNames: destinationNames),
                    remainingLocalFiles: remainingFiles,
                    remainingRemoteFiles: [],
                    existingNames: destinationNames
                )
                return
            }

            appModel.queueUpload(file, serverID: session.profile.id, remoteDirectory: session.remotePath)
            destinationNames.insert(file.name)
        }
    }

    @MainActor private func beginDownload(_ file: RemoteFile?) {
        guard let file, file.name != ".." else { return }
        beginDownload([file])
    }

    @MainActor private func beginDownload(_ files: [RemoteFile]) {
        processDownload(files.filter { $0.name != ".." }, existingNames: Set(session.localFiles.map(\.name)))
    }

    @MainActor private func processDownload(_ files: [RemoteFile], existingNames: Set<String>) {
        var remainingFiles = files
        var destinationNames = existingNames

        while !remainingFiles.isEmpty {
            let file = remainingFiles.removeFirst()

            if destinationNames.contains(file.name) {
                pendingConflict = TransferConflict(
                    direction: .download,
                    localFile: nil,
                    remoteFile: file,
                    originalName: file.name,
                    suggestedName: uniqueTransferName(for: file.name, existingNames: destinationNames),
                    remainingLocalFiles: [],
                    remainingRemoteFiles: remainingFiles,
                    existingNames: destinationNames
                )
                return
            }

            appModel.queueDownload(
                file,
                serverID: session.profile.id,
                remoteDirectory: session.remotePath,
                localDirectory: session.localPath
            )
            destinationNames.insert(file.name)
        }
    }

    @MainActor private func commitTransfer(_ conflict: TransferConflict, renamedName: String?) {
        switch conflict.direction {
        case .upload:
            appModel.queueUpload(
                conflict.localFile,
                serverID: session.profile.id,
                remoteDirectory: session.remotePath,
                remoteName: renamedName
            )
            continueUpload(after: conflict, destinationName: renamedName ?? conflict.originalName)
        case .download:
            appModel.queueDownload(
                conflict.remoteFile,
                serverID: session.profile.id,
                remoteDirectory: session.remotePath,
                localDirectory: session.localPath,
                localName: renamedName
            )
            continueDownload(after: conflict, destinationName: renamedName ?? conflict.originalName)
        }
    }

    @MainActor private func skipTransfer(_ conflict: TransferConflict) {
        appModel.noteTransferSkipped(conflict.originalName)

        switch conflict.direction {
        case .upload:
            processUpload(conflict.remainingLocalFiles, existingNames: conflict.existingNames)
        case .download:
            processDownload(conflict.remainingRemoteFiles, existingNames: conflict.existingNames)
        }
    }

    @MainActor private func continueUpload(after conflict: TransferConflict, destinationName: String) {
        var destinationNames = conflict.existingNames
        destinationNames.insert(destinationName)
        processUpload(conflict.remainingLocalFiles, existingNames: destinationNames)
    }

    @MainActor private func continueDownload(after conflict: TransferConflict, destinationName: String) {
        var destinationNames = conflict.existingNames
        destinationNames.insert(destinationName)
        processDownload(conflict.remainingRemoteFiles, existingNames: destinationNames)
    }

    private func uniqueTransferName(for name: String, existingNames: Set<String>) -> String {
        let nsName = name as NSString
        let stem = nsName.deletingPathExtension
        let pathExtension = nsName.pathExtension
        let base = stem.isEmpty ? name : stem
        let suffix = pathExtension.isEmpty ? "" : ".\(pathExtension)"

        var candidate = "\(base) copy\(suffix)"
        var index = 2
        while existingNames.contains(candidate) {
            candidate = "\(base) copy \(index)\(suffix)"
            index += 1
        }
        return candidate
    }
}

private struct TransferConflict: Identifiable {
    enum Direction {
        case upload
        case download
    }

    let id = UUID()
    var direction: Direction
    var localFile: LocalFile?
    var remoteFile: RemoteFile?
    var originalName: String
    var suggestedName: String
    var remainingLocalFiles: [LocalFile]
    var remainingRemoteFiles: [RemoteFile]
    var existingNames: Set<String>

    var actionName: String {
        switch direction {
        case .upload:
            "upload"
        case .download:
            "download"
        }
    }

    var destinationName: String {
        switch direction {
        case .upload:
            "remote folder"
        case .download:
            "local folder"
        }
    }
}

private enum FilePaneRow: Identifiable {
    case local(LocalFile)
    case remote(RemoteFile)

    var id: String {
        switch self {
        case .local(let file):
            file.id
        case .remote(let file):
            file.id
        }
    }

    var selectableID: String? {
        id
    }

    var name: String {
        switch self {
        case .local(let file):
            file.name
        case .remote(let file):
            file.name
        }
    }

    var kind: RemoteFile.Kind {
        switch self {
        case .local(let file):
            file.kind
        case .remote(let file):
            file.kind
        }
    }

    var size: Int64 {
        switch self {
        case .local(let file):
            file.size
        case .remote(let file):
            file.size
        }
    }

    var modifiedAt: Date? {
        switch self {
        case .local(let file):
            file.modifiedAt
        case .remote(let file):
            file.modifiedAt
        }
    }

    var permissions: String? {
        switch self {
        case .remote(let file):
            file.permissions
        case .local:
            nil
        }
    }
}

private struct TransferConflictSheet: View {
    let conflict: TransferConflict
    let onCancel: () -> Void
    let onSkip: () -> Void
    let onReplace: () -> Void
    let onRename: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("同名项目已存在")
                        .font(.headline)
                    Text("\"\(conflict.originalName)\" already exists in the \(conflict.destinationName).")
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            HStack {
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("跳过", action: onSkip)
                Button("重命名", action: onRename)
                Button("替换", role: .destructive, action: onReplace)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460)
    }
}

private struct FileTransferSplitView<Leading: View, Trailing: View>: View {
    @Binding var splitRatio: Double
    let leading: () -> Leading
    let trailing: () -> Trailing
    @State private var dragStartWidth: CGFloat?

    private let handleWidth: CGFloat = 9
    private let minimumPaneWidth: CGFloat = 320

    init(
        splitRatio: Binding<Double>,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self._splitRatio = splitRatio
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(0, geometry.size.width - handleWidth)
            let leadingWidth = constrainedLeadingWidth(totalWidth: geometry.size.width)
            let trailingWidth = max(0, availableWidth - leadingWidth)

            HStack(spacing: 0) {
                leading()
                    .frame(width: leadingWidth)
                    .clipped()

                splitHandle(totalWidth: geometry.size.width)

                trailing()
                    .frame(width: trailingWidth)
                    .clipped()
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
        }
    }

    private func splitHandle(totalWidth: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.18))
                .frame(width: 1)

            Rectangle()
                .fill(Color.clear)
                .frame(width: handleWidth)
                .contentShape(Rectangle())
                .background {
                    CursorRectView(cursor: .resizeLeftRight)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            resizeSplit(value, totalWidth: totalWidth)
                        }
                        .onEnded { _ in
                            dragStartWidth = nil
                        }
                )
                .help("Drag to resize file panes")
        }
        .frame(width: handleWidth)
    }

    private func resizeSplit(_ value: DragGesture.Value, totalWidth: CGFloat) {
        let startingWidth = dragStartWidth ?? constrainedLeadingWidth(totalWidth: totalWidth)
        dragStartWidth = startingWidth

        let availableWidth = max(1, totalWidth - handleWidth)
        let nextWidth = constrainedLeadingWidth(
            proposedWidth: startingWidth + value.translation.width,
            availableWidth: availableWidth
        )
        splitRatio = Double(min(max(nextWidth / availableWidth, 0.2), 0.8))
    }

    private func constrainedLeadingWidth(totalWidth: CGFloat) -> CGFloat {
        let availableWidth = max(1, totalWidth - handleWidth)
        return constrainedLeadingWidth(
            proposedWidth: availableWidth * CGFloat(min(max(splitRatio, 0.2), 0.8)),
            availableWidth: availableWidth
        )
    }

    private func constrainedLeadingWidth(proposedWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        let effectiveMinimum = min(minimumPaneWidth, availableWidth / 2)
        let upperBound = max(effectiveMinimum, availableWidth - effectiveMinimum)
        return min(max(proposedWidth, effectiveMinimum), upperBound)
    }
}

private struct FilePane: View {
    let title: String
    @Binding var pathText: String
    let systemImage: String
    let rows: [FilePaneRow]
    @Binding var selectedIDs: Set<String>
    @Binding var activeSelectedID: String?
    let showsPermissions: Bool
    let columnWidthsStorageKey: String
    let emptyTitle: String
    let emptyDescription: String
    let onPathSubmit: () -> Void
    let onGoUp: () -> Void
    let onRefresh: () -> Void
    let onSelect: (FilePaneRow) -> Void
    let onOpen: (FilePaneRow) -> Void
    @AppStorage private var storedColumnWidths: Data

    init(
        title: String,
        pathText: Binding<String>,
        systemImage: String,
        rows: [FilePaneRow],
        selectedIDs: Binding<Set<String>>,
        activeSelectedID: Binding<String?>,
        showsPermissions: Bool,
        columnWidthsStorageKey: String,
        emptyTitle: String,
        emptyDescription: String,
        onPathSubmit: @escaping () -> Void,
        onGoUp: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onSelect: @escaping (FilePaneRow) -> Void,
        onOpen: @escaping (FilePaneRow) -> Void
    ) {
        self.title = title
        self._pathText = pathText
        self.systemImage = systemImage
        self.rows = rows
        self._selectedIDs = selectedIDs
        self._activeSelectedID = activeSelectedID
        self.showsPermissions = showsPermissions
        self.columnWidthsStorageKey = columnWidthsStorageKey
        self.emptyTitle = emptyTitle
        self.emptyDescription = emptyDescription
        self.onPathSubmit = onPathSubmit
        self.onGoUp = onGoUp
        self.onRefresh = onRefresh
        self.onSelect = onSelect
        self.onOpen = onOpen
        self._storedColumnWidths = AppStorage(wrappedValue: Data(), columnWidthsStorageKey)
    }

    private var columnWidths: Binding<FilePaneColumnWidths> {
        Binding(
            get: {
                FilePaneColumnWidths.load(from: storedColumnWidths)
            },
            set: { widths in
                storedColumnWidths = widths.encoded()
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            FilePaneHeader(
                title: title,
                pathText: $pathText,
                systemImage: systemImage,
                onPathSubmit: onPathSubmit,
                onGoUp: onGoUp,
                onRefresh: onRefresh
            )

            GeometryReader { geometry in
                let contentWidth = max(
                    columnWidths.wrappedValue.totalWidth(showsPermissions: showsPermissions),
                    geometry.size.width - FilePaneTableMetrics.horizontalPadding
                )
                let tableWidth = contentWidth + FilePaneTableMetrics.horizontalPadding

                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        FilePaneColumnHeader(
                            columnWidths: columnWidths,
                            showsPermissions: showsPermissions,
                            contentWidth: contentWidth
                        )
                        .frame(width: tableWidth)

                        ScrollView {
                            if rows.isEmpty {
                                ContentUnavailableView(
                                    emptyTitle,
                                    systemImage: "folder",
                                    description: Text(emptyDescription)
                                )
                                .frame(width: tableWidth)
                                .frame(minHeight: 180)
                                .padding(.top, 24)
                            } else {
                                LazyVStack(spacing: 0) {
                                    ForEach(rows) { row in
                                        FilePaneRowView(
                                            row: row,
                                            isSelected: selectedIDs.contains(row.id),
                                            columnWidths: columnWidths.wrappedValue,
                                            showsPermissions: showsPermissions,
                                            contentWidth: contentWidth,
                                            onSelect: {
                                                select(row)
                                                onSelect(row)
                                            },
                                            onOpen: {
                                                selectSingle(row)
                                                onSelect(row)
                                                onOpen(row)
                                            }
                                        )
                                    }
                                }
                                .padding(.vertical, 6)
                                .frame(width: tableWidth)
                            }
                        }
                    }
                    .frame(width: tableWidth)
                }
            }
        }
    }

    private func select(_ row: FilePaneRow) {
        guard let rowID = row.selectableID else {
            selectedIDs.removeAll()
            activeSelectedID = nil
            return
        }

        let modifierFlags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if modifierFlags.contains(.shift),
           let anchorID = activeSelectedID,
           let anchorIndex = rows.firstIndex(where: { $0.id == anchorID }),
           let rowIndex = rows.firstIndex(where: { $0.id == rowID }) {
            let bounds = min(anchorIndex, rowIndex)...max(anchorIndex, rowIndex)
            selectedIDs = Set(rows[bounds].compactMap(\.selectableID))
        } else if modifierFlags.contains(.command) {
            if selectedIDs.contains(rowID) {
                selectedIDs.remove(rowID)
            } else {
                selectedIDs.insert(rowID)
            }
            activeSelectedID = rowID
        } else {
            selectedIDs = [rowID]
            activeSelectedID = rowID
        }
    }

    private func selectSingle(_ row: FilePaneRow) {
        guard let rowID = row.selectableID else {
            selectedIDs.removeAll()
            activeSelectedID = nil
            return
        }

        selectedIDs = [rowID]
        activeSelectedID = rowID
    }
}

private struct FilePaneHeader: View {
    let title: String
    @Binding var pathText: String
    let systemImage: String
    let onPathSubmit: () -> Void
    let onGoUp: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)

                    TextField("Path", text: $pathText)
                        .textFieldStyle(.plain)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .onSubmit(onPathSubmit)
                }

                Spacer()

                Button(action: onGoUp) {
                    Image(systemName: "chevron.up")
                }
                .help("Parent Folder")

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider()
        }
    }
}

private struct FilePaneColumnHeader: View {
    @Binding var columnWidths: FilePaneColumnWidths
    let showsPermissions: Bool
    let contentWidth: CGFloat
    @AppStorage(HostDeckPreferenceKeys.fileBrowserFontFamily) private var fileBrowserFontFamily = HostDeckPreferenceDefaults.fileBrowserFontFamily.rawValue
    @AppStorage(HostDeckPreferenceKeys.fileBrowserFontSize) private var fileBrowserFontSize = HostDeckPreferenceDefaults.fileBrowserFontSize

    var body: some View {
        HStack(spacing: 0) {
            ResizableColumnHeaderCell(
                title: "Name",
                width: $columnWidths.name,
                minWidth: FilePaneTableMetrics.nameMinWidth
            )
            ResizableColumnHeaderCell(
                title: "Size",
                width: $columnWidths.size,
                minWidth: FilePaneTableMetrics.sizeMinWidth
            )
            ResizableColumnHeaderCell(
                title: "Modified",
                width: $columnWidths.modified,
                minWidth: FilePaneTableMetrics.modifiedMinWidth
            )
            if showsPermissions {
                ResizableColumnHeaderCell(
                    title: "Permissions",
                    width: $columnWidths.permissions,
                    minWidth: FilePaneTableMetrics.permissionsMinWidth
                )
            }

            Spacer(minLength: 0)
        }
        .font(fileBrowserFont(weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: contentWidth + FilePaneTableMetrics.horizontalPadding, alignment: .leading)
        .background(.quaternary.opacity(0.35))

        Divider()
    }

    private func fileBrowserFont(weight: Font.Weight = .regular) -> Font {
        InterfaceFontFamily.value(for: fileBrowserFontFamily).font(size: fileBrowserFontSize, weight: weight)
    }
}

private struct FilePaneRowView: View {
    let row: FilePaneRow
    let isSelected: Bool
    let columnWidths: FilePaneColumnWidths
    let showsPermissions: Bool
    let contentWidth: CGFloat
    let onSelect: () -> Void
    let onOpen: () -> Void
    @AppStorage(HostDeckPreferenceKeys.fileBrowserFontFamily) private var fileBrowserFontFamily = HostDeckPreferenceDefaults.fileBrowserFontFamily.rawValue
    @AppStorage(HostDeckPreferenceKeys.fileBrowserFontSize) private var fileBrowserFontSize = HostDeckPreferenceDefaults.fileBrowserFontSize

    var body: some View {
        HStack(spacing: 0) {
            FileNameCell(name: row.name, kind: row.kind, isParent: row.selectableID == nil)
                .frame(width: columnWidths.name, alignment: .leading)

            Text(row.kind == .file ? Formatters.byteCount.string(fromByteCount: row.size) : "--")
                .foregroundStyle(.secondary)
                .frame(width: columnWidths.size, alignment: .leading)

            Text(row.modifiedAt.map { Formatters.fileModifiedDate.string(from: $0) } ?? "")
                .foregroundStyle(.secondary)
                .frame(width: columnWidths.modified, alignment: .leading)

            if showsPermissions {
                Text(row.permissions ?? "")
                    .foregroundStyle(.secondary)
                    .frame(width: columnWidths.permissions, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .font(fileBrowserFont())
        .frame(width: contentWidth, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.24) : Color.clear)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .highPriorityGesture(
            TapGesture(count: 2)
                .onEnded {
                    onOpen()
                }
        )
        .contextMenu {
            Button("Open") {
                onOpen()
            }
            Button("Select") {
                onSelect()
            }
        }
    }

    private func fileBrowserFont(weight: Font.Weight = .regular) -> Font {
        InterfaceFontFamily.value(for: fileBrowserFontFamily).font(size: fileBrowserFontSize, weight: weight)
    }
}

private struct FilePaneColumnWidths: Codable, Equatable {
    var name: CGFloat = 320
    var size: CGFloat = 110
    var modified: CGFloat = 170
    var permissions: CGFloat = 120

    func totalWidth(showsPermissions: Bool) -> CGFloat {
        name + size + modified + (showsPermissions ? permissions : 0)
    }

    func encoded() -> Data {
        (try? JSONEncoder.hostDeck.encode(clamped)) ?? Data()
    }

    static func load(from data: Data) -> FilePaneColumnWidths {
        guard !data.isEmpty,
              let widths = try? JSONDecoder.hostDeck.decode(FilePaneColumnWidths.self, from: data) else {
            return FilePaneColumnWidths()
        }
        return widths.clamped
    }

    private var clamped: FilePaneColumnWidths {
        FilePaneColumnWidths(
            name: min(max(name, FilePaneTableMetrics.nameMinWidth), FilePaneTableMetrics.columnMaxWidth),
            size: min(max(size, FilePaneTableMetrics.sizeMinWidth), FilePaneTableMetrics.columnMaxWidth),
            modified: min(max(modified, FilePaneTableMetrics.modifiedMinWidth), FilePaneTableMetrics.columnMaxWidth),
            permissions: min(max(permissions, FilePaneTableMetrics.permissionsMinWidth), FilePaneTableMetrics.columnMaxWidth)
        )
    }

    enum StorageKey {
        static let local = "HostDeck.filePaneColumnWidths.local.v1"
        static let remote = "HostDeck.filePaneColumnWidths.remote.v1"
    }
}

private enum FilePaneTableMetrics {
    static let horizontalPadding: CGFloat = 28
    static let nameMinWidth: CGFloat = 140
    static let sizeMinWidth: CGFloat = 72
    static let modifiedMinWidth: CGFloat = 128
    static let permissionsMinWidth: CGFloat = 92
    static let columnMaxWidth: CGFloat = 720
}

private struct ResizableColumnHeaderCell: View {
    let title: String
    @Binding var width: CGFloat
    let minWidth: CGFloat
    @State private var dragStartWidth: CGFloat?
    @State private var isDragging = false

    var body: some View {
        Text(title)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
            .overlay(alignment: .trailing) {
                ColumnResizeHandle(
                    isDragging: isDragging,
                    onChanged: resizeColumn,
                    onEnded: endResize
                )
            }
    }

    private func resizeColumn(_ value: DragGesture.Value) {
        if dragStartWidth == nil {
            dragStartWidth = width
        }

        let startingWidth = dragStartWidth ?? width
        width = min(
            max(startingWidth + value.translation.width, minWidth),
            FilePaneTableMetrics.columnMaxWidth
        )
        isDragging = true
    }

    private func endResize() {
        dragStartWidth = nil
        isDragging = false
    }
}

private struct ColumnResizeHandle: View {
    let isDragging: Bool
    let onChanged: (DragGesture.Value) -> Void
    let onEnded: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isDragging ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.22))
                .frame(width: 1)

            Rectangle()
                .fill(Color.clear)
                .frame(width: 10)
                .contentShape(Rectangle())
                .background {
                    CursorRectView(cursor: .resizeLeftRight)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged(onChanged)
                        .onEnded { _ in
                            onEnded()
                        }
                )
                .help("Drag to resize column")
        }
        .frame(width: 10)
    }
}

private struct CursorRectView: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorRectNSView {
        let view = CursorRectNSView()
        view.cursor = cursor
        return view
    }

    func updateNSView(_ nsView: CursorRectNSView, context: Context) {
        nsView.cursor = cursor
    }
}

private final class CursorRectNSView: NSView {
    var cursor: NSCursor = .arrow {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }
}

private struct TransferQueueStrip: View {
    let jobs: [TransferJob]
    @Binding var isExpanded: Bool
    let onCancel: (TransferJob) -> Void
    private let maxExpandedHeight: CGFloat = 260

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .help(isExpanded ? "Minimize Transfer Queue" : "Expand Transfer Queue")

                Text("Transfer Queue")
                    .font(.caption.weight(.semibold))

                Spacer()

                Text(summaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            }

            if isExpanded {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 8) {
                        ForEach(jobs) { job in
                            TransferProgressRow(
                                job: job,
                                onCancel: {
                                    onCancel(job)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.visible)
                .frame(maxHeight: maxExpandedHeight)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background(.bar)
    }

    private var summaryText: String {
        let runningCount = jobs.filter { $0.status == .running }.count
        let queuedCount = jobs.filter { $0.status == .queued }.count

        if runningCount > 0 {
            return "\(runningCount) active, \(queuedCount) queued"
        }

        if queuedCount > 0 {
            return "\(queuedCount) queued"
        }

        return "\(jobs.count) shown"
    }
}

private struct TransferProgressRow: View {
    let job: TransferJob
    let onCancel: () -> Void
    @AppStorage(HostDeckPreferenceKeys.transferListFontFamily) private var transferListFontFamily = HostDeckPreferenceDefaults.transferListFontFamily.rawValue
    @AppStorage(HostDeckPreferenceKeys.transferListFontSize) private var transferListFontSize = HostDeckPreferenceDefaults.transferListFontSize

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(statusColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(rowFont(weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(percentText)
                        .font(rowFont())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)

                HStack(spacing: 12) {
                    Text("\(Formatters.byteCount.string(fromByteCount: job.transferredBytes)) of \(Formatters.byteCount.string(fromByteCount: job.totalBytes))")
                    Text(job.speedText)
                    if let errorMessage = job.errorMessage {
                        Text(errorMessage)
                            .lineLimit(1)
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
    }

    private func rowFont(sizeOffset: Double = 0, weight: Font.Weight = .regular) -> Font {
        InterfaceFontFamily.value(for: transferListFontFamily).font(size: transferListFontSize + sizeOffset, weight: weight)
    }

    private var title: String {
        let verb: String
        switch job.status {
        case .running:
            verb = job.direction == .download ? "Downloading" : "Uploading"
        case .completed:
            verb = job.direction == .download ? "Downloaded" : "Uploaded"
        case .failed:
            verb = "Failed"
        case .queued:
            verb = "Queued"
        case .cancelled:
            verb = "Cancelled"
        }
        return "\(verb) \(job.filename)"
    }

    private var percentText: String {
        "\(Int((job.progress * 100).rounded()))%"
    }

    private var iconName: String {
        switch job.status {
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        default:
            return job.direction == .download ? "arrow.down.circle" : "arrow.up.circle"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .completed:
            return .green
        case .failed:
            return .red
        case .queued, .cancelled:
            return .secondary
        default:
            return .accentColor
        }
    }
}

private struct FileNameCell: View {
    let name: String
    let kind: RemoteFile.Kind
    let isParent: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(kind == .directory ? .blue : .secondary)
            Text(name)
                .lineLimit(1)
        }
    }

    private var iconName: String {
        if isParent {
            return "ellipsis"
        }

        switch kind {
        case .directory:
            return "folder"
        case .file:
            return "doc"
        case .symlink:
            return "arrowshape.turn.up.right"
        }
    }
}
