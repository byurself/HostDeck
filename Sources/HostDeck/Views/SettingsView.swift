import SwiftUI

struct SettingsView: View {
    @Bindable var appModel: AppModel
    @AppStorage(HostDeckPreferenceKeys.appearanceMode) private var appearanceMode = HostDeckPreferenceDefaults.appearanceMode.rawValue
    @AppStorage(HostDeckPreferenceKeys.terminalFontFamily) private var terminalFontFamily = HostDeckPreferenceDefaults.terminalFontFamily.rawValue
    @AppStorage(HostDeckPreferenceKeys.terminalFontSize) private var terminalFontSize = HostDeckPreferenceDefaults.terminalFontSize
    @AppStorage(HostDeckPreferenceKeys.terminalCursorBlink) private var terminalCursorBlink = HostDeckPreferenceDefaults.terminalCursorBlink
    @AppStorage(HostDeckPreferenceKeys.terminalScrollback) private var terminalScrollback = HostDeckPreferenceDefaults.terminalScrollback
    @AppStorage(HostDeckPreferenceKeys.transferListFontFamily) private var transferListFontFamily = HostDeckPreferenceDefaults.transferListFontFamily.rawValue
    @AppStorage(HostDeckPreferenceKeys.transferListFontSize) private var transferListFontSize = HostDeckPreferenceDefaults.transferListFontSize
    @AppStorage(HostDeckPreferenceKeys.serverListFontFamily) private var serverListFontFamily = HostDeckPreferenceDefaults.serverListFontFamily.rawValue
    @AppStorage(HostDeckPreferenceKeys.serverListFontSize) private var serverListFontSize = HostDeckPreferenceDefaults.serverListFontSize
    @AppStorage(HostDeckPreferenceKeys.fileBrowserFontFamily) private var fileBrowserFontFamily = HostDeckPreferenceDefaults.fileBrowserFontFamily.rawValue
    @AppStorage(HostDeckPreferenceKeys.fileBrowserFontSize) private var fileBrowserFontSize = HostDeckPreferenceDefaults.fileBrowserFontSize
    @AppStorage(HostDeckPreferenceKeys.maxConcurrentTransfers) private var maxConcurrentTransfers = HostDeckPreferenceDefaults.maxConcurrentTransfers
    @AppStorage(HostDeckPreferenceKeys.confirmUnknownHostKeys) private var confirmUnknownHostKeys = HostDeckPreferenceDefaults.confirmUnknownHostKeys

    var body: some View {
        TabView {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Terminal") {
                    Picker("Font", selection: $terminalFontFamily) {
                        ForEach(TerminalFontFamily.allCases) { family in
                            Text(family.label).tag(family.rawValue)
                        }
                    }

                    Stepper(value: $terminalFontSize, in: 10...24, step: 1) {
                        Text("Size: \(Int(terminalFontSize)) pt")
                    }

                    Toggle("Blink cursor", isOn: $terminalCursorBlink)

                    Stepper(value: $terminalScrollback, in: 500...20_000, step: 500) {
                        Text("Scrollback: \(terminalScrollback) lines")
                    }
                }

                Section("Lists") {
                    FontPreferenceRow(
                        title: "Server list",
                        family: $serverListFontFamily,
                        size: $serverListFontSize,
                        sizeRange: 10...20
                    )

                    FontPreferenceRow(
                        title: "File browser",
                        family: $fileBrowserFontFamily,
                        size: $fileBrowserFontSize,
                        sizeRange: 10...18
                    )

                    FontPreferenceRow(
                        title: "Transfer queue",
                        family: $transferListFontFamily,
                        size: $transferListFontSize,
                        sizeRange: 10...20
                    )
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Display", systemImage: "paintbrush")
            }

            Form {
                Section("Connections") {
                    Toggle("Confirm unknown host keys", isOn: $confirmUnknownHostKeys)
                    Stepper(value: $maxConcurrentTransfers, in: 1...8) {
                        Text("Concurrent transfers: \(maxConcurrentTransfers)")
                    }
                }

                Section("Storage") {
                    Text("Profiles: \(appModel.profileStore.profiles.count)")
                    Text("Credentials are stored in Keychain.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Transfers", systemImage: "arrow.up.arrow.down")
            }
        }
        .scenePadding()
        .frame(width: 560, height: 500)
    }
}

private struct FontPreferenceRow: View {
    let title: String
    @Binding var family: String
    @Binding var size: Double
    let sizeRange: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(title, selection: $family) {
                ForEach(InterfaceFontFamily.allCases) { family in
                    Text(family.label).tag(family.rawValue)
                }
            }

            Stepper(value: $size, in: sizeRange, step: 1) {
                Text("\(title) size: \(Int(size)) pt")
            }
        }
    }
}
