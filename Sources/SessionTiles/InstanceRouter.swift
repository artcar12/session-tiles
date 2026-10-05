import AppKit
import Carbon.HIToolbox
import Darwin

/// One running Claude app process and the data folder it was started with.
struct ClaudeInstance: Equatable {
    let pid: pid_t
    /// Standardized `--user-data-dir`, or the default `~/Library/Application Support/Claude`.
    let dataDir: URL
    var name: String { dataDir.lastPathComponent }
}

enum OpenError: LocalizedError {
    case unknownInstance
    case notRunning(String)
    case notPermitted
    case sendFailed(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .unknownInstance:
            return "Couldn't tell which Claude instance this session belongs to, so it wasn't opened."
        case .notRunning(let name):
            return "\(name) isn't running. Start that Claude instance, then click the tile again."
        case .notPermitted:
            return "Session Tiles isn't allowed to control Claude. Enable it in System Settings ▸ Privacy & Security ▸ Automation."
        case .sendFailed(let name, let status):
            return "Couldn't open the session in \(name) (error \(status))."
        }
    }
}

/// Opens a session in the Claude instance that owns it. Several instances of the same app (one per
/// `--user-data-dir`) share a bundle id, so a `claude://` URL handed to LaunchServices lands in whichever
/// one it picks. Instead the owner is worked out from the process tree (live sessions) or from the data
/// folder holding the session's record (dormant ones), and the URL is sent to that pid as a GURL Apple
/// event. Nothing falls back to LaunchServices: a wrong-account open is worse than an error.
enum InstanceRouter {
    static let bundleID = "com.anthropic.claudefordesktop"
    private static let queue = DispatchQueue(label: "SessionTiles.InstanceRouter")

    /// Resolves and delivers off the main thread (process scans, sysctl and the one-time Automation
    /// prompt all block), then reports a failure, if any, on the main actor.
    /// `recordDataDir`: the data folder holding the session's record in the Claude app, if any.
    static func open(_ session: Session, recordDataDir: URL?, onError: @escaping @MainActor (String) -> Void) {
        guard let url = session.deepLink else { return }
        let pid = session.pid
        queue.async {
            do {
                let instance = try resolve(sessionPID: pid, recordDataDir: recordDataDir)
                try deliver(url, to: instance)
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async { MainActor.assumeIsolated { onError(message) } }
            }
        }
    }

    /// The running instance owning the session: the Claude process above the session's own process if it
    /// is live, else the instance whose data folder holds its record.
    static func resolve(sessionPID: Int, recordDataDir: URL?) throws -> ClaudeInstance {
        let instances = runningInstances()
        if sessionPID > 0 {
            var pid = pid_t(sessionPID)
            for _ in 0..<16 {
                guard let parent = parentPID(of: pid), parent > 1 else { break }
                if let owner = instances.first(where: { $0.pid == parent }) { return owner }
                pid = parent
            }
        }
        // Keyed on the data folder, never the account id: the same account folder can exist under both.
        guard let dir = recordDataDir?.standardizedFileURL else { throw OpenError.unknownInstance }
        if let owner = instances.first(where: { $0.dataDir.path == dir.path }) { return owner }
        throw OpenError.notRunning(dir.lastPathComponent)
    }

    static func runningInstances() -> [ClaudeInstance] {
        let defaultDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).compactMap { app in
            let pid = app.processIdentifier
            guard pid > 0, let args = arguments(of: pid) else { return nil }
            let dir = userDataDir(in: args).map { URL(fileURLWithPath: $0, isDirectory: true) } ?? defaultDir
            return ClaudeInstance(pid: pid, dataDir: dir.standardizedFileURL)
        }
    }

    /// `--user-data-dir=<dir>` or `--user-data-dir <dir>`.
    static func userDataDir(in args: [String]) -> String? {
        let flag = "--user-data-dir"
        for (i, arg) in args.enumerated() {
            if arg.hasPrefix(flag + "=") { return String(arg.dropFirst(flag.count + 1)) }
            if arg == flag, i + 1 < args.count { return args[i + 1] }
        }
        return nil
    }

    /// argv via KERN_PROCARGS2: an Int32 argc, the exec path, NUL padding, then argc NUL-terminated args.
    static func arguments(of pid: pid_t) -> [String]? {
        var argmax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&mib, 2, &argmax, &size, nil, 0) == 0, argmax > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: Int(argmax))
        size = buffer.count
        mib = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        let argc = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var i = MemoryLayout<Int32>.size
        while i < size && buffer[i] != 0 { i += 1 }    // exec path
        while i < size && buffer[i] == 0 { i += 1 }    // padding
        var args: [String] = []
        while args.count < argc && i < size {
            let start = i
            while i < size && buffer[i] != 0 { i += 1 }
            args.append(String(decoding: buffer[start..<i], as: UTF8.self))
            i += 1
        }
        return args
    }

    static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    /// Sends the URL to that one process as a GURL event, then an activate event: macOS 14 ignores
    /// NSRunningApplication.activate() from an inactive caller, and Electron's own focus on open-url.
    static func deliver(_ url: URL, to instance: ClaudeInstance) throws {
        let target = NSAppleEventDescriptor(processIdentifier: instance.pid)
        // Asks for consent the first time; blocks until the user answers.
        let permission = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
        switch permission {
        case noErr: break
        case OSStatus(errAEEventNotPermitted), OSStatus(errAEEventWouldRequireUserConsent):
            throw OpenError.notPermitted
        case OSStatus(procNotFound):
            throw OpenError.notRunning(instance.name)
        default:
            throw OpenError.sendFailed(instance.name, permission)
        }

        let gurl = NSAppleEventDescriptor(eventClass: AEEventClass(kInternetEventClass), eventID: AEEventID(kAEGetURL),
                                          targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                                          transactionID: AETransactionID(kAnyTransactionID))
        gurl.setParam(NSAppleEventDescriptor(string: url.absoluteString), forKeyword: keyDirectObject)
        let activate = NSAppleEventDescriptor(eventClass: AEEventClass(kAEMiscStandards), eventID: AEEventID(kAEActivate),
                                              targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                                              transactionID: AETransactionID(kAnyTransactionID))
        for event in [gurl, activate] {
            do {
                try event.sendEvent(options: [.noReply], timeout: 10)
            } catch let error as NSError {
                switch error.code {
                case Int(errAEEventNotPermitted), Int(errAEEventWouldRequireUserConsent): throw OpenError.notPermitted
                case Int(procNotFound): throw OpenError.notRunning(instance.name)
                default: throw OpenError.sendFailed(instance.name, OSStatus(truncatingIfNeeded: error.code))
                }
            }
        }
    }
}
