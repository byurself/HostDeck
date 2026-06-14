import CLibSSH2
import Darwin
import Foundation

actor LibSSH2SSHClient: SSHClient {
    private var session: OpaquePointer?
    private var channel: OpaquePointer?
    private var socketFD: Int32 = -1
    private var outputHandler: (@Sendable (String) async -> Void)?
    private var readTask: Task<Void, Never>?

    deinit {
        if let channel {
            libssh2_channel_close(channel)
            libssh2_channel_free(channel)
        }

        if let session {
            libssh2_session_disconnect_ex(session, SSH_DISCONNECT_BY_APPLICATION, "HostDeck disconnect", "")
            libssh2_session_free(session)
        }

        if socketFD >= 0 {
            Darwin.close(socketFD)
        }
    }

    func connect(profile: ServerProfile, secret: CredentialSecret?) async throws {
        closeConnection()

        guard libssh2_init(0) == 0 else {
            throw LibSSH2Error.initializationFailed
        }

        socketFD = try openSocket(host: profile.host, port: profile.port)

        guard let session = libssh2_session_init_ex(nil, nil, nil, nil) else {
            closeSocket()
            throw LibSSH2Error.sessionCreationFailed
        }
        self.session = session
        libssh2_session_set_blocking(session, 1)

        guard libssh2_session_handshake(session, socketFD) == 0 else {
            throw lastError("SSH handshake failed")
        }

        try authenticate(profile: profile, secret: secret, session: session)

        guard let channel = libssh2_channel_open_ex(
            session,
            "session",
            UInt32(strlen("session")),
            2 * 1024 * 1024,
            32_768,
            nil,
            0
        ) else {
            throw lastError("Could not open SSH channel")
        }
        self.channel = channel

        guard libssh2_channel_request_pty_ex(
            channel,
            "xterm-256color",
            UInt32(strlen("xterm-256color")),
            nil,
            0,
            120,
            36,
            0,
            0
        ) == 0 else {
            throw lastError("Could not request PTY")
        }

        _ = libssh2_channel_request_pty_size_ex(channel, 120, 36, 0, 0)

        guard libssh2_channel_process_startup(channel, "shell", UInt32(strlen("shell")), nil, 0) == 0 else {
            throw lastError("Could not start remote shell")
        }

        libssh2_channel_set_blocking(channel, 0)
        libssh2_session_set_blocking(session, 0)

        startReadLoop()
    }

    func disconnect() async {
        closeConnection()
    }

    func send(command: String) async throws -> String {
        guard let channel else { throw SSHClientError.notConnected }
        try writeToChannel(command + "\n", channel: channel)
        return ""
    }

    func sendRaw(_ text: String) async throws {
        guard let channel else { throw SSHClientError.notConnected }
        try writeToChannel(text, channel: channel)
    }

    func resize(columns: Int, rows: Int) async {
        guard let channel else { return }
        libssh2_channel_request_pty_size_ex(channel, Int32(columns), Int32(rows), 0, 0)
    }

    func setOutputHandler(_ handler: (@Sendable (String) async -> Void)?) async {
        outputHandler = handler
    }

    private func writeToChannel(_ text: String, channel: OpaquePointer) throws {
        let bytes = Array(text.utf8)

        try bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            var sent = 0
            while sent < bytes.count {
                let written = libssh2_channel_write_ex(channel, 0, base.advanced(by: sent), bytes.count - sent)
                if written == LIBSSH2_ERROR_EAGAIN {
                    usleep(25_000)
                    continue
                }
                if written < 0 {
                    throw lastError("Could not write to remote shell")
                }
                sent += written
            }
        }
    }

    private func startReadLoop() {
        readTask?.cancel()
        readTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                do {
                    let chunk = try await self.readAvailableChunk()
                    if !chunk.isEmpty {
                        await self.emitOutput(chunk)
                    } else {
                        try await Task.sleep(for: .milliseconds(25))
                    }
                } catch {
                    return
                }
            }
        }
    }

    private func emitOutput(_ chunk: String) async {
        await outputHandler?(chunk)
    }

    private func readAvailableChunk() throws -> String {
        guard let channel else { throw SSHClientError.notConnected }

        var buffer = [CChar](repeating: 0, count: 16_384)
        var data = Data()

        while true {
            let readCount = libssh2_channel_read_ex(channel, 0, &buffer, buffer.count)

            if readCount > 0 {
                data.append(contentsOf: buffer.prefix(readCount).map { UInt8(bitPattern: $0) })
                continue
            }

            if readCount == LIBSSH2_ERROR_EAGAIN || readCount == 0 {
                break
            }

            throw lastError("Could not read from remote shell")
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    private func authenticate(profile: ServerProfile, secret: CredentialSecret?, session: OpaquePointer) throws {
        switch profile.authMethod {
        case .password:
            guard case .password(let password) = secret else {
                throw LibSSH2Error.missingSecret("Password is missing. Edit the server and save its password.")
            }
            let result = profile.username.withCString { usernameC in
                password.withCString { passwordC in
                    libssh2_userauth_password_ex(
                        session,
                        usernameC,
                        UInt32(strlen(usernameC)),
                        passwordC,
                        UInt32(strlen(passwordC)),
                        nil
                    )
                }
            }
            guard result == 0 else { throw lastError("Password authentication failed") }

        case .privateKey:
            let keyPath = profile.privateKeyPath.expandingTildeInPath
            guard FileManager.default.fileExists(atPath: keyPath) else {
                throw LibSSH2Error.missingSecret("Private key not found at \(profile.privateKeyPath).")
            }

            let passphrase: String?
            if case .privateKey(let savedPassphrase) = secret {
                passphrase = savedPassphrase
            } else {
                passphrase = nil
            }

            let result = profile.username.withCString { usernameC in
                keyPath.withCString { privateKeyC in
                    if let passphrase {
                        return passphrase.withCString { passphraseC in
                            libssh2_userauth_publickey_fromfile_ex(
                                session,
                                usernameC,
                                UInt32(strlen(usernameC)),
                                nil,
                                privateKeyC,
                                passphraseC
                            )
                        }
                    }

                    return libssh2_userauth_publickey_fromfile_ex(
                        session,
                        usernameC,
                        UInt32(strlen(usernameC)),
                        nil,
                        privateKeyC,
                        nil
                    )
                }
            }
            guard result == 0 else { throw lastError("Private key authentication failed") }

        case .agent:
            guard let agent = libssh2_agent_init(session) else {
                throw lastError("Could not initialize SSH agent")
            }
            defer {
                libssh2_agent_disconnect(agent)
                libssh2_agent_free(agent)
            }

            guard libssh2_agent_connect(agent) == 0 else {
                throw lastError("Could not connect to SSH agent")
            }
            guard libssh2_agent_list_identities(agent) == 0 else {
                throw lastError("Could not list SSH agent identities")
            }

            var identity: UnsafeMutablePointer<libssh2_agent_publickey>?
            var previous: UnsafeMutablePointer<libssh2_agent_publickey>?
            while libssh2_agent_get_identity(agent, &identity, previous) == 0 {
                if let identity {
                    let result = profile.username.withCString { usernameC in
                        libssh2_agent_userauth(agent, usernameC, identity)
                    }
                    if result == 0 { return }
                    previous = identity
                }
            }

            throw lastError("SSH agent authentication failed")
        }
    }

    private func openSocket(host: String, port: Int) throws -> Int32 {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, "\(port)", &hints, &result)
        guard status == 0, let result else {
            throw LibSSH2Error.socketError(String(cString: gai_strerror(status)))
        }
        defer { freeaddrinfo(result) }

        var current: UnsafeMutablePointer<addrinfo>? = result
        while let info = current {
            let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
            if fd >= 0 {
                if Darwin.connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 {
                    return fd
                }
                Darwin.close(fd)
            }
            current = info.pointee.ai_next
        }

        throw LibSSH2Error.socketError("Could not connect to \(host):\(port).")
    }

    private func lastError(_ fallback: String) -> LibSSH2Error {
        guard let session else { return .operationFailed(fallback) }
        var messagePointer: UnsafeMutablePointer<CChar>?
        var messageLength: Int32 = 0
        libssh2_session_last_error(session, &messagePointer, &messageLength, 0)

        if let messagePointer, messageLength > 0 {
            return .operationFailed(String(cString: messagePointer))
        }
        return .operationFailed(fallback)
    }

    private func closeConnection() {
        readTask?.cancel()
        readTask = nil

        if let channel {
            libssh2_channel_close(channel)
            libssh2_channel_free(channel)
            self.channel = nil
        }

        if let session {
            libssh2_session_disconnect_ex(session, SSH_DISCONNECT_BY_APPLICATION, "HostDeck disconnect", "")
            libssh2_session_free(session)
            self.session = nil
        }

        closeSocket()
    }

    private func closeSocket() {
        if socketFD >= 0 {
            Darwin.close(socketFD)
            socketFD = -1
        }
    }
}
