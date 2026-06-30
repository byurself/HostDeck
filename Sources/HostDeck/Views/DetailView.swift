import SwiftUI

struct DetailView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        let footerState = currentFooterState

        VStack(spacing: 0) {
            if !appModel.workspaceTabs.isEmpty {
                WorkspaceTabBar(appModel: appModel)
                Divider()
            }

            if let tab = appModel.selectedWorkspaceTab {
                WorkspaceTabContent(appModel: appModel, tab: tab)
            } else if appModel.workspaceTabs.isEmpty {
                WorkspaceEmptyStateView(appModel: appModel)
            } else {
                PrimaryWorkspaceContent(
                    appModel: appModel,
                    workspace: appModel.selectedWorkspace,
                    serverID: appModel.selectedServerID
                )
            }

            Divider()

            HStack {
                Text(footerState.message)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(footerState.connectionState.label)
                    .foregroundStyle(footerState.connectionState.isConnected ? .green : .secondary)
            }
            .font(.caption)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @MainActor private var currentFooterState: DetailFooterState {
        guard let tab = appModel.selectedWorkspaceTab else {
            return DetailFooterState(message: appModel.statusMessage, connectionState: appModel.connectionState)
        }

        switch tab.kind {
        case .primary(_, let serverID):
            guard let serverID else {
                return DetailFooterState(message: appModel.statusMessage, connectionState: appModel.connectionState)
            }
            return DetailFooterState(
                message: appModel.statusMessage(for: serverID),
                connectionState: appModel.connectionState(for: serverID)
            )
        case .terminal(let sessionID):
            guard let session = appModel.terminalWindowSession(for: sessionID) else {
                return DetailFooterState(message: "Terminal session not found", connectionState: .failed("Terminal session not found"))
            }
            return DetailFooterState(message: session.statusMessage, connectionState: session.connectionState)
        case .files(let sessionID):
            guard let session = appModel.fileTransferWindowSession(for: sessionID) else {
                return DetailFooterState(message: "SFTP session not found", connectionState: .failed("SFTP session not found"))
            }
            return DetailFooterState(message: session.statusMessage, connectionState: session.connectionState)
        }
    }
}

private struct DetailFooterState {
    let message: String
    let connectionState: ConnectionState
}

private struct WorkspaceEmptyStateView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: iconName)
                    .font(.system(size: 32, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title3.weight(.semibold))

                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                if appModel.selectedServer == nil {
                    Button {
                        appModel.editingServer = nil
                        appModel.isPresentingServerEditor = true
                    } label: {
                        Label("Add Server", systemImage: "plus")
                    }
                } else {
                    Button {
                        appModel.createTerminalTabForSelectedServer()
                    } label: {
                        Label("Terminal", systemImage: "terminal")
                    }

                    Button {
                        appModel.createFileTransferTabForSelectedServer()
                    } label: {
                        Label("SFTP", systemImage: "folder")
                    }

                    Button {
                        Task { await appModel.connectSelectedServer() }
                    } label: {
                        Label("Connect", systemImage: "bolt.horizontal.circle")
                    }
                    .disabled(appModel.connectionState.isConnected)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @MainActor private var title: String {
        appModel.selectedServer == nil ? "Choose a Server" : "No Open Tab"
    }

    @MainActor private var subtitle: String {
        if let server = appModel.selectedServer {
            return "Open a workspace for \(server.displayName)."
        }

        return "Select one from the sidebar or add a new server."
    }

    @MainActor private var iconName: String {
        appModel.selectedServer == nil ? "server.rack" : appModel.selectedWorkspace.systemImage
    }
}

private struct WorkspaceTabBar: View {
    @Bindable var appModel: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(appModel.workspaceTabs) { tab in
                    WorkspaceTabItem(
                        tab: tab,
                        isSelected: appModel.selectedWorkspaceTabID == tab.id,
                        onSelect: {
                            appModel.selectWorkspaceTab(tab.id)
                        },
                        onClose: {
                            appModel.closeWorkspaceTab(tab.id)
                        }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .background(.bar)
    }
}

private struct WorkspaceTabItem: View {
    let tab: WorkspaceTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: tab.systemImage)
                .font(.caption)
            Text(tab.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close Tab")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minWidth: 96, maxWidth: 150, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .help(tab.subtitle)
    }
}

private struct WorkspaceTabContent: View {
    @Bindable var appModel: AppModel
    let tab: WorkspaceTab

    var body: some View {
        switch tab.kind {
        case .primary(let workspace, let serverID):
            PrimaryWorkspaceContent(appModel: appModel, workspace: workspace, serverID: serverID)
        case .terminal(let sessionID):
            if let session = appModel.terminalWindowSession(for: sessionID) {
                TerminalSessionContentView(session: session)
                    .id(session.id)
            } else {
                ContentUnavailableView("Terminal Session Not Found", systemImage: "terminal")
            }
        case .files(let sessionID):
            if let session = appModel.fileTransferWindowSession(for: sessionID) {
                SFTPDetachedWindowView(appModel: appModel, session: session)
                    .id(session.id)
            } else {
                ContentUnavailableView("SFTP Session Not Found", systemImage: "folder")
            }
        }
    }
}

private struct PrimaryWorkspaceContent: View {
    @Bindable var appModel: AppModel
    let workspace: WorkspaceKind
    let serverID: ServerProfile.ID?

    var body: some View {
        Group {
            switch workspace {
            case .terminal:
                TerminalView(appModel: appModel, serverID: serverID)
            case .files:
                SFTPBrowserView(appModel: appModel, serverID: serverID)
            case .transfers:
                TransferQueueView(appModel: appModel)
            }
        }
        .task(id: taskID) {
            if workspace == .files, let serverID {
                await appModel.prepareFileTransferWorkspace(for: serverID)
            }
        }
    }

    private var taskID: String {
        "\(workspace.rawValue)-\(serverID?.uuidString ?? "none")"
    }
}
