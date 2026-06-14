import AppKit
import SwiftUI

enum HostDeckAppearance {
    static func apply(_ mode: AppearanceMode, to window: NSWindow? = nil) {
        let appearance = mode.nsAppearance
        NSApp.appearance = appearance

        for window in NSApp.windows {
            window.appearance = appearance
        }

        window?.appearance = appearance
    }
}

extension View {
    func hostDeckAppearance(_ mode: AppearanceMode) -> some View {
        modifier(HostDeckAppearanceModifier(mode: mode))
    }
}

private struct HostDeckAppearanceModifier: ViewModifier {
    let mode: AppearanceMode

    func body(content: Content) -> some View {
        content
            .background(HostDeckWindowAppearanceSync(mode: mode).frame(width: 0, height: 0))
            .onAppear {
                HostDeckAppearance.apply(mode)
            }
            .onChange(of: mode) { _, newMode in
                HostDeckAppearance.apply(newMode)
            }
    }
}

private struct HostDeckWindowAppearanceSync: NSViewRepresentable {
    let mode: AppearanceMode

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        apply(mode, from: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        apply(mode, from: view)
    }

    private func apply(_ mode: AppearanceMode, from view: NSView) {
        HostDeckAppearance.apply(mode, to: view.window)

        DispatchQueue.main.async {
            HostDeckAppearance.apply(mode, to: view.window)
        }
    }
}

private extension AppearanceMode {
    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }
}
