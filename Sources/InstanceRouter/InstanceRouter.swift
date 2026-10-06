import Foundation
import AppKit
import Darwin

/// One Claude desktop account: a `--user-data-dir`, and the pid of its main process if it's running.
public struct ClaudeInstance: Equatable, Sendable {
    public let userDataDir: String
    public let pid: pid_t?

    /// Short display name: the data dir's folder name ("Claude", "Claude-personal").
    public var name: String { (userDataDir as NSString).lastPathComponent }
}

public enum RouteError: Error, LocalizedError, Equatable {
    case unknownOwner(String)
    case consentDenied
    case launchFailed(String)
    case launchTimedOut(String)
    case sendFailed(String, Int)

    public var errorDescription: String? {
        switch self {
        case .unknownOwner(let id):
            return "Can't tell which Claude account owns \(id), so it wasn't opened."
        case .consentDenied:
            return "Not allowed to send links to Claude. Allow it in System Settings › Privacy & Security › Automation."
        case .launchFailed(let why):
            return "Couldn't start that Claude account: \(why)"
        case .launchTimedOut(let name):
            return "Started the \(name) account but it didn't accept the link within 15 s."
        case .sendFailed(let name, let code):
            if code == Int(procNotFound) { return "The \(name) account quit before the link reached it. Click again." }
            return "Couldn't send the link to the \(name) account (error \(code))."
        }
    }

    /// Stable exit codes for claude-open.
    public var exitCode: Int32 {
        switch self {
        case .unknownOwner: return 3
        case .consentDenied: return 4
        case .launchFailed, .launchTimedOut: return 5
        case .sendFailed: return 6
        }
    }
}

public struct OpenResult: Sendable {
    public let instance: ClaudeInstance
    public let launched: Bool
    public let elapsed: TimeInterval
}

/// Opens a Claude desktop session in the instance (account) that owns it. Both accounts run the same
/// Claude.app bundle with different `--user-data-dir`s, so `NSWorkspace.open(url)` would hand the link
/// to whichever process LaunchServices picks. Instead we work out the owning instance and send the
/// GURL Apple Event to that pid only. There is deliberately no fallback to an unrouted open.
///
/// Everything here blocks (process scans, the consent prompt, cold starts): call it off the main thread.
public enum InstanceRouter {
    public static let bundleIdentifier = "com.anthropic.claudefordesktop"
    static let dataDirFlag = "--user-data-dir"
    static let launchTimeout: TimeInterval = 15

