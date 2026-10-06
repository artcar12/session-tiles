import Foundation
import Darwin

/// Per-process facts read straight from the kernel (no `ps` subprocess). Only works for processes
/// owned by the same user, which is all we need.
enum ProcessTable {
    static func parentPid(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    static func executablePath(of pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard n > 0 else { return nil }
        return String(cString: buf)
    }

    /// argv (without the environment) via KERN_PROCARGS2: an Int32 argc, the exec path, NUL padding,
    /// then argc NUL-terminated strings.
    static func arguments(of pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return nil }
        let argc = buf.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var i = MemoryLayout<Int32>.size
        while i < size && buf[i] != 0 { i += 1 }   // exec path
        while i < size && buf[i] == 0 { i += 1 }   // padding
        var args: [String] = []
        while args.count < argc && i < size {
            let start = i
            while i < size && buf[i] != 0 { i += 1 }
            args.append(String(decoding: buf[start..<i], as: UTF8.self))
            i += 1
        }
        return args
    }
}

/// Looks up a desktop session's live `claude` pid from `~/.claude/sessions/<pid>.json`, for callers
/// (claude-open) that only have the hostSessionId.
public enum LiveSessions {
    public static func pid(forHostSessionId id: String,
                           directory: URL = FileManager.default.homeDirectoryForCurrentUser
                               .appendingPathComponent(".claude/sessions", isDirectory: true)) -> pid_t? {
        struct Entry: Decodable { let pid: Int?; let hostSessionId: String? }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasSuffix(".json") {
            guard let data = FileManager.default.contents(atPath: directory.appendingPathComponent(name).path),
                  let e = try? JSONDecoder().decode(Entry.self, from: data),
                  e.hostSessionId == id, let pid = e.pid, pid > 0,
                  kill(pid_t(pid), 0) == 0 || errno == EPERM else { continue }
            return pid_t(pid)
        }
        return nil
    }
}
