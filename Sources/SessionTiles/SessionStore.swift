import Foundation
import Darwin

/// Reads `~/.claude/sessions`, keeps the live Claude-desktop sessions, and republishes on change.
/// Change detection: a DispatchSource on the directory (files added/removed/renamed) plus a poll,
/// because sessions rewrite their file in place, which doesn't touch the directory.
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    /// Folder unreadable: tiles are cleared and this is shown instead.
    @Published private(set) var fatalError: String?
    /// Some files didn't parse: shown as a banner above the tiles that did.
    @Published private(set) var warning: String?

    let directory: URL
    private var pollTimer: Timer?
    private var dirSource: DispatchSourceFileSystemObject?
    /// Previous successful parse per file, reused for one refresh if a read catches a half-written file.
    private var lastGood: [String: SessionFile] = [:]
    private var failedLastTime: Set<String> = []

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions", isDirectory: true)) {
        self.directory = directory
    }

    func start(pollInterval: TimeInterval = 1.5) {
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        watchDirectoryIfNeeded()

        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch {
            sessions = []
            warning = nil
            fatalError = "Can't read \(displayPath): \(error.localizedDescription)"
            stopWatching()
            return
        }
        fatalError = nil

        var found: [Session] = []
        var failed: Set<String> = []
        var good: [String: SessionFile] = [:]
        let decoder = JSONDecoder()

        for name in names where name.hasSuffix(".json") {
            let path = directory.appendingPathComponent(name).path
            var file: SessionFile?
            if let data = FileManager.default.contents(atPath: path),
               let f = try? decoder.decode(SessionFile.self, from: data), f.pid != nil {
                file = f
                good[name] = f
            } else {
                failed.insert(name)
                file = lastGood[name]  // tolerate one bad read (mid-rewrite)
            }
            guard let f = file, let pid = f.pid, f.entrypoint == "claude-desktop",
                  ProcessCheck.isAlive(pid: pid, procStart: f.procStart) else { continue }
            if let s = Session(f) {
                found.append(s)
            } else {
                failed.insert(name)  // live desktop session missing fields we need
            }
        }

        // Only complain about files that failed twice in a row and whose pid (from the filename) is live.
        let persistent = failed.intersection(failedLastTime).filter { name in
            guard let pid = Int((name as NSString).deletingPathExtension) else { return true }
            return ProcessCheck.isAlive(pid: pid, procStart: nil)
        }
        warning = persistent.isEmpty ? nil
            : "Couldn't parse \(persistent.count) session file(s): \(persistent.sorted().joined(separator: ", ")). The format may have changed."

        failedLastTime = failed
        lastGood = good
        if found != sessions { sessions = found }
    }

    private var displayPath: String {
        directory.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    private func watchDirectoryIfNeeded() {
        guard dirSource == nil else { return }
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend, .attrib], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if src.data.contains(.delete) || src.data.contains(.rename) { self.stopWatching() }
                self.refresh()
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        dirSource = src
    }

    private func stopWatching() {
        dirSource?.cancel()
        dirSource = nil
    }
}

enum ProcessCheck {
    /// Alive per `kill(pid, 0)`. When `procStart` is given and parseable, also require it to match the
    /// process's real start time, so a stale file whose pid was reused by another process is dropped.
    static func isAlive(pid: Int, procStart: String?) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid_t(pid), 0) != 0 && errno != EPERM { return false }
        guard let procStart, let claimed = parseProcStart(procStart),
              let actual = startTime(pid: pid) else { return true }
        return abs(claimed.timeIntervalSince(actual)) < 2
    }

    // procStart looks like asctime() in UTC: "Fri Oct  2 15:17:10 2026".
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return f
    }()

    private static func parseProcStart(_ s: String) -> Date? {
        let collapsed = s.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return formatter.date(from: collapsed)
    }

    private static func startTime(pid: Int) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(pid)]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let tv = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1e6)
    }
}
