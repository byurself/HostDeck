# Repository Guidelines

## Project Structure & Module Organization

HostDeck is a SwiftPM macOS 14 SwiftUI app. The executable target lives in `Sources/HostDeck`, with app entry and shared state in `App/`, SwiftUI screens in `Views/`, data types in `Models/`, persistence/state containers in `Stores/`, SSH/SFTP boundaries in `Services/`, and small utilities in `Support/`. App icons and terminal web assets are under `Sources/HostDeck/Resources`. The C module map for the `libssh2` system library is in `Sources/CLibSSH2`. Build artifacts and app bundles are generated in `dist/` and should not be committed.

## Build, Test, and Development Commands

- `brew install libssh2`: installs the system dependency used by `CLibSSH2`.
- `swift build`: compiles the debug executable and validates package wiring.
- `swift build -c release`: produces the optimized binary used for packaging.
- `./script/build_and_run.sh`: builds a local `.app` bundle in `dist/` and launches it.
- `./script/build_and_run.sh --verify`: launches the app and checks the process is running.
- `./script/build_and_run.sh --logs`: launches and streams app logs.
- `./script/package_app.sh`: creates a locally signed `.app` and zip archive.

## Coding Style & Naming Conventions

Use standard Swift formatting with 4-space indentation, trailing closures where they improve readability, and explicit access control when it clarifies ownership. Name SwiftUI views with a `View` suffix, stores with a `Store` suffix, and protocol-backed transport clients with `Client` suffixes, following existing examples like `SFTPBrowserView`, `ServerProfileStore`, and `SSHClient`. Keep UI independent from transport details by depending on `SSHClient` and `SFTPClient` protocols instead of concrete implementations.

## Testing Guidelines

No `Tests/` target exists yet. When adding tests, create SwiftPM test targets under `Tests/HostDeckTests` and run them with `swift test`. Prefer focused unit tests for models, path utilities, stores, and mockable service behavior. Name test files after the subject, such as `ServerProfileStoreTests.swift`, and test methods with clear behavior names.

## Commit & Pull Request Guidelines

This repository currently has no commit history, so use concise imperative commits such as `Add transfer queue persistence` or `Fix terminal resize handling`. Pull requests should include a short summary, test or verification commands run, screenshots for visible UI changes, and notes for changes touching credentials, Keychain storage, SSH/SFTP behavior, packaging, or bundled resources.

## Security & Configuration Tips

Do not commit real hosts, usernames, private keys, passwords, or generated archives. Keep credentials in Keychain-backed flows, use sample data only for demos, and verify packaging changes still embed non-system dynamic libraries required by `libssh2`.
