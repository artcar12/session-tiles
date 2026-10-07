import Foundation
import InstanceRouter

// claude-open: opens a Claude desktop session in the account (instance) that owns it.
//   claude-open --session <hostSessionId> [--resolve-only]
//   claude-open --data-dir <user data dir> [--pid <claude main pid>] (--url <claude:// url> | --resolve-only)
//   claude-open --pid <claude main pid> --url <claude:// url>
// --data-dir is for callers that resolved the owner themselves (ccsessiond): the pid is used if it's
// still that dir's main process, else the dir's running instance, else the account is started.
// Prints one JSON line {instance, dataDir, pid, delivered, launched, elapsedMs} or {error, code}.
// Exit codes: 0 ok, 2 usage, 3 unknown owner, 4 Automation consent denied, 5 launch failed/timed out,
// 6 send failed.

func emit(_ obj: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

func fail(_ error: RouteError) -> Never {
    emit(["error": error.localizedDescription, "code": Int(error.exitCode)])
    exit(error.exitCode)
}

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    usage: claude-open --session <hostSessionId> [--resolve-only]
           claude-open --data-dir <dir> [--pid <n>] (--url <url> | --resolve-only)
           claude-open --pid <n> --url <url>

    """.utf8))
    exit(2)
}

/// Run as our own responsible process. macOS asks for Automation consent on behalf of the caller's
/// responsible process: from a launchd job (ccsessiond) that is a bare interpreter with no bundle, which
/// can't be prompted, so every send is refused as denied. Re-spawning with responsibility disclaimed
/// makes this signed binary the one that asks (and is listed under Automation). The child does the work
/// on the same stdio; we pass its exit status on. `responsibility_spawnattrs_setdisclaim` is a private
/// libsystem symbol looked up at run time: if it's missing, or any step fails, we just run in-process.
func runDisclaimed() {
    let key = "CLAUDE_OPEN_DISCLAIMED"
    guard getenv(key) == nil,
          let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim") else { return }
    typealias SetDisclaim = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
    var attr: posix_spawnattr_t?
    guard posix_spawnattr_init(&attr) == 0 else { return }
    defer { posix_spawnattr_destroy(&attr) }
    guard unsafeBitCast(sym, to: SetDisclaim.self)(&attr, 1) == 0 else { return }
    var buf = [CChar](repeating: 0, count: 4096)
    guard proc_pidpath(getpid(), &buf, UInt32(buf.count)) > 0 else { return }
    setenv(key, "1", 1)
    var argv: [UnsafeMutablePointer<CChar>?] = CommandLine.arguments.map { strdup($0) } + [nil]
    var child: pid_t = 0
    guard posix_spawn(&child, buf, nil, &attr, &argv, environ) == 0 else { unsetenv(key); return }
    var status: Int32 = 0
    while waitpid(child, &status, 0) == -1 && errno == EINTR {}
    exit((status & 0x7f) == 0 ? (status >> 8) & 0xff : 6)
}
runDisclaimed()

var session: String?, dataDir: String?, pid: pid_t?, url: URL?, resolveOnly = false
var args = CommandLine.arguments.dropFirst()
while let a = args.popFirst() {
    switch a {
    case "--session": session = args.popFirst()
    case "--data-dir": dataDir = args.popFirst()
    case "--pid": pid = args.popFirst().flatMap { pid_t($0) }
    case "--url": url = args.popFirst().flatMap { URL(string: $0) }
    case "--resolve-only": resolveOnly = true
    default: usage()
    }
}

do {
    if let dataDir, session == nil, (url != nil) != resolveOnly {
        let instance = InstanceRouter.instance(dataDir: dataDir, pid: pid)
        guard let url else {
            emit(["instance": instance.name, "dataDir": instance.userDataDir,
                  "pid": instance.pid.map { Int($0) } ?? NSNull(), "delivered": false])
            exit(0)
        }
        let r = try InstanceRouter.open(url: url, in: instance)
        emit(["instance": r.instance.name, "dataDir": r.instance.userDataDir, "pid": Int(r.instance.pid ?? 0),
              "delivered": true, "launched": r.launched, "elapsedMs": Int(r.elapsed * 1000)])
    } else if let session, dataDir == nil, pid == nil, url == nil {
        let sessionPid = LiveSessions.pid(forHostSessionId: session)
        guard let instance = InstanceRouter.resolve(hostSessionId: session, sessionPid: sessionPid),
              let link = InstanceRouter.deepLink(hostSessionId: session) else {
            fail(.unknownOwner(session))
        }
        if resolveOnly {
            emit(["instance": instance.name, "dataDir": instance.userDataDir, "pid": instance.pid.map { Int($0) } ?? NSNull(),
                  "sessionPid": sessionPid.map { Int($0) } ?? NSNull(), "delivered": false])
            exit(0)
        }
        let r = try InstanceRouter.open(url: link, in: instance)
        emit(["instance": r.instance.name, "dataDir": r.instance.userDataDir, "pid": Int(r.instance.pid ?? 0),
              "delivered": true, "launched": r.launched, "elapsedMs": Int(r.elapsed * 1000)])
    } else if let pid, let url, session == nil, dataDir == nil, !resolveOnly {
        let started = Date()
        try InstanceRouter.deliver(url: url, to: pid)
        emit(["pid": Int(pid), "delivered": true, "launched": false,
              "elapsedMs": Int(Date().timeIntervalSince(started) * 1000)])
    } else {
        usage()
    }
} catch let e as RouteError {
    fail(e)
}
