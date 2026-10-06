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
