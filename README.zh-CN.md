# HostDeck

<p align="center">
  <strong>一个用于 SSH、SFTP 和远程主机管理的原生 macOS 工作台应用。</strong>
</p>

<p align="center">
  <a href="README.md">English</a> | 简体中文
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-black" />
  <img src="https://img.shields.io/badge/Swift-5.10-orange" />
  <img src="https://img.shields.io/badge/version-0.1.0-brightgreen" />
  <img src="https://img.shields.io/badge/license-MIT-blue" />
</p>

---

## 项目简介

HostDeck 是一个原生 macOS 工作台应用，用于在一个专注的界面中管理远程主机、SSH 终端会话和 SFTP 文件传输。

做这个项目的起因很简单：我在 Mac 上一直没有找到一款足够顺手、同时集成 SSH 和 SFTP 的软件。日常连接服务器时，经常需要在终端工具和文件传输工具之间来回切换，体验并不够集中。因此我决定自己做一个更符合个人使用习惯的原生 macOS 应用，也就是 HostDeck。

> 为 macOS 用户打造的轻量、原生、专注的 SSH + SFTP 工作台。

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

## 下载方式

从 GitHub Releases 下载最新版本：

https://github.com/byurself/HostDeck/releases/latest

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
