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
    /// Off: pinned tiles are hidden, offline ones included (SHOW ALL still shows live pinned sessions).
    var showPinned = true
    /// Adds dormant tiles: sessions in the Claude app's sidebar with no running process. They follow the
    /// standby window and show for the ANY and IDLE knob positions; with SHOW ALL, every one shows.
    var showDormant = false

    /// How long an idle (standby) or dormant session stays visible; nil keeps it forever.
    static let standbyStops: [TimeInterval?] = [5, 15, 30, 60, 120, 240, 480, 1440, 4320, 10080].map { $0 * 60 } + [nil]
    static let defaultStandbyStop = 3  // 1h

    var standbyCutoff: TimeInterval? {
        Self.standbyStops[min(max(standbyStop, 0), Self.standbyStops.count - 1)]
    }

    /// "5m", "1h", "24h", "3d", "∞"
    static func standbyLabel(_ stop: Int) -> String {
        guard let t = standbyStops[min(max(stop, 0), standbyStops.count - 1)] else { return "∞" }
        let m = Int(t / 60)
        if m > 1440 { return "\(m / 1440)d" }
        return m < 60 ? "\(m)m" : "\(m / 60)h"
    }

    enum Keys {
        static let showAll = "showAll"
        static let status = "statusFilter"
        static let standbyStop = "standbyStop"
        static let showPinned = "showPinned"
        static let showDormant = "showDormant"
    }

    /// Current settings, for code outside SwiftUI (the debug snapshot).
    static var saved: TileFilter {
        let d = UserDefaults.standard
        var f = TileFilter()
        f.showAll = d.bool(forKey: Keys.showAll)
        f.status = d.string(forKey: Keys.status).flatMap(StatusFilter.init(rawValue:)) ?? .any
        if d.object(forKey: Keys.standbyStop) != nil { f.standbyStop = d.integer(forKey: Keys.standbyStop) }
        if d.object(forKey: Keys.showPinned) != nil { f.showPinned = d.bool(forKey: Keys.showPinned) }
        f.showDormant = d.bool(forKey: Keys.showDormant)
        return f
    }
}

/// The single place that decides which sessions get a tile and in what order.
enum VisibilityRules {
    struct Result {
        var tiles: [Session]
        /// Live sessions the filter hid.
        var hidden: Int
        /// Dormant sessions the current filter would show with `showDormant` on.
        var dormant: Int
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

    /// Whether a dormant session (no process) gets a tile, given `showDormant` is on.
    static func isDormantVisible(_ e: AppSessionEntry, filter: TileFilter, now: Date) -> Bool {
        if e.archived { return false }
        if filter.showAll { return true }
        guard filter.status == .any || filter.status == .idle else { return false }
        if let cutoff = filter.standbyCutoff, now.timeIntervalSince(e.lastActivity) > cutoff { return false }
        return true
    }

    /// Pinned tiles first, and always shown: a pinned session whose process has gone becomes an offline
    /// tile. Within each group: waiting (oldest first), then idle, then busy, then anything unrecognised,
    /// then dormant (most recent first), then offline. With `showPinned` off, pinned sessions are hidden
    /// instead (unless `showAll`).
    ///
    /// `index` is the Claude app's own session list: the source of dormant tiles and of the archived flag.
    /// A session flagged archived there gets no tile, pinned or not; SHOW ALL still shows running ones so
    /// they can be unarchived.
    static func ordered(_ sessions: [Session], pinned allPins: [String: PinnedSession], index: [AppSessionEntry] = [],
                        filter: TileFilter, now: Date) -> Result {
        let pinned = filter.showPinned ? allPins : [:]
        let archived = Set(index.filter(\.archived).map(\.id))
        let liveIDs = Set(sessions.map(\.id))
        let offline = pinned.filter { !liveIDs.contains($0.key) && !archived.contains($0.key) }
            .map { Session(offline: $0.key, pin: $0.value) }
        let shown = sessions.filter {
            if archived.contains($0.id) || (!filter.showPinned && allPins[$0.id] != nil) { return filter.showAll }
            return pinned[$0.id] != nil || isVisible($0, filter: filter, now: now)
        }
        let eligible = index
            .filter { !liveIDs.contains($0.id) && allPins[$0.id] == nil && isDormantVisible($0, filter: filter, now: now) }
        let asleep = filter.showDormant ? eligible.map(Session.init(dormant:)) : []
        let tiles = (shown + offline + asleep).sorted {
            let p0 = pinned[$0.id] != nil, p1 = pinned[$1.id] != nil
            if p0 != p1 { return p0 }
            if $0.status != $1.status { return $0.status < $1.status }
            if $0.statusSince != $1.statusSince {
                return $0.status == .dormant ? $0.statusSince > $1.statusSince : $0.statusSince < $1.statusSince
            }
            return $0.id < $1.id
        }
        return Result(tiles: tiles, hidden: sessions.count - shown.count, dormant: eligible.count)
    }
}
