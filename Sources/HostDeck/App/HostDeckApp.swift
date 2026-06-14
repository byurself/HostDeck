import AppKit
import SwiftUI

@main
struct HostDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @AppStorage(HostDeckPreferenceKeys.appearanceMode) private var appearanceModeRaw = HostDeckPreferenceDefaults.appearanceMode.rawValue
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup("HostDeck") {
            ContentView(appModel: appModel)
                .frame(minWidth: 1040, minHeight: 680)
                .hostDeckAppearance(appearanceMode)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About HostDeck") {
                    openWindow(id: "about-hostdeck")
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("New Server") {
                    appModel.isPresentingServerEditor = true
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Connect") {
                    Task { await appModel.connectSelectedServer() }
                }
                .keyboardShortcut("k", modifiers: [.command])
                .disabled(appModel.selectedServer == nil || appModel.connectionState.isConnected)

                Button("Disconnect") {
                    Task { await appModel.disconnect() }
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(!appModel.connectionState.isConnected)
            }
        }

        Settings {
            SettingsView(appModel: appModel)
                .hostDeckAppearance(appearanceMode)
        }

        Window("About HostDeck", id: "about-hostdeck") {
            AboutHostDeckView()
                .hostDeckAppearance(appearanceMode)
        }
        .windowResizability(.contentSize)
    }

    private var appearanceMode: AppearanceMode {
        AppearanceMode.value(for: appearanceModeRaw)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        HostDeckAppearance.apply(
            AppearanceMode.value(
                for: UserDefaults.standard.string(forKey: HostDeckPreferenceKeys.appearanceMode)
                    ?? HostDeckPreferenceDefaults.appearanceMode.rawValue
            )
        )
        NSApp.activate(ignoringOtherApps: true)
    }
}
