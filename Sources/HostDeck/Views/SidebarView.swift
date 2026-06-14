import SwiftUI

struct SidebarView: View {
    @Bindable var appModel: AppModel
    @State private var searchText = ""

    @MainActor private var profiles: [ServerProfile] {
        if searchText.isEmpty {
            return appModel.profileStore.profiles
        }
        return appModel.profileStore.profiles.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.host.localizedCaseInsensitiveContains(searchText)
                || $0.username.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List(selection: $appModel.selectedServerID) {
            Section("Servers") {
                ForEach(profiles) { profile in
                    ServerRow(
                        profile: profile,
                        connectionState: appModel.connectionState(for: profile.id)
                    )
                        .tag(profile.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appModel.selectServer(profile.id)
                        }
                        .onTapGesture(count: 2) {
                            appModel.selectServer(profile.id)
                            Task { await appModel.connectSelectedServer() }
                        }
                        .contextMenu {
                            Button("Edit") {
                                appModel.editingServer = profile
                                appModel.isPresentingServerEditor = true
                            }
                            Button("Delete", role: .destructive) {
                                appModel.selectedServerID = profile.id
                                appModel.deleteSelectedProfile()
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search servers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appModel.editingServer = nil
                    appModel.isPresentingServerEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Server")
            }
        }
        .navigationTitle("HostDeck")
    }
}

private struct ServerRow: View {
    let profile: ServerProfile
    let connectionState: ConnectionState
    @AppStorage(HostDeckPreferenceKeys.serverListFontFamily) private var serverListFontFamily = HostDeckPreferenceDefaults.serverListFontFamily.rawValue
    @AppStorage(HostDeckPreferenceKeys.serverListFontSize) private var serverListFontSize = HostDeckPreferenceDefaults.serverListFontSize

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: profile.authMethod == .password ? "key" : "lock.doc")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(rowFont())
                    .lineLimit(1)
                Text("\(profile.username)@\(profile.host)")
                    .font(rowFont(sizeOffset: -2))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(statusText)
                    .font(rowFont(sizeOffset: -3))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private func rowFont(sizeOffset: Double = 0, weight: Font.Weight = .regular) -> Font {
        InterfaceFontFamily.value(for: serverListFontFamily).font(size: serverListFontSize + sizeOffset, weight: weight)
    }

    private var statusColor: Color {
        switch connectionState {
        case .connected:
            .green
        case .connecting:
            .yellow
        case .failed:
            .red
        case .disconnected:
            .secondary
        }
    }

    private var statusText: String {
        switch connectionState {
        case .connected:
            "Connected"
        case .connecting:
            "Connecting"
        case .failed:
            "Failed"
        case .disconnected:
            "Offline"
        }
    }
}
