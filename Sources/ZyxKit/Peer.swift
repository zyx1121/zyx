import Darwin

/// Finds which Claude Code session sent a request over loopback TCP. Each
/// stickd request is one connection, made by the stick MCP server that the
/// session started, so the session is the process, or the parent of the
/// process, that holds the other end.
public enum Peer {
    /// The session among `sessions` whose process or a process under it
    /// (2 levels down) holds a TCP socket on local port `port`.
    public static func session(fromPort port: UInt16, sessions: [Int32]) -> Int32? {
        sessions.first { session in
            let children = self.children(of: session)
            let candidates = [session] + children + children.flatMap(self.children(of:))
            return candidates.contains { holds($0, port: port) }
        }
    }

    static func children(of pid: Int32) -> [Int32] {
        var buffer = [Int32](repeating: 0, count: 128)
        let bytes = proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(pid), &buffer,
                                  Int32(buffer.count * MemoryLayout<Int32>.size))
        return Array(buffer.prefix(max(0, Int(bytes)) / MemoryLayout<Int32>.size)).filter { $0 > 0 }
    }

    /// Whether `pid` holds a TCP socket bound to local port `port`.
    static func holds(_ pid: Int32, port: UInt16) -> Bool {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return false }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / stride)
        let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, size)
        guard got > 0 else { return false }
        for fd in fds.prefix(Int(got) / stride) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var info = socket_fdinfo()
            let length = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, length) == length,
                  info.psi.soi_kind == Int32(SOCKINFO_TCP) else { continue }
            // The port is in network byte order in the low 16 bits.
            let local = UInt16(truncatingIfNeeded: info.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport)
            if UInt16(bigEndian: local) == port { return true }
        }
        return false
    }
}
