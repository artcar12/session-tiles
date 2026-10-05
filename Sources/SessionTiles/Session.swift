import Foundation

/// Raw shape of `~/.claude/sessions/<pid>.json`. Undocumented internal format:
/// every field is optional and unknown fields are ignored.
struct SessionFile: Decodable {
    let pid: Int?
    let sessionId: String?
    let cwd: String?
    let procStart: String?
    let entrypoint: String?
    let hostSessionId: String?
    let name: String?
    let status: String?
    let waitingFor: String?
    let statusUpdatedAt: Double?
    let updatedAt: Double?
}

enum SessionStatus: Int, Comparable {
    /// `offline` never comes from a file: it marks a pinned session whose process has gone.
    case waiting = 0, idle, busy, unknown, offline

    init(raw: String?) {
        switch raw {
        case "waiting": self = .waiting
        case "idle": self = .idle
        case "busy": self = .busy
        default: self = .unknown
        }
    }

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

struct Session: Identifiable, Equatable {
    let id: String              // hostSessionId
    let pid: Int
    let name: String
    let project: String
    let status: SessionStatus
    let rawStatus: String
    let waitingFor: String?
    let statusSince: Date

    var deepLink: URL? {
        URL(string: "claude://claude.ai/epitaxy/\(id)")
    }

    /// Returns nil when the file lacks what a desktop tile needs.
    init?(_ f: SessionFile) {
        guard let pid = f.pid, let host = f.hostSessionId, !host.isEmpty, let cwd = f.cwd else { return nil }
        id = host
        self.pid = pid
        project = Session.projectName(cwd: cwd)
        let trimmed = f.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        name = trimmed.isEmpty ? (cwd as NSString).lastPathComponent : trimmed
        status = SessionStatus(raw: f.status)
        rawStatus = f.status ?? "?"
        waitingFor = f.waitingFor
        let ms = f.statusUpdatedAt ?? f.updatedAt ?? Date().timeIntervalSince1970 * 1000
        statusSince = Date(timeIntervalSince1970: ms / 1000)
    }

    /// Placeholder tile for a pinned session that is no longer running.
    init(offline id: String, pin: PinnedSession) {
        self.id = id
        pid = 0
        name = pin.name
        project = pin.project
        status = .offline
        rawStatus = "offline"
        waitingFor = nil
        statusSince = pin.lastSeen
    }

    /// Last path component of cwd, with `.claude/worktrees/<name>` collapsed to the repo name.
    static func projectName(cwd: String) -> String {
        var path = cwd
        if let r = path.range(of: "/.claude/worktrees/") {
            path = String(path[..<r.lowerBound])
        }
        let last = (path as NSString).lastPathComponent
        return last.isEmpty ? cwd : last
    }
}