    static var appSupport: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true).path
    }
    /// Where Claude keeps its data when started without `--user-data-dir`.
    static var defaultDataDir: String { (appSupport as NSString).appendingPathComponent("Claude") }

    public static func deepLink(hostSessionId: String) -> URL? {
        URL(string: "claude://claude.ai/epitaxy/\(hostSessionId)")
    }

    // MARK: Resolve

    /// The Claude main processes running now, with their data dirs.
    public static func runningInstances() -> [ClaudeInstance] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).compactMap { app in
            let pid = app.processIdentifier
            guard pid > 0, !app.isTerminated else { return nil }
            return ClaudeInstance(userDataDir: dataDir(ofMainPid: pid), pid: pid)
        }
    }

    /// Which account owns a session. `sessionPid` is the pid in `~/.claude/sessions/<pid>.json` (the
    /// session's `claude` process); when it's live we walk its ppid chain to the Claude main process.
    /// Otherwise the account is wherever the desktop index file for `hostSessionId` lives;
    /// `recordDataDir` skips that search when the caller already knows it (the panel's AppSessionIndex).
    public static func resolve(hostSessionId: String, sessionPid: pid_t? = nil,
                               recordDataDir: String? = nil) -> ClaudeInstance? {
        let running = runningInstances()
        if let sessionPid, let main = owningMainPid(of: sessionPid, among: Set(running.compactMap(\.pid))) {
            return ClaudeInstance(userDataDir: dataDir(ofMainPid: main), pid: main)
        }
        guard let dir = recordDataDir.map(normalize) ?? dataDirHoldingIndex(for: hostSessionId) else { return nil }
        return running.first { $0.userDataDir == dir } ?? ClaudeInstance(userDataDir: dir, pid: nil)
    }

    /// The instance for a data dir the caller has already resolved (ccsessiond does its own owner
    /// resolution): `pid` when it's that dir's running main process, else whichever running instance
    /// has the dir, else not running, so `open` starts it.
    public static func instance(dataDir: String, pid: pid_t? = nil) -> ClaudeInstance {
        let dir = normalize(dataDir)
        let running = runningInstances().filter { $0.userDataDir == dir }
        if let pid, let match = running.first(where: { $0.pid == pid }) { return match }
        return running.first ?? ClaudeInstance(userDataDir: dir, pid: nil)
    }

    /// Walks up from `pid` (claude → disclaimer → Claude) until it hits one of the main pids.
    static func owningMainPid(of pid: pid_t, among mains: Set<pid_t>) -> pid_t? {
        var current = pid
        for _ in 0..<16 {
            if mains.contains(current) { return current }
            guard let parent = ProcessTable.parentPid(of: current), parent > 1, parent != current else { return nil }
            current = parent
        }
        return nil
    }

    static func dataDir(ofMainPid pid: pid_t) -> String {
        let args = ProcessTable.arguments(of: pid) ?? []
        var value: String?
        for (i, a) in args.enumerated() {
            if a.hasPrefix(dataDirFlag + "=") {
                value = String(a.dropFirst(dataDirFlag.count + 1))
            } else if a == dataDirFlag, i + 1 < args.count {
                value = args[i + 1]
            }
        }
        return normalize(value ?? defaultDataDir)
    }

    static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
    }

    /// `<appSupport>/<dataDir>/claude-code-sessions/<account>/<org>/<hostSessionId>.json`.
    static func dataDirHoldingIndex(for hostSessionId: String) -> String? {
        let fm = FileManager.default
        let file = hostSessionId + ".json"
        guard !hostSessionId.contains("/"), let dirs = try? fm.contentsOfDirectory(atPath: appSupport) else { return nil }
        for dir in dirs.sorted() where dir.hasPrefix("Claude") {
            let root = (appSupport as NSString).appendingPathComponent(dir)
            let index = (root as NSString).appendingPathComponent("claude-code-sessions")
            guard let accounts = try? fm.contentsOfDirectory(atPath: index) else { continue }
            for account in accounts {
                let accountDir = (index as NSString).appendingPathComponent(account)
                for org in (try? fm.contentsOfDirectory(atPath: accountDir)) ?? [] {
                    let path = (accountDir as NSString).appendingPathComponent(org + "/" + file)
                    if fm.fileExists(atPath: path) { return normalize(root) }
                }
            }
        }
        return nil
    }

    // MARK: Open

    /// Resolve, launch the account if needed, deliver the link to that pid, and bring it forward.
    public static func open(hostSessionId: String, sessionPid: pid_t? = nil,
                            recordDataDir: String? = nil) throws -> OpenResult {
        guard let url = deepLink(hostSessionId: hostSessionId),
              let instance = resolve(hostSessionId: hostSessionId, sessionPid: sessionPid,
                                     recordDataDir: recordDataDir) else {
            throw RouteError.unknownOwner(hostSessionId)
        }
        return try open(url: url, in: instance)
    }

    public static func open(url: URL, in instance: ClaudeInstance) throws -> OpenResult {
        let started = Date()
        if let pid = instance.pid {
            try deliver(url: url, to: pid, name: instance.name)
            return OpenResult(instance: instance, launched: false, elapsed: Date().timeIntervalSince(started))
        }
        let pid = try launch(userDataDir: instance.userDataDir)
        // A just-launched process may not take Apple Events yet (procNotFound); retry until the deadline.
        let deadline = started.addingTimeInterval(launchTimeout)
        while true {
            do {
                try deliver(url: url, to: pid, name: instance.name)
                break
            } catch RouteError.sendFailed(_, let code) where Date() < deadline && retryableDuringLaunch(code) {
                Thread.sleep(forTimeInterval: 0.25)
            } catch RouteError.sendFailed(_, let code) where retryableDuringLaunch(code) {
                throw RouteError.launchTimedOut(instance.name)
            }
        }
        return OpenResult(instance: ClaudeInstance(userDataDir: instance.userDataDir, pid: pid),
                          launched: true, elapsed: Date().timeIntervalSince(started))
    }

    static func retryableDuringLaunch(_ code: Int) -> Bool {
        code == Int(procNotFound) || code == Int(connectionInvalid) || code == Int(errAETimeout)
    }

    /// Starts the account the way `~/Applications/Claude <Account>.app` does
    /// (`open -na Claude.app --args --user-data-dir=<dir>`) and waits for its main pid.
    static func launch(userDataDir: String) throws -> pid_t {
        let name = (userDataDir as NSString).lastPathComponent
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw RouteError.launchFailed("Claude.app not found")
        }
        try? FileManager.default.createDirectory(atPath: userDataDir, withIntermediateDirectories: true)
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.arguments = ["\(dataDirFlag)=\(userDataDir)"]
        config.activates = true

        final class Outcome: @unchecked Sendable { var pid: pid_t?; var error: Error? }
        let outcome = Outcome()
        let done = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { app, error in
            outcome.pid = app?.processIdentifier
            outcome.error = error
            done.signal()
        }
        if done.wait(timeout: .now() + launchTimeout) == .timedOut { throw RouteError.launchTimedOut(name) }
        if let error = outcome.error { throw RouteError.launchFailed(error.localizedDescription) }
        guard let pid = outcome.pid, pid > 0 else { throw RouteError.launchFailed("no process") }
        return pid
    }

    /// Sends `GURL <url>` to exactly `pid`, then activates it. Asks for Automation consent first
    /// (a one-time system prompt) so a refusal is reported as such rather than as a generic failure.
    public static func deliver(url: URL, to pid: pid_t, name: String = "Claude") throws {
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        let permission = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
        switch permission {
        case noErr: break
        case OSStatus(errAEEventNotPermitted), OSStatus(errAEEventWouldRequireUserConsent):
            throw RouteError.consentDenied
        case OSStatus(procNotFound):
            throw RouteError.sendFailed(name, Int(procNotFound))   // retried while a launch settles
        default:
            throw RouteError.sendFailed(name, Int(permission))
        }

        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kInternetEventClass),
                                           eventID: AEEventID(kAEGetURL),
                                           targetDescriptor: target,
                                           returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: url.absoluteString), forKeyword: keyDirectObject)
        do {
            _ = try event.sendEvent(options: [.noReply], timeout: 10)
        } catch let error as NSError {
            if error.code == Int(errAEEventNotPermitted) || error.code == Int(errAEEventWouldRequireUserConsent) {
                throw RouteError.consentDenied
            }
            throw RouteError.sendFailed(name, error.code)
        }

        // Bring it forward. NSRunningApplication.activate() from an inactive caller (this CLI, a
        // non-activating panel) is ignored under macOS 14 cooperative activation, and so is the app's
        // own focus call in its open-url handler. An `activate` Apple Event (what AppleScript's
        // `tell application … to activate` sends) makes the target activate itself, which is allowed.
        let activate = NSAppleEventDescriptor(eventClass: AEEventClass(kAEMiscStandards),
                                              eventID: AEEventID(kAEActivate),
                                              targetDescriptor: target,
                                              returnID: AEReturnID(kAutoGenerateReturnID),
                                              transactionID: AETransactionID(kAnyTransactionID))
        _ = try? activate.sendEvent(options: [.noReply], timeout: 10)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }
}
