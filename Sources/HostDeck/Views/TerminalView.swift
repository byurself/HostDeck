import SwiftUI
import WebKit

struct TerminalView: View {
    @Bindable var appModel: AppModel
    let serverID: ServerProfile.ID?

    var body: some View {
        if let serverID {
            TerminalSurface(
                events: appModel.terminalEvents(for: serverID),
                onInput: { input in
                    Task { await appModel.sendTerminalInput(input, for: serverID) }
                },
                onResize: { columns, rows in
                    Task { await appModel.resizeTerminal(columns: columns, rows: rows, for: serverID) }
                }
            )
        } else {
            ContentUnavailableView("No Server Selected", systemImage: "terminal")
        }
    }
}

struct TerminalSessionContentView: View {
    @Bindable var session: TerminalWindowSession

    var body: some View {
        TerminalSurface(
            events: session.terminalEvents,
            onInput: { input in
                Task { await session.sendTerminalInput(input) }
            },
            onResize: { columns, rows in
                Task { await session.resizeTerminal(columns: columns, rows: rows) }
            }
        )
        .task(id: session.id) {
            await session.connect()
        }
    }
}

struct TerminalSessionWindowView: View {
    @Bindable var session: TerminalWindowSession

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.profile.displayName)
                        .font(.headline)
                    Text("\(session.profile.username)@\(session.profile.host):\(session.profile.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await session.connect() }
                } label: {
                    Label("Connect", systemImage: "bolt.horizontal.circle")
                }
                .disabled(session.connectionState.isConnected)
                Button {
                    Task { await session.disconnect() }
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
                .disabled(!session.connectionState.isConnected)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            TerminalSessionContentView(session: session)

            Divider()

            HStack {
                Text(session.statusMessage)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(session.connectionState.label)
                    .foregroundStyle(session.connectionState.isConnected ? .green : .secondary)
            }
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
        }
    }
}

private struct TerminalSurface: View {
    let events: [TerminalEvent]
    let onInput: (String) -> Void
    let onResize: (Int, Int) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(HostDeckPreferenceKeys.terminalFontFamily) private var terminalFontFamily = HostDeckPreferenceDefaults.terminalFontFamily.rawValue
    @AppStorage(HostDeckPreferenceKeys.terminalFontSize) private var terminalFontSize = HostDeckPreferenceDefaults.terminalFontSize
    @AppStorage(HostDeckPreferenceKeys.terminalCursorBlink) private var terminalCursorBlink = HostDeckPreferenceDefaults.terminalCursorBlink
    @AppStorage(HostDeckPreferenceKeys.terminalScrollback) private var terminalScrollback = HostDeckPreferenceDefaults.terminalScrollback

    var body: some View {
        XtermWebView(
            events: events,
            configuration: TerminalWebConfiguration(
                fontFamily: TerminalFontFamily.value(for: terminalFontFamily).cssFamily,
                fontSize: terminalFontSize,
                cursorBlink: terminalCursorBlink,
                scrollback: terminalScrollback,
                theme: colorScheme == .dark ? .dark : .light
            ),
            onInput: onInput,
            onResize: onResize
        )
    }
}

struct TerminalWebConfiguration: Encodable, Equatable {
    enum Theme: String, Encodable {
        case light
        case dark
    }

    let fontFamily: String
    let fontSize: Double
    let cursorBlink: Bool
    let scrollback: Int
    let theme: Theme
}

struct XtermWebView: NSViewRepresentable {
    let events: [TerminalEvent]
    let configuration: TerminalWebConfiguration
    let onInput: (String) -> Void
    let onResize: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(configuration: configuration, onInput: onInput, onResize: onResize)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "terminalInput")
        configuration.userContentController.add(context.coordinator, name: "terminalResize")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        if let url = Self.terminalHTMLURL() {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        context.coordinator.webView = webView
        return webView
    }

    private static func terminalHTMLURL() -> URL? {
        if let url = Bundle.main.url(forResource: "terminal", withExtension: "html") {
            return url
        }

        let resourceBundleURL = Bundle.main.bundleURL.appendingPathComponent("HostDeck_HostDeck.bundle")
        return Bundle(url: resourceBundleURL)?.url(forResource: "terminal", withExtension: "html")
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onInput = onInput
        context.coordinator.onResize = onResize
        context.coordinator.configuration = configuration

        let newEvents: [TerminalEvent]
        if let latestEventID = context.coordinator.latestEventID,
           let index = events.firstIndex(where: { $0.id == latestEventID }) {
            newEvents = Array(events.dropFirst(index + 1))
        } else {
            newEvents = events
        }

        context.coordinator.latestEventID = events.last?.id
        guard context.coordinator.isLoaded else {
            context.coordinator.pendingEvents.append(contentsOf: newEvents)
            return
        }

        context.coordinator.applyConfiguration()
        for event in newEvents {
            context.coordinator.apply(event)
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onInput: (String) -> Void
        var onResize: (Int, Int) -> Void
        var configuration: TerminalWebConfiguration
        weak var webView: WKWebView?
        var isLoaded = false
        var latestEventID: TerminalEvent.ID?
        var pendingEvents: [TerminalEvent] = []
        private var appliedConfiguration: TerminalWebConfiguration?

        init(configuration: TerminalWebConfiguration, onInput: @escaping (String) -> Void, onResize: @escaping (Int, Int) -> Void) {
            self.configuration = configuration
            self.onInput = onInput
            self.onResize = onResize
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            applyConfiguration()
            pendingEvents.forEach(apply)
            pendingEvents.removeAll()
            webView.evaluateJavaScript("window.hostDeckFocus && window.hostDeckFocus();")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "terminalInput":
                if let input = message.body as? String {
                    onInput(input)
                }
            case "terminalResize":
                if let payload = message.body as? [String: Any],
                   let columns = payload["cols"] as? Int,
                   let rows = payload["rows"] as? Int {
                    onResize(columns, rows)
                }
            default:
                break
            }
        }

        func applyConfiguration() {
            guard appliedConfiguration != configuration,
                  let json = try? JSONEncoder().encode(configuration),
                  let string = String(data: json, encoding: .utf8) else {
                return
            }

            appliedConfiguration = configuration
            webView?.evaluateJavaScript("window.hostDeckConfigure && window.hostDeckConfigure(\(string));")
        }

        func apply(_ event: TerminalEvent) {
            switch event.kind {
            case .reset:
                webView?.evaluateJavaScript("window.hostDeckReset && window.hostDeckReset();")
            case .write:
                guard let json = try? JSONEncoder().encode(event.data),
                      let string = String(data: json, encoding: .utf8) else { return }
                webView?.evaluateJavaScript("window.hostDeckWrite && window.hostDeckWrite(\(string));")
            }
        }
    }
}
