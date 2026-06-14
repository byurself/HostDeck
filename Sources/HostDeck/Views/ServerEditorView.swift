import SwiftUI
import AppKit

struct ServerEditorView: View {
    @State private var draft: ServerProfile
    @State private var password = ""
    @State private var passphrase = ""
    @State private var isTestingConnection = false
    @State private var testResult: ConnectionTestResult?
    let onCancel: () -> Void
    let onSave: (ServerProfile, CredentialSecret?) -> Void
    let onTest: (ServerProfile, CredentialSecret?) async -> ConnectionTestResult

    init(
        profile: ServerProfile,
        onCancel: @escaping () -> Void,
        onSave: @escaping (ServerProfile, CredentialSecret?) -> Void,
        onTest: @escaping (ServerProfile, CredentialSecret?) async -> ConnectionTestResult
    ) {
        _draft = State(initialValue: profile)
        self.onCancel = onCancel
        self.onSave = onSave
        self.onTest = onTest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(draft.name.isEmpty ? "New Server" : "Edit Server")
                .font(.title2.bold())
                .padding([.horizontal, .top], 22)

            Form {
                TextField("Name", text: $draft.name)
                TextField("Host", text: $draft.host)
                TextField("Port", value: $draft.port, formatter: Self.portFormatter)
                    .onSubmit {
                        clampPort()
                    }
                TextField("Username", text: $draft.username)

                Picker("Authentication", selection: $draft.authMethod) {
                    ForEach(AuthMethod.allCases) { method in
                        Text(method.label).tag(method)
                    }
                }

                if draft.authMethod == .password {
                    SecureField("Password", text: $password)
                }

                if draft.authMethod == .privateKey {
                    TextField("Private Key", text: $draft.privateKeyPath)
                    SecureField("Passphrase", text: $passphrase)
                }

                HStack {
                    TextField("Default Path", text: $draft.defaultPath)
                    Button {
                        chooseDefaultPath()
                    } label: {
                        Label("Choose", systemImage: "folder")
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 12)

            Divider()

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button {
                    Task { await testConnection() }
                } label: {
                    if isTestingConnection {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Test Connection", systemImage: "network")
                    }
                }
                .disabled(isTestingConnection || !canSubmit)

                if let testResult {
                    Label(testResult.message, systemImage: testResult.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(testResult.isSuccess ? .green : .red)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()

                Button("Save") {
                    clampPort()
                    onSave(draft, secret)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
            .padding(16)
        }
    }

    private var canSubmit: Bool {
        !draft.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (1...65_535).contains(draft.port)
    }

    private var secret: CredentialSecret? {
        switch draft.authMethod {
        case .password:
            password.isEmpty ? nil : .password(password)
        case .privateKey:
            passphrase.isEmpty ? nil : .privateKey(passphrase: passphrase)
        case .agent:
            nil
        }
    }

    private func testConnection() async {
        clampPort()
        isTestingConnection = true
        testResult = nil
        let result = await onTest(draft, secret)
        testResult = result
        isTestingConnection = false
    }

    private func clampPort() {
        draft.port = min(max(draft.port, 1), 65_535)
    }

    private func chooseDefaultPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose a default folder."

        if panel.runModal() == .OK, let url = panel.url {
            draft.defaultPath = url.path
        }
    }

    private static let portFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.maximum = 65_535
        formatter.allowsFloats = false
        return formatter
    }()
}
