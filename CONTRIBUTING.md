# Contributing to HostDeck

Thanks for your interest in improving HostDeck. Small fixes, documentation updates, bug reports, and focused feature pull requests are welcome.

## Before You Start

- Check existing issues or pull requests to avoid duplicate work.
- For larger features, open an issue first and describe the problem, proposed direction, and user impact.
- Keep changes focused. A small, reviewable PR is easier to merge than a broad rewrite.

## Development Setup

Install the system dependency:

```bash
brew install libssh2
```

Build the project:

```bash
swift build
```

Run the app locally:

```bash
./script/build_and_run.sh
```

Package the app locally:

```bash
./script/package_app.sh
```

## Pull Request Workflow

1. Fork the repository.
2. Create a feature branch from `main`.
3. Make your changes with clear, focused commits.
4. Run the relevant verification commands.
5. Open a pull request against `main`.

Suggested branch names:

- `fix/terminal-resize`
- `feature/transfer-progress`
- `docs/update-readme`
- `chore/package-script`

Suggested commit style:

```text
Fix terminal resize handling
Add transfer queue persistence
Update GitHub Actions packaging workflow
```

## PR Checklist

Before opening a PR, please confirm:

- `swift build` passes.
- `./script/package_app.sh` passes if you changed packaging, resources, dynamic libraries, or app metadata.
- UI changes include screenshots or a short visual description.
- SSH/SFTP changes describe the test host type or mocked behavior used for verification.
- Credential, Keychain, private key, and security-related changes include a clear risk note.
- Generated files in `dist/`, real credentials, hosts, usernames, passwords, private keys, and certificates are not committed.

## PR Description Template

```markdown
## Summary

- 

## Verification

- [ ] swift build
- [ ] ./script/package_app.sh

## Notes

- 
```

## Code Guidelines

- Follow the existing SwiftPM structure under `Sources/HostDeck`.
- Keep SwiftUI views in `Views/`, models in `Models/`, stores in `Stores/`, SSH/SFTP boundaries in `Services/`, and helpers in `Support/`.
- Keep UI code independent from transport details by depending on `SSHClient` and `SFTPClient` protocols where possible.
- Prefer focused changes over unrelated refactors.
- Do not commit build artifacts or generated app bundles.

## Security

HostDeck manages remote host configuration and credentials, so security-sensitive changes need extra care.

- Do not include real server details or credentials in examples, screenshots, logs, or tests.
- Keep credentials in Keychain-backed flows.
- Be careful with logging around usernames, hosts, paths, authentication failures, and transfer errors.
- For changes touching SSH, SFTP, Keychain, packaging, or dynamic library embedding, include verification details in the PR.

## License

By contributing to HostDeck, you agree that your contribution will be licensed under the MIT License.

---

# HostDeck 贡献指南

感谢你愿意改进 HostDeck。欢迎提交小修复、文档更新、bug 修复，以及范围清晰的功能 PR。

## 开始之前

- 先查看已有 issue 或 PR，避免重复工作。
- 如果是较大的功能，建议先开 issue，说明问题、方案方向和用户影响。
- 请尽量保持改动聚焦。小而清晰的 PR 更容易 review 和合并。

## 开发环境

安装系统依赖：

```bash
brew install libssh2
```

构建项目：

```bash
swift build
```

本地运行：

```bash
./script/build_and_run.sh
```

本地打包：

```bash
./script/package_app.sh
```

## PR 流程

1. Fork 仓库。
2. 从 `main` 创建功能分支。
3. 提交清晰、聚焦的 commits。
4. 运行相关验证命令。
5. 向 `main` 发起 Pull Request。

推荐分支命名：

- `fix/terminal-resize`
- `feature/transfer-progress`
- `docs/update-readme`
- `chore/package-script`

推荐 commit 风格：

```text
Fix terminal resize handling
Add transfer queue persistence
Update GitHub Actions packaging workflow
```

## PR 检查清单

发起 PR 前，请确认：

- `swift build` 通过。
- 如果修改了打包、资源、动态库或 app 元数据，`./script/package_app.sh` 通过。
- UI 改动附带截图或简短视觉说明。
- SSH/SFTP 改动说明使用的测试主机类型或 mock 验证方式。
- 涉及凭据、Keychain、私钥或安全相关改动时，在 PR 中说明风险。
- 不提交 `dist/` 里的生成文件，也不提交真实凭据、主机、用户名、密码、私钥或证书。

## PR 描述模板

```markdown
## Summary

- 

## Verification

- [ ] swift build
- [ ] ./script/package_app.sh

## Notes

- 
```

## 代码规范

- 遵循 `Sources/HostDeck` 下现有的 SwiftPM 结构。
- SwiftUI 视图放在 `Views/`，模型放在 `Models/`，状态和持久化放在 `Stores/`，SSH/SFTP 边界放在 `Services/`，辅助工具放在 `Support/`。
- UI 尽量依赖 `SSHClient` 和 `SFTPClient` 协议，而不是直接依赖具体实现。
- 保持改动聚焦，不夹带无关重构。
- 不提交构建产物或生成的 app bundle。

## 安全

HostDeck 会管理远程主机配置和凭据，因此安全相关改动需要格外谨慎。

- 示例、截图、日志和测试中不要包含真实服务器或凭据。
- 凭据应保存在 Keychain 支持的流程中。
- 记录日志时注意用户名、主机、路径、认证失败和传输错误等信息。
- 如果改动涉及 SSH、SFTP、Keychain、打包或动态库嵌入，请在 PR 中写清验证方式。

## 许可证

向 HostDeck 贡献代码即表示你同意贡献内容使用 MIT License 授权。
