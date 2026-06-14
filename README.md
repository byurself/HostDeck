# HostDeck

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black)
![Swift](https://img.shields.io/badge/Swift-5.10-orange)
![Version](https://img.shields.io/badge/version-0.1.0-brightgreen)
![License](https://img.shields.io/badge/license-MIT-blue)

HostDeck is a native macOS workspace for managing remote hosts, SSH terminal sessions, and SFTP file transfers in one focused app.

> Built for people who want a clean, native, SSH + SFTP workflow on macOS.

---

## Overview

HostDeck brings together remote host management, SSH terminal access, SFTP browsing, local file browsing, and file transfer queues in a single macOS app.

The project started from a simple need: I could not find a macOS app that combined SSH and SFTP in a way that felt focused, native, and comfortable to use. Instead of constantly switching between separate terminal and file-transfer tools, I decided to build HostDeck as an all-in-one workspace for daily remote server work.

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

## Download

After each push to the `main` branch, GitHub Actions builds and packages HostDeck automatically.

1. Open the repository on GitHub.
2. Go to the **Actions** tab.
3. Open the latest **Package macOS App** workflow run.
4. Download the `HostDeck-macOS` artifact.
5. Unzip the downloaded artifact.
6. Unzip the included `HostDeck-macOS.zip`.
7. Move `HostDeck.app` to your Applications folder.

> GitHub keeps workflow artifacts for 30 days.

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

---

# HostDeck 中文说明

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black)
![Swift](https://img.shields.io/badge/Swift-5.10-orange)
![Version](https://img.shields.io/badge/version-0.1.0-brightgreen)
![License](https://img.shields.io/badge/license-MIT-blue)

HostDeck 是一个原生 macOS 工作台应用，用于在一个专注的界面中管理远程主机、SSH 终端会话和 SFTP 文件传输。

> 为 macOS 用户打造的轻量、原生、专注的 SSH + SFTP 工作台。

---

## 项目简介

HostDeck 将远程主机管理、SSH 终端连接、SFTP 远程文件浏览、本地文件浏览、上传下载队列整合到一个 macOS 应用中。

做这个项目的起因很简单：我在 Mac 上一直没有找到一款足够顺手、同时集成 SSH 和 SFTP 的软件。日常连接服务器时，经常需要在终端工具和文件传输工具之间来回切换，体验并不够集中。因此我决定自己做一个更符合个人使用习惯的原生 macOS 应用，也就是 HostDeck。

---

## 应用信息

| 项目   | 内容                             |
| ---- | ------------------------------ |
| 版本   | `0.1.0`                        |
| 构建号  | `1`                            |
| 作者   | `byu_rself`                    |
| 系统要求 | macOS 14+                      |
| 开源协议 | MIT                            |
| 主要技术 | Swift、SwiftUI、libssh2、xterm.js |

---

## 功能亮点

* 原生 SwiftUI macOS 界面
* 服务器配置管理
* 密码和私钥认证
* 基于 Keychain 的凭据存储
* SSH 终端会话，内置终端 Web 资源
* SFTP 远程文件浏览
* 本地文件浏览
* 上传和下载传输队列
* 本地 `.app` 和 zip 打包脚本
* 推送到 `main` 分支后通过 GitHub Actions 自动打包

---

## 下载方式

每次推送到 `main` 分支后，GitHub Actions 都会自动构建并打包 HostDeck。

1. 打开 GitHub 仓库页面。
2. 进入 **Actions** 页面。
3. 打开最新的 **Package macOS App** 工作流记录。
4. 下载 `HostDeck-macOS` artifact。
5. 先解压下载到的 artifact。
6. 再解压其中的 `HostDeck-macOS.zip`。
7. 把 `HostDeck.app` 移动到 Applications 文件夹。

> GitHub workflow artifact 会保留 30 天。

当前包使用本地 ad-hoc 签名，暂未进行 Apple notarization 公证。首次运行时 macOS Gatekeeper 可能会提示风险。

如果后续要做正式公开发布，建议补上 Developer ID 签名和 Apple notarization 公证流程。

---

## 环境要求

* macOS 14 或更高版本
* Swift 5.10 或更高版本
* Xcode Command Line Tools
* Homebrew
* `libssh2`

安装系统依赖：

```bash
brew install libssh2
```

---

## 本地构建

构建 debug 可执行文件：

```bash
swift build
```

构建并启动本地 `.app`：

```bash
./script/build_and_run.sh
```

构建、启动并检查进程是否运行：

```bash
./script/build_and_run.sh --verify
```

启动并查看日志：

```bash
./script/build_and_run.sh --logs
```

---

## 本地打包

创建 release `.app` 和 zip 压缩包：

```bash
./script/package_app.sh
```

生成文件位于 `dist/`：

```text
dist/
  HostDeck.app
  HostDeck-macOS.zip
```

`dist/` 已加入 `.gitignore`，不应提交到仓库。

---

## GitHub Actions 自动打包

`.github/workflows/package-macos.yml` 会在以下场景运行：

* 推送到 `main` 分支
* 在 GitHub Actions 页面手动运行

它会执行：

1. 拉取仓库代码。
2. 使用 Homebrew 安装 `libssh2`。
3. 通过 `script/package_app.sh` 构建 release 包。
4. 把 `dist/HostDeck-macOS.zip` 上传为 `HostDeck-macOS` artifact，供下载。

---

## 项目结构

```text
Sources/HostDeck/
  App/          App 入口和共享状态
  Views/        SwiftUI 页面和 macOS 窗口
  Models/       值类型和领域模型
  Stores/       持久化和状态容器
  Services/     SSH、SFTP、Keychain、传输和连接边界
  Support/      工具函数、格式化、偏好设置和应用元数据
  Resources/    App 图标和终端 Web 资源

Sources/CLibSSH2/
  module.modulemap

script/
  build_and_run.sh
  package_app.sh
```

---

## 安全说明

* 不要提交真实主机、用户名、密码、私钥或生成的打包产物。
* 凭据应保存在 Keychain 支持的流程中。
* 远程连接由本机直接连接到你配置的远程主机。
* 修改打包流程后，应确认 `libssh2` 需要的非系统动态库仍然被正确嵌入。

---

## 后续计划

* Developer ID 签名和 Apple notarization 公证
* 优化下载版本的首次启动体验
* 完善 SSH 终端交互能力
* 增强 SFTP 文件操作能力
* 支持主机分组和收藏
* 支持传输历史和失败重试
* 优化应用图标和发布资源

---

## 贡献

欢迎提交 Pull Request。

发起 PR 前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

---

## 致谢

HostDeck 使用了：

* Swift / SwiftUI
* libssh2
* xterm.js terminal web assets

---

## 版权

HostDeck 使用 [MIT License](LICENSE) 开源。

Copyright © 2026 byu_rself.

第三方依赖许可证可在应用内 **About HostDeck** 窗口中查看。
