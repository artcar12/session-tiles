import Foundation

/// What's remembered about a pinned session, so its tile can stay up after its process ends.
struct PinnedSession: Codable, Equatable {
    var name: String
    var project: String
    /// When the session was last seen running; an offline tile counts its time from here.
    var lastSeen: Date
}

/// Pinned sessions, keyed by hostSessionId and persisted in UserDefaults.
@MainActor
final class PinStore: ObservableObject {
    @Published private(set) var pins: [String: PinnedSession]

    private static let defaultsKey = "pinnedSessions"
    /// Pinned ids that were live on the last `update`, to stamp `lastSeen` when one goes away.
    private var live: Set<String> = []

    init() {
        pins = UserDefaults.standard.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([String: PinnedSession].self, from: $0) } ?? [:]
    }

    func isPinned(_ id: String) -> Bool { pins[id] != nil }

    func toggle(_ s: Session) {
        if pins[s.id] != nil {
            pins[s.id] = nil
            live.remove(s.id)
        } else {
            pins[s.id] = PinnedSession(name: s.name, project: s.project,
                                       lastSeen: s.status == .offline ? s.statusSince : Date())
            if s.status != .offline { live.insert(s.id) }
        }
        save()
    }

    /// Keeps pinned names current and stamps `lastSeen` when a pinned session's process goes away.
    /// Writes only on those changes, not on every refresh.
    func update(from sessions: [Session]) {
        var changed = false
        var nowLive: Set<String> = []
        for s in sessions {
            guard var pin = pins[s.id] else { continue }
            nowLive.insert(s.id)
            if pin.name != s.name || pin.project != s.project {
                pin.name = s.name
                pin.project = s.project
                pins[s.id] = pin
                changed = true
            }
        }
        let now = Date()
        for id in live.subtracting(nowLive) where pins[id] != nil {
            pins[id]?.lastSeen = now
            changed = true
        }
        live = nowLive
        if changed { save() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(pins) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
