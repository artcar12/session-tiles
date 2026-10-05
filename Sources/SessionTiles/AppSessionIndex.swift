import Foundation

/// One session as the Claude app records it, running or not.
struct AppSessionEntry: Equatable {
    let id: String          // same "local_…" id as a live session's hostSessionId
    let title: String
    let cwd: String
    let lastActivity: Date
    let archived: Bool
    /// The Claude instance's data folder the record lives in ("Claude", "Claude-personal"), which tells
    /// apart sessions of accounts run side by side in separate instances.
    let instance: String
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
/// (`~/Library/Application Support/Claude*/claude-code-sessions/<account>/<org>/local_*.json`), so sessions
/// with no running process can be shown as dormant tiles. Every `Claude*` data folder is read, so a second
/// instance (`--user-data-dir=…/Claude-personal`) is included. Polled; only changed files are re-parsed.
/// A missing or unreadable folder just means no dormant sessions.
@MainActor
final class AppSessionIndex: ObservableObject {
    @Published private(set) var entries: [AppSessionEntry] = []
    /// Account badge per session id, set only when records come from more than one instance.
    @Published private(set) var badges: [String: String] = [:]

    /// nil: find every `Claude*` data folder on each poll.
    let directory: URL?
    private var timer: Timer?
    private var parsed: [String: (stamp: FileStamp, entry: AppSessionEntry?)] = [:]

    private static let appSupport = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support", isDirectory: true)

    /// `directory`: one `claude-code-sessions` folder to read instead of discovering them.
    init(directory: URL? = nil) {
        self.directory = directory
    }

    private func roots() -> [URL] {
        if let directory { return [directory] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: Self.appSupport.path)) ?? []
        return names.filter { $0.hasPrefix("Claude") }.sorted()
            .map { Self.appSupport.appendingPathComponent($0).appendingPathComponent("claude-code-sessions", isDirectory: true) }
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
        // Per instance: two levels of id folders, then one file per session.
        for directory in roots() {
            let instance = directory.deletingLastPathComponent().lastPathComponent
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
                                archived: f.isArchived ?? false,
                                instance: instance)
                        }
                        parsed[path] = (stamp, entry)
                        if let entry { found.append(entry) }
                    }
                }
            }
        }
        parsed = parsed.filter { seen.contains($0.key) }
        found.sort { $0.id < $1.id }
        if found != entries { entries = found }
        let instances = Set(found.map(\.instance))
        let newBadges = instances.count > 1
            ? Dictionary(found.map { ($0.id, AccountBadge.label(instance: $0.instance)) }, uniquingKeysWith: { a, _ in a })
            : [:]
        if newBadges != badges { badges = newBadges }
    }
}

/// The letter on a tile that says which Claude instance (and so which account) a session belongs to.
enum AccountBadge {
    /// UserDefaults dictionary of instance folder name → badge text, e.g. `{Claude = W; "Claude-personal" = P;}`.
    static let defaultsKey = "accountBadges"

    /// Override from `accountBadges`, else the initial of the folder's suffix ("Claude-personal" → "P");
    /// the plain "Claude" folder gets "D" (default instance).
    static func label(instance: String) -> String {
        if let custom = (UserDefaults.standard.dictionary(forKey: defaultsKey)?[instance] as? String)?
            .trimmingCharacters(in: .whitespaces), !custom.isEmpty {
            return String(custom.prefix(2)).uppercased()
        }
        let suffix = instance.dropFirst("Claude".count).drop { $0 == "-" || $0 == "_" || $0 == " " }
        return suffix.first.map { String($0).uppercased() } ?? "D"
    }
}
