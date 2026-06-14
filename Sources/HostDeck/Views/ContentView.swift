import SwiftUI

struct ContentView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView(appModel: appModel)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
        } detail: {
            DetailView(appModel: appModel)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Workspace", selection: workspaceSelection) {
                    ForEach(WorkspaceKind.allCases) { workspace in
                        Label(workspace.label, systemImage: workspace.systemImage)
                            .tag(workspace)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                Button {
                    appModel.createTerminalTabForSelectedServer()
                } label: {
                    Label("New Terminal", systemImage: "terminal")
                }
                .disabled(appModel.selectedServer == nil)

                Button {
                    appModel.createFileTransferTabForSelectedServer()
                } label: {
                    Label("New SFTP", systemImage: "folder.badge.plus")
                }
                .disabled(appModel.selectedServer == nil)

                Button {
                    Task { await appModel.connectSelectedServer() }
                } label: {
                    Label("Connect", systemImage: "bolt.horizontal.circle")
                }
                .disabled(appModel.selectedServer == nil || appModel.connectionState.isConnected)

                Button {
                    Task { await appModel.disconnect() }
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
                .disabled(!appModel.connectionState.isConnected)
            }
        }
        .sheet(isPresented: $appModel.isPresentingServerEditor) {
            ServerEditorView(
                profile: appModel.editingServer ?? ServerProfile(name: "", host: "", username: ""),
                onCancel: {
                    appModel.editingServer = nil
                    appModel.isPresentingServerEditor = false
                },
                onSave: { profile, secret in
                    appModel.saveProfile(profile, secret: secret)
                    appModel.editingServer = nil
                    appModel.isPresentingServerEditor = false
                },
                onTest: { profile, secret in
                    await appModel.testConnection(profile: profile, secret: secret)
                }
            )
            .frame(width: 520)
        }
    }

    @MainActor private var workspaceSelection: Binding<WorkspaceKind> {
        Binding(
            get: { appModel.selectedWorkspace },
            set: { workspace in
                appModel.selectWorkspace(workspace)
            }
        )
    }
}
