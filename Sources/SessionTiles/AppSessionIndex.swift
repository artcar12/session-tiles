import Foundation
import Darwin

/// One session as the Claude app records it, running or not.
struct AppSessionEntry: Equatable {
    let id: String          // same "local_…" id as a live session's hostSessionId
    let title: String
    let cwd: String
    let lastActivity: Date
    let archived: Bool
    /// The record file, for `setArchived`.
    let path: String
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

enum ArchiveError: LocalizedError {
    case unknownSession
    case unexpectedFormat(String)

    var errorDescription: String? {
        switch self {
        case .unknownSession: return "The Claude app has no record of this session."
        case .unexpectedFormat(let file):
            return "\(file) doesn't contain a single isArchived flag in the expected form; the format may have changed."
        }
    }
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
                                path: path,
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

    /// Sets the archived flag in the session's record. The running Claude app keeps its session list in
    /// memory and doesn't read this back: the change takes effect in its sidebar after it restarts, and is
    /// reset whenever the app writes the record again (for instance when the session is used). The panel
    /// reads the flag directly, so tiles follow it straight away.
    ///
    /// Only the flag's text is touched (`"isArchived":false` ↔ `true`), so the rest of the file stays
    /// byte-for-byte as the app wrote it; the replacement is written atomically.
    func setArchived(_ id: String, _ archived: Bool) throws {
        guard let entry = entries.first(where: { $0.id == id }) else { throw ArchiveError.unknownSession }
        let url = URL(fileURLWithPath: entry.path)
        let text = try String(contentsOf: url, encoding: .utf8)
        let from = "\"isArchived\":\(!archived)", to = "\"isArchived\":\(archived)"
        if !text.contains(from) && text.components(separatedBy: to).count == 2 { refresh(); return }  // already so
        guard text.components(separatedBy: from).count == 2, !text.contains(to) else {
            throw ArchiveError.unexpectedFormat(url.lastPathComponent)
        }
        // Write a sibling with the original's permissions (the app uses 0600), then rename it over.
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] ?? 0o600
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).sessiontiles")
        guard FileManager.default.createFile(atPath: tmp.path, contents: Data(text.replacingOccurrences(of: from, with: to).utf8),
                                             attributes: [.posixPermissions: perms]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard rename(tmp.path, url.path) == 0 else {
            let err = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            try? FileManager.default.removeItem(at: tmp)
            throw err
        }
        refresh()
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
