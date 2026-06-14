import CLibSSH2
import Darwin
import Foundation

actor LibSSH2SFTPClient: SFTPClient {
    private var session: OpaquePointer?
    private var sftp: OpaquePointer?
    private var socketFD: Int32 = -1

    deinit {
        if let sftp {
            libssh2_sftp_shutdown(sftp)
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

        guard let sftp = libssh2_sftp_init(session) else {
            throw lastError("SFTP initialization failed")
        }
        self.sftp = sftp
    }

    func disconnect() async {
        closeConnection()
    }

    func listDirectory(path: String) async throws -> [RemoteFile] {
        guard let sftp else { throw LibSSH2Error.notConnected }

        guard let handle = path.withCString({ pathC in
            libssh2_sftp_open_ex(
                sftp,
                pathC,
                UInt32(strlen(pathC)),
                UInt(LIBSSH2_FXF_READ),
                0,
                LIBSSH2_SFTP_OPENDIR
            )
        }) else {
            throw lastError("Could not open remote directory \(path)")
        }
        defer { libssh2_sftp_close_handle(handle) }

        var files: [RemoteFile] = []
        var buffer = [CChar](repeating: 0, count: 4096)

        while true {
            var attrs = LIBSSH2_SFTP_ATTRIBUTES()
            let rc = libssh2_sftp_readdir_ex(
                handle,
                &buffer,
                buffer.count,
                nil,
                0,
                &attrs
            )

            if rc > 0 {
                let name = String(bytes: buffer.prefix(Int(rc)).map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? ""
                guard name != "." && !name.isEmpty else { continue }
                files.append(remoteFile(name: name, attrs: attrs))
            } else if rc == 0 {
                break
            } else {
                throw lastError("Could not read remote directory \(path)")
            }
        }

        return files.sorted { lhs, rhs in
            if lhs.kind == .directory && rhs.kind != .directory { return true }
            if lhs.kind != .directory && rhs.kind == .directory { return false }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func upload(
        localURL: URL,
        remotePath: String,
        shouldCancel: @Sendable () -> Bool,
        progress: @Sendable (Int64, Int64) async -> Void
    ) async throws {
        _ = try requireSFTP()
        try checkCancellation(shouldCancel)
        let totalBytes = LocalFile.totalBytes(at: localURL)
        await progress(0, totalBytes)

        let values = try localURL.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true {
            _ = try await uploadDirectory(
                localURL: localURL,
                remotePath: remotePath,
                transferredBytes: 0,
                totalBytes: totalBytes,
                shouldCancel: shouldCancel,
                progress: progress
            )
        } else {
            _ = try await uploadFile(
                localURL: localURL,
                remotePath: remotePath,
                transferredBytes: 0,
                totalBytes: totalBytes,
                shouldCancel: shouldCancel,
                progress: progress
            )
        }
    }

    func download(
        remotePath: String,
        localURL: URL,
        shouldCancel: @Sendable () -> Bool,
        progress: @Sendable (Int64, Int64) async -> Void
    ) async throws {
        _ = try requireSFTP()
        try checkCancellation(shouldCancel)
        let attrs = try remoteAttributes(path: remotePath)
        let kind = kind(from: attrs)
        let totalBytes = try remoteTotalBytes(path: remotePath, kind: kind)
        await progress(0, totalBytes)

        if kind == .directory {
            _ = try await downloadDirectory(
                remotePath: remotePath,
                localURL: localURL,
                transferredBytes: 0,
                totalBytes: totalBytes,
                shouldCancel: shouldCancel,
                progress: progress
            )
        } else {
            _ = try await downloadFile(
                remotePath: remotePath,
                localURL: localURL,
                transferredBytes: 0,
                totalBytes: totalBytes,
                shouldCancel: shouldCancel,
                progress: progress
            )
        }
    }

    private func uploadDirectory(
        localURL: URL,
        remotePath: String,
        transferredBytes: Int64,
        totalBytes: Int64,
        shouldCancel: @Sendable () -> Bool,
        progress: @Sendable (Int64, Int64) async -> Void
    ) async throws -> Int64 {
        try checkCancellation(shouldCancel)
        try ensureRemoteDirectory(path: remotePath)

        let children = try FileManager.default.contentsOfDirectory(
            at: localURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var transferredBytes = transferredBytes
        for child in children {
            try checkCancellation(shouldCancel)
            let childRemotePath = remotePath.appendingPathComponent(child.lastPathComponent)
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])

            if values.isDirectory == true {
                transferredBytes = try await uploadDirectory(
                    localURL: child,
                    remotePath: childRemotePath,
                    transferredBytes: transferredBytes,
                    totalBytes: totalBytes,
                    shouldCancel: shouldCancel,
                    progress: progress
                )
            } else {
                transferredBytes = try await uploadFile(
                    localURL: child,
                    remotePath: childRemotePath,
                    transferredBytes: transferredBytes,
                    totalBytes: totalBytes,
                    shouldCancel: shouldCancel,
                    progress: progress
                )
            }
        }

        return transferredBytes
    }

    private func uploadFile(
        localURL: URL,
        remotePath: String,
        transferredBytes: Int64,
        totalBytes: Int64,
        shouldCancel: @Sendable () -> Bool,
        progress: @Sendable (Int64, Int64) async -> Void
    ) async throws -> Int64 {
        try checkCancellation(shouldCancel)
        let sftp = try requireSFTP()
        try ensureRemoteDirectory(path: remotePath.deletingLastPathComponent)

        guard let handle = remotePath.withCString({ remotePathC in
            libssh2_sftp_open_ex(
                sftp,
                remotePathC,
                UInt32(strlen(remotePathC)),
                UInt(LIBSSH2_FXF_WRITE | LIBSSH2_FXF_CREAT | LIBSSH2_FXF_TRUNC),
                0o644,
                LIBSSH2_SFTP_OPENFILE
            )
        }) else {
            throw lastError("Could not open remote file \(remotePath)")
        }
        defer { libssh2_sftp_close_handle(handle) }

        let fileHandle = try FileHandle(forReadingFrom: localURL)
        defer { try? fileHandle.close() }

        var transferredBytes = transferredBytes
        while let data = try fileHandle.read(upToCount: 32_768), !data.isEmpty {
            try checkCancellation(shouldCancel)
            var writtenInChunk = 0
            try data.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.bindMemory(to: CChar.self).baseAddress else { return }

                while writtenInChunk < data.count {
                    try checkCancellation(shouldCancel)
                    let remaining = data.count - writtenInChunk
                    let written = libssh2_sftp_write(handle, base.advanced(by: writtenInChunk), remaining)
                    if written < 0 {
                        throw lastError("Could not write remote file \(remotePath)")
                    }
                    writtenInChunk += written
                }
            }
            transferredBytes += Int64(writtenInChunk)
            await progress(transferredBytes, totalBytes)
        }

        return transferredBytes
    }

    private func downloadDirectory(
        remotePath: String,
        localURL: URL,
        transferredBytes: Int64,
        totalBytes: Int64,
        shouldCancel: @Sendable () -> Bool,
        progress: @Sendable (Int64, Int64) async -> Void
    ) async throws -> Int64 {
        try checkCancellation(shouldCancel)
        try FileManager.default.createDirectory(at: localURL, withIntermediateDirectories: true)

        var transferredBytes = transferredBytes
        let children = try await listDirectory(path: remotePath)
            .filter { $0.name != "." && $0.name != ".." }

        for child in children {
            try checkCancellation(shouldCancel)
            let childRemotePath = remotePath.appendingPathComponent(child.name)
            let childLocalURL = localURL.appending(path: child.name)

            switch child.kind {
            case .directory:
                transferredBytes = try await downloadDirectory(
                    remotePath: childRemotePath,
                    localURL: childLocalURL,
                    transferredBytes: transferredBytes,
                    totalBytes: totalBytes,
                    shouldCancel: shouldCancel,
                    progress: progress
                )
            case .file:
                transferredBytes = try await downloadFile(
                    remotePath: childRemotePath,
                    localURL: childLocalURL,
                    transferredBytes: transferredBytes,
                    totalBytes: totalBytes,
                    shouldCancel: shouldCancel,
                    progress: progress
                )
            case .symlink:
                continue
            }
        }

        return transferredBytes
    }

    private func downloadFile(
        remotePath: String,
        localURL: URL,
        transferredBytes: Int64,
        totalBytes: Int64,
        shouldCancel: @Sendable () -> Bool,
        progress: @Sendable (Int64, Int64) async -> Void
    ) async throws -> Int64 {
        try checkCancellation(shouldCancel)
        let sftp = try requireSFTP()

        guard let handle = remotePath.withCString({ remotePathC in
            libssh2_sftp_open_ex(
                sftp,
                remotePathC,
                UInt32(strlen(remotePathC)),
                UInt(LIBSSH2_FXF_READ),
                0,
                LIBSSH2_SFTP_OPENFILE
            )
        }) else {
            throw lastError("Could not open remote file \(remotePath)")
        }
        defer { libssh2_sftp_close_handle(handle) }

        try FileManager.default.createDirectory(at: localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: localURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: localURL)
        defer { try? fileHandle.close() }

        var transferredBytes = transferredBytes
        var buffer = [CChar](repeating: 0, count: 32_768)

        while true {
            try checkCancellation(shouldCancel)
            let readCount = libssh2_sftp_read(handle, &buffer, buffer.count)
            if readCount > 0 {
                let data = Data(buffer.prefix(readCount).map { UInt8(bitPattern: $0) })
                try fileHandle.write(contentsOf: data)
                transferredBytes += Int64(readCount)
                await progress(transferredBytes, totalBytes)
            } else if readCount == 0 {
                break
            } else {
                throw lastError("Could not read remote file \(remotePath)")
            }
        }

        return transferredBytes
    }

    private func remoteTotalBytes(path: String, kind: RemoteFile.Kind) throws -> Int64 {
        switch kind {
        case .file:
            return Int64(try remoteAttributes(path: path).filesize)
        case .symlink:
            return 0
        case .directory:
            return try listDirectoryForRecursion(path: path).reduce(Int64(0)) { total, child in
                let childPath = path.appendingPathComponent(child.name)
                if child.kind == .directory {
                    return total + (try remoteTotalBytes(path: childPath, kind: .directory))
                }
                return total + (child.kind == .file ? child.size : 0)
            }
        }
    }

    private func listDirectoryForRecursion(path: String) throws -> [RemoteFile] {
        guard let sftp else { throw LibSSH2Error.notConnected }

        guard let handle = path.withCString({ pathC in
            libssh2_sftp_open_ex(
                sftp,
                pathC,
                UInt32(strlen(pathC)),
                UInt(LIBSSH2_FXF_READ),
                0,
                LIBSSH2_SFTP_OPENDIR
            )
        }) else {
            throw lastError("Could not open remote directory \(path)")
        }
        defer { libssh2_sftp_close_handle(handle) }

        var files: [RemoteFile] = []
        var buffer = [CChar](repeating: 0, count: 4096)

        while true {
            var attrs = LIBSSH2_SFTP_ATTRIBUTES()
            let rc = libssh2_sftp_readdir_ex(handle, &buffer, buffer.count, nil, 0, &attrs)
            if rc > 0 {
                let name = String(bytes: buffer.prefix(Int(rc)).map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? ""
                guard !["", ".", ".."].contains(name) else { continue }
                files.append(remoteFile(name: name, attrs: attrs))
            } else if rc == 0 {
                break
            } else {
                throw lastError("Could not read remote directory \(path)")
            }
        }

        return files
    }

    private func ensureRemoteDirectory(path: String) throws {
        guard path != "/" else { return }
        let sftp = try requireSFTP()
        let parent = path.deletingLastPathComponent
        if parent != path {
            try ensureRemoteDirectory(path: parent)
        }

        let result = path.withCString { pathC in
            libssh2_sftp_mkdir_ex(sftp, pathC, UInt32(strlen(pathC)), 0o755)
        }

        if result == 0 { return }

        if let attrs = try? remoteAttributes(path: path), kind(from: attrs) == .directory {
            return
        }

        throw lastError("Could not create remote directory \(path)")
    }

    private func remoteAttributes(path: String) throws -> LIBSSH2_SFTP_ATTRIBUTES {
        let sftp = try requireSFTP()
        var attrs = LIBSSH2_SFTP_ATTRIBUTES()
        let result = path.withCString { pathC in
            libssh2_sftp_stat_ex(sftp, pathC, UInt32(strlen(pathC)), LIBSSH2_SFTP_LSTAT, &attrs)
        }

        guard result == 0 else {
            throw lastError("Could not stat remote path \(path)")
        }

        return attrs
    }

    private func requireSFTP() throws -> OpaquePointer {
        guard let sftp else { throw LibSSH2Error.notConnected }
        return sftp
    }

    private func checkCancellation(_ shouldCancel: @Sendable () -> Bool) throws {
        if shouldCancel() {
            throw CancellationError()
        }
    }

    private func kind(from attrs: LIBSSH2_SFTP_ATTRIBUTES) -> RemoteFile.Kind {
        let permissions = UInt32(attrs.permissions)
        if (permissions & UInt32(LIBSSH2_SFTP_S_IFMT)) == UInt32(LIBSSH2_SFTP_S_IFDIR) {
            return .directory
        }
        if (permissions & UInt32(LIBSSH2_SFTP_S_IFMT)) == UInt32(LIBSSH2_SFTP_S_IFLNK) {
            return .symlink
        }
        return .file
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

    private func remoteFile(name: String, attrs: LIBSSH2_SFTP_ATTRIBUTES) -> RemoteFile {
        let permissions = UInt32(attrs.permissions)
        let kind: RemoteFile.Kind
        if (permissions & UInt32(LIBSSH2_SFTP_S_IFMT)) == UInt32(LIBSSH2_SFTP_S_IFDIR) {
            kind = .directory
        } else if (permissions & UInt32(LIBSSH2_SFTP_S_IFMT)) == UInt32(LIBSSH2_SFTP_S_IFLNK) {
            kind = .symlink
        } else {
            kind = .file
        }

        return RemoteFile(
            name: name,
            kind: kind,
            size: Int64(attrs.filesize),
            modifiedAt: attrs.mtime > 0 ? Date(timeIntervalSince1970: TimeInterval(attrs.mtime)) : .distantPast,
            permissions: permissionString(permissions)
        )
    }

    private func permissionString(_ permissions: UInt32) -> String {
        let bits: [(UInt32, Character)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"),
            (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x")
        ]
        return String(bits.map { permissions & $0.0 == 0 ? "-" : $0.1 })
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
        if let sftp {
            libssh2_sftp_shutdown(sftp)
            self.sftp = nil
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

enum LibSSH2Error: LocalizedError {
    case initializationFailed
    case sessionCreationFailed
    case notConnected
    case socketError(String)
    case missingSecret(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .initializationFailed:
            "Could not initialize libssh2."
        case .sessionCreationFailed:
            "Could not create SSH session."
        case .notConnected:
            "SFTP is not connected."
        case .socketError(let message), .missingSecret(let message), .operationFailed(let message):
            message
        }
    }
}
