//
//  POSIXFileOps.swift
//  Markdown Editor
//

import CryptoKit
import Darwin
import Foundation

// REQ-065/067/071/077: narrow descriptor-relative filesystem core.

nonisolated enum POSIXFileOps {
    /// Open an absolute directory path trusted from DocumentGroup. Do not use
    /// `O_NOFOLLOW_ANY` here — system prefixes like `/var` → `/private/var` are normal.
    static func openDirectory(_ path: String, noFollowBeneath: Bool = false) throws -> Int32 {
        var flags: Int32 = O_RDONLY | O_DIRECTORY | O_CLOEXEC
        if noFollowBeneath {
            flags |= O_NOFOLLOW
        }
        let fd = open(path, flags)
        if fd < 0 { throw ImagePlacementError.unsafeDestination }
        return fd
    }

    static func openChildDirectory(parentFD: Int32, name: String) throws -> Int32 {
        let fd = openat(
            parentFD,
            name,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW_ANY | O_RESOLVE_BENEATH
        )
        if fd < 0 { throw ImagePlacementError.unsafeDestination }
        return fd
    }

    static func mkdiratChild(parentFD: Int32, name: String, mode: mode_t = 0o755) throws {
        if mkdirat(parentFD, name, mode) != 0, errno != EEXIST {
            throw ImagePlacementError.writeFailed
        }
    }

    static func fstatIdentity(_ fd: Int32) throws -> FileIdentity {
        var st = stat()
        if fstat(fd, &st) != 0 { throw ImagePlacementError.writeFailed }
        return FileIdentity(device: UInt64(st.st_dev), inode: UInt64(st.st_ino))
    }

    static func isRegularFile(_ fd: Int32) throws -> Bool {
        var st = stat()
        if fstat(fd, &st) != 0 { throw ImagePlacementError.writeFailed }
        return (st.st_mode & S_IFMT) == S_IFREG
    }

    static func openRegularFileNoFollow(_ path: String) throws -> Int32 {
        // Final-component no-follow: reject if the leaf is a symlink. Ancestor system
        // symlinks (e.g. /var) remain traversable for absolute paths.
        let fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        if fd < 0 { throw ImagePlacementError.nonRegularSource }
        do {
            guard try isRegularFile(fd) else {
                close(fd)
                throw ImagePlacementError.nonRegularSource
            }
        } catch {
            close(fd)
            throw error
        }
        return fd
    }

    static func enumerateNames(directoryFD: Int32) throws -> [String] {
        let fd2 = dup(directoryFD)
        if fd2 < 0 { throw ImagePlacementError.writeFailed }
        guard let dir = fdopendir(fd2) else {
            close(fd2)
            throw ImagePlacementError.writeFailed
        }
        defer { closedir(dir) }
        var names: [String] = []
        while let ent = readdir(dir) {
            let name = withUnsafePointer(to: &ent.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            names.append(name)
        }
        return names
    }

    static func streamCopyAndHash(
        fromFD: Int32,
        toPath: String,
        bufferSize: Int = 64 * 1024
    ) throws -> (sha256Hex: String, byteCount: Int) {
        let out = open(toPath, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644)
        if out < 0 { throw ImagePlacementError.writeFailed }
        defer { close(out) }

        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var total = 0
        while true {
            let n = buffer.withUnsafeMutableBytes { read(fromFD, $0.baseAddress, bufferSize) }
            if n < 0 { throw ImagePlacementError.writeFailed }
            if n == 0 { break }
            total += Int(n)
            hasher.update(data: Data(buffer.prefix(Int(n))))
            var written = 0
            while written < n {
                let w = buffer.withUnsafeBytes {
                    write(out, $0.baseAddress!.advanced(by: written), Int(n) - written)
                }
                if w <= 0 { throw ImagePlacementError.writeFailed }
                written += w
            }
        }
        if fsync(out) != 0 { throw ImagePlacementError.writeFailed }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (digest, total)
    }

    static func writeDataExclusive(toPath: String, data: Data) throws {
        let out = open(toPath, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644)
        if out < 0 { throw ImagePlacementError.writeFailed }
        defer { close(out) }
        try data.withUnsafeBytes { raw in
            var written = 0
            let total = raw.count
            while written < total {
                let w = write(out, raw.baseAddress!.advanced(by: written), total - written)
                if w <= 0 { throw ImagePlacementError.writeFailed }
                written += w
            }
        }
        if fsync(out) != 0 { throw ImagePlacementError.writeFailed }
    }

    static func renameExclusive(fromDir: Int32, fromName: String, toDir: Int32, toName: String) throws {
        let rc = renameatx_np(fromDir, fromName, toDir, toName, UInt32(RENAME_EXCL))
        if rc == 0 { return }
        if errno == EEXIST { throw ExclusiveCollision() }
        if errno == ENOTSUP || errno == EINVAL {
            try linkExclusive(fromDir: fromDir, fromName: fromName, toDir: toDir, toName: toName)
            _ = unlinkat(fromDir, fromName, 0)
            return
        }
        throw ImagePlacementError.writeFailed
    }

    static func linkExclusive(fromDir: Int32, fromName: String, toDir: Int32, toName: String) throws {
        let rc = linkat(fromDir, fromName, toDir, toName, 0)
        if rc == 0 { return }
        if errno == EEXIST { throw ExclusiveCollision() }
        throw ImagePlacementError.writeFailed
    }

    static func openChildFileNoFollow(dirFD: Int32, name: String) throws -> Int32 {
        let fd = openat(dirFD, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW_ANY | O_RESOLVE_BENEATH)
        if fd < 0 { throw ImagePlacementError.writeFailed }
        return fd
    }

    @discardableResult
    static func unlinkChildIfIdentityMatches(dirFD: Int32, name: String, expected: FileIdentity) throws -> Bool {
        let fd = openat(dirFD, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW_ANY | O_RESOLVE_BENEATH)
        if fd < 0 { return false }
        defer { close(fd) }
        let current = try fstatIdentity(fd)
        guard current == expected else { return false }
        return unlinkat(dirFD, name, 0) == 0
    }

    static func bytesEqual(fdA: Int32, fdB: Int32, bufferSize: Int = 64 * 1024) throws -> Bool {
        var stA = stat(), stB = stat()
        if fstat(fdA, &stA) != 0 || fstat(fdB, &stB) != 0 { throw ImagePlacementError.writeFailed }
        if stA.st_size != stB.st_size { return false }
        lseek(fdA, 0, SEEK_SET)
        lseek(fdB, 0, SEEK_SET)
        var bufA = [UInt8](repeating: 0, count: bufferSize)
        var bufB = [UInt8](repeating: 0, count: bufferSize)
        while true {
            let nA = bufA.withUnsafeMutableBytes { read(fdA, $0.baseAddress, bufferSize) }
            let nB = bufB.withUnsafeMutableBytes { read(fdB, $0.baseAddress, bufferSize) }
            if nA < 0 || nB < 0 { throw ImagePlacementError.writeFailed }
            if nA != nB { return false }
            if nA == 0 { return true }
            if !bufA.prefix(Int(nA)).elementsEqual(bufB.prefix(Int(nB))) { return false }
        }
    }

    static func path(for dirFD: Int32) throws -> String {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        if fcntl(dirFD, F_GETPATH, &buf) != 0 {
            throw ImagePlacementError.writeFailed
        }
        return String(cString: buf)
    }
}

nonisolated struct ExclusiveCollision: Error {}
