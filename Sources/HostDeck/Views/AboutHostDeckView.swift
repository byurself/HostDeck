import AppKit
import SwiftUI

struct AboutHostDeckView: View {
    @State private var isShowingLicenses = false

    private let resourceColumns = [
        GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .leading)
    ]

    private let productDescription = """
    HostDeck is a native macOS app for managing remote hosts, SSH sessions, and SFTP files in one focused workspace. It is designed for developers and operators who need a clean, local-first way to connect, browse, transfer, and work across servers.
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("About")
                Text(productDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Acknowledgements")
                VStack(alignment: .leading, spacing: 7) {
                    DependencyRow("Swift / SwiftUI")
                    DependencyRow("libssh2")
                    DependencyRow("xterm.js terminal web assets")
                }

                Button("View Licenses") {
                    isShowingLicenses = true
                }
                .help("View dependency acknowledgements and license details.")
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Resources")
                LazyVGrid(columns: resourceColumns, alignment: .leading, spacing: 8) {
                    Button {
                        open(AppInfo.releasesURL)
                    } label: {
                        Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("Open the latest HostDeck release on GitHub.")

                    Button(action: openLogsFolder) {
                        Label("Open Logs Folder", systemImage: "folder")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("Open HostDeck's local logs folder.")

                    Button {
                        open(AppInfo.newIssueURL)
                    } label: {
                        Label("Report an Issue", systemImage: "exclamationmark.bubble")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("Open a new GitHub issue with an issue report template.")

                    Button {
                        open(AppInfo.repositoryURL)
                    } label: {
                        Label("GitHub", systemImage: "network")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("Open the HostDeck GitHub repository.")

                    Button {
                        open(AppInfo.documentationURL)
                    } label: {
                        Label("Documentation", systemImage: "book")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("Open the HostDeck README documentation.")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .padding(28)
        .frame(width: 560)
        .sheet(isPresented: $isShowingLicenses) {
            LicenseDetailsView()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                Text(AppInfo.name)
                    .font(.system(size: 28, weight: .semibold))

                Text("Version \(AppInfo.version) (Build \(AppInfo.build))")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text(AppInfo.tagline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(AppInfo.copyright)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
    }

    private func openLogsFolder() {
        let url = AppInfo.logsDirectory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

private struct LicenseDetailsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Licenses")
                    .font(.title2.weight(.semibold))

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            Text("HostDeck is open source under the MIT License and uses the following platform technologies and bundled open-source components.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                LicenseItem(
                    name: "HostDeck",
                    detail: "Released under the MIT License. Copyright © 2026 byu_rself."
                )

                LicenseItem(
                    name: "Swift / SwiftUI",
                    detail: "Apple platform technologies used to build the native macOS app experience."
                )

                LicenseItem(
                    name: "libssh2",
                    detail: "SSH2 client library used for SSH and SFTP transport. libssh2 is distributed under a BSD-style license."
                )

                LicenseItem(
                    name: "xterm.js",
                    detail: "Terminal web assets used for the embedded terminal surface. xterm.js is distributed under the MIT License."
                )
            }

            Text("See the repository LICENSE file for the full HostDeck MIT License text. Third-party components retain their own licenses.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                NSWorkspace.shared.open(AppInfo.licenseURL)
            } label: {
                Label("Open Full License", systemImage: "doc.text")
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

private struct LicenseItem: View {
    let name: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.headline)

            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
    }
}

private struct DependencyRow: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Label(title, systemImage: "checkmark.circle")
            .foregroundStyle(.secondary)
    }
}
