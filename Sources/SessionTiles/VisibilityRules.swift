import Foundation

/// Status-knob positions.
enum StatusFilter: String, CaseIterable, Identifiable {
    case any, waiting, idle, busy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: return "ANY"
        case .waiting: return "WAIT"
        case .idle: return "IDLE"
        case .busy: return "BUSY"
        }
    }
}

/// What the panel's controls are set to. Persisted in UserDefaults under `Keys`.
struct TileFilter: Equatable {
    /// Shows every live session, ignoring the status knob and the standby slider.
    var showAll = false
    var status: StatusFilter = .any
    /// Index into `standbyStops`.
    var standbyStop = TileFilter.defaultStandbyStop

    /// How long an idle (standby) session stays visible; nil keeps it forever.
    static let standbyStops: [TimeInterval?] = [5, 15, 30, 60, 120, 240, 480, 1440].map { $0 * 60 } + [nil]
    static let defaultStandbyStop = 3  // 1h

    var standbyCutoff: TimeInterval? {
        Self.standbyStops[min(max(standbyStop, 0), Self.standbyStops.count - 1)]
    }

    /// "5m", "1h", "24h", "∞"
    static func standbyLabel(_ stop: Int) -> String {
        guard let t = standbyStops[min(max(stop, 0), standbyStops.count - 1)] else { return "∞" }
        let m = Int(t / 60)
        return m < 60 ? "\(m)m" : "\(m / 60)h"
    }

    enum Keys {
        static let showAll = "showAll"
        static let status = "statusFilter"
        static let standbyStop = "standbyStop"
    }

    /// Current settings, for code outside SwiftUI (the debug snapshot).
    static var saved: TileFilter {
        let d = UserDefaults.standard
        var f = TileFilter()
        f.showAll = d.bool(forKey: Keys.showAll)
        f.status = d.string(forKey: Keys.status).flatMap(StatusFilter.init(rawValue:)) ?? .any
        if d.object(forKey: Keys.standbyStop) != nil { f.standbyStop = d.integer(forKey: Keys.standbyStop) }
        return f
    }
}

/// The single place that decides which sessions get a tile and in what order.
enum VisibilityRules {
    struct Result {
        var tiles: [Session]
        /// Live sessions the filter hid.
        var hidden: Int
    }

    static func isVisible(_ s: Session, filter: TileFilter, now: Date) -> Bool {
        if filter.showAll { return true }
        switch filter.status {
        case .any: break
        case .waiting: if s.status != .waiting { return false }
        case .idle: if s.status != .idle { return false }
        case .busy: if s.status != .busy { return false }
        }
        if s.status == .idle, let cutoff = filter.standbyCutoff,
           now.timeIntervalSince(s.statusSince) > cutoff { return false }
        return true
    }

    /// Pinned tiles first, and always shown: a pinned session whose process has gone becomes an offline
    /// tile. Within each group: waiting (oldest first), then idle, then busy, then anything unrecognised,
    /// then offline.
    static func ordered(_ sessions: [Session], pinned: [String: PinnedSession], filter: TileFilter,
                        now: Date) -> Result {
        let liveIDs = Set(sessions.map(\.id))
        let offline = pinned.filter { !liveIDs.contains($0.key) }.map { Session(offline: $0.key, pin: $0.value) }
        let shown = sessions.filter { pinned[$0.id] != nil || isVisible($0, filter: filter, now: now) }
        let tiles = (shown + offline).sorted {
            let p0 = pinned[$0.id] != nil, p1 = pinned[$1.id] != nil
            if p0 != p1 { return p0 }
            if $0.status != $1.status { return $0.status < $1.status }
            if $0.statusSince != $1.statusSince { return $0.statusSince < $1.statusSince }
            return $0.id < $1.id
        }
        return Result(tiles: tiles, hidden: sessions.count - shown.count)
    }
}
