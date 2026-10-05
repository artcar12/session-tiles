import Foundation

/// One session as the Claude app records it, running or not.
struct AppSessionEntry: Equatable {
    let id: String          // same "local_…" id as a live session's hostSessionId
    let title: String
    let cwd: String
    let lastActivity: Date
    let archived: Bool
}

/// Raw shape of the Claude app's per-session metadata file. Undocumented internal format: every field
/// optional, unknown fields ignored.
private struct AppSessionFile: Decodable {
    let sessionId: String?
    let title: String?
    let cwd: String?
    let lastActivityAt: Double?
    let isArchived: Bool?
}

/// Reads the Claude app's own record of every Code-tab session
/// (`~/Library/Application Support/Claude/claude-code-sessions/<account>/<org>/local_*.json`), so sessions
/// with no running process can be shown as dormant tiles. Polled; only changed files are re-parsed.
/// A missing or unreadable folder just means no dormant sessions.
@MainActor
final class AppSessionIndex: ObservableObject {
    @Published private(set) var entries: [AppSessionEntry] = []

    let directory: URL
    private var timer: Timer?
    private var parsed: [String: (stamp: FileStamp, entry: AppSessionEntry?)] = [:]

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions", isDirectory: true)) {
        self.directory = directory
    }

    func start(pollInterval: TimeInterval = 5) {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let fm = FileManager.default
        var found: [AppSessionEntry] = []
        var seen: Set<String> = []
        let decoder = JSONDecoder()
        // Two levels of id folders, then one file per session.
        for a in (try? fm.contentsOfDirectory(atPath: directory.path)) ?? [] {
            let dirA = directory.appendingPathComponent(a)
            for b in (try? fm.contentsOfDirectory(atPath: dirA.path)) ?? [] {
                let dirB = dirA.appendingPathComponent(b)
                for name in (try? fm.contentsOfDirectory(atPath: dirB.path)) ?? []
                where name.hasPrefix("local_") && name.hasSuffix(".json") {
                    let path = dirB.appendingPathComponent(name).path
                    seen.insert(path)
                    guard let stamp = FileStamp(path: path) else { continue }
                    if let cached = parsed[path], cached.stamp == stamp {
                        if let e = cached.entry { found.append(e) }
                        continue
                    }
                    guard let data = fm.contents(atPath: path),
                          let f = try? decoder.decode(AppSessionFile.self, from: data) else {
                        // Mid-rewrite: keep the last good parse, retry next poll.
                        if let e = parsed[path]?.entry { found.append(e) }
                        continue
                    }
                    var entry: AppSessionEntry?
                    if let id = f.sessionId, let cwd = f.cwd {
                        let title = f.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        entry = AppSessionEntry(
                            id: id,
                            title: title.isEmpty ? (cwd as NSString).lastPathComponent : title,
                            cwd: cwd,
                            lastActivity: Date(timeIntervalSince1970: (f.lastActivityAt ?? 0) / 1000),
                            archived: f.isArchived ?? false)
                    }
                    parsed[path] = (stamp, entry)
                    if let entry { found.append(entry) }
                }
            }
        }
        parsed = parsed.filter { seen.contains($0.key) }
        found.sort { $0.id < $1.id }
        if found != entries { entries = found }
    }
}
