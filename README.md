# HostDeck

<p align="center">
  <strong>A native macOS workspace for SSH, SFTP, and remote host management.</strong>
</p>

<p align="center">
  English | <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-black" />
  <img src="https://img.shields.io/badge/Swift-5.10-orange" />
  <img src="https://img.shields.io/badge/version-0.1.0-brightgreen" />
  <img src="https://img.shields.io/badge/license-MIT-blue" />
</p>

---

## Overview

HostDeck is a native macOS workspace for managing remote hosts, SSH terminal sessions, and SFTP file transfers in one focused app.

The project started from a simple need: I could not find a macOS app that combined SSH and SFTP in a way that felt focused, native, and comfortable to use. Instead of constantly switching between separate terminal and file-transfer tools, I decided to build HostDeck as an all-in-one workspace for daily remote server work.

> Built for people who want a clean, native, SSH + SFTP workflow on macOS.

---

## Highlights

* Native SwiftUI macOS interface
* Server profile management
* Password and private-key authentication
* Keychain-backed credential storage
* SSH terminal sessions powered by bundled terminal web assets
* SFTP remote file browser
* Local file browser
* Upload and download transfer queue
* Local packaging script for `.app` and zip archive
* GitHub Actions workflow for automatic macOS packaging on `main`

---

## App Info

| Item              | Value                             |
| ----------------- | --------------------------------- |
| Version           | `0.1.0`                           |
| Build             | `1`                               |
| Author            | `byu_rself`                       |
| Platform          | macOS 14+                         |
| License           | MIT                               |
| Main technologies | Swift, SwiftUI, libssh2, xterm.js |

---

## Download

Download the latest version from GitHub Releases:

https://github.com/byurself/HostDeck/releases/latest

The current package is locally signed with an ad-hoc signature and is not notarized yet. macOS Gatekeeper may show a warning on first launch.

For a public release channel, the next step is Developer ID signing and Apple notarization.

---

## Requirements

* macOS 14 or later
* Swift 5.10 or later
* Xcode Command Line Tools
* Homebrew
* `libssh2`

Install the system dependency:

```bash
brew install libssh2
```

---

## Build Locally

Build the debug executable:

```bash
swift build
```

Build and launch a local `.app` bundle:

```bash
./script/build_and_run.sh
```

Build, launch, and verify that the process is running:

```bash
./script/build_and_run.sh --verify
```

Launch and stream logs:

```bash
./script/build_and_run.sh --logs
```

---

## Package Locally

Create a release `.app` bundle and zip archive:

```bash
./script/package_app.sh
```

Generated files are written to `dist/`:

```text
dist/
  HostDeck.app
  HostDeck-macOS.zip
```

`dist/` is intentionally ignored by Git.

---

## GitHub Actions Packaging

The workflow in `.github/workflows/package-macos.yml` runs on:

* Pushes to `main`
* Manual runs from the GitHub Actions UI

It performs the following steps:

1. Checks out the repository.
2. Installs `libssh2` with Homebrew.
3. Builds the SwiftPM project in release mode through `script/package_app.sh`.
4. Uploads `dist/HostDeck-macOS.zip` as the `HostDeck-macOS` artifact.

---

## Project Structure

```text
Sources/HostDeck/
  App/          App entry point and shared app state
  Views/        SwiftUI screens and macOS windows
  Models/       Value types and domain models
  Stores/       Persistence and state containers
  Services/     SSH, SFTP, Keychain, transfer, and connection boundaries
  Support/      Small utilities, formatters, preferences, and app metadata
  Resources/    App icons and terminal web assets

Sources/CLibSSH2/
  module.modulemap

script/
  build_and_run.sh
  package_app.sh
```

---

## Security Notes

* Do not commit real hosts, usernames, passwords, private keys, or generated archives.
* Credentials should stay in Keychain-backed flows.
* Remote connections are made directly from your Mac to the hosts you configure.
* Packaging changes should be verified to ensure non-system dynamic libraries required by `libssh2` are embedded correctly.

---

## Roadmap

* Developer ID signing and Apple notarization
* Better first-launch experience for downloaded builds
* More complete terminal interaction support
* More advanced SFTP operations
* Host grouping and favorites
* Transfer history and retry support
* Improved app icon and release assets

---

## Contributing

Pull requests are welcome.

Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a PR.

---

## Acknowledgements

HostDeck uses:

* Swift / SwiftUI
* libssh2
* xterm.js terminal web assets

---

## License

HostDeck is open source under the [MIT License](LICENSE).

Copyright © 2026 byu_rself.

Third-party dependency licenses are acknowledged in the app's **About HostDeck** window.
