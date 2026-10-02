import Foundation

/// The single place that decides which sessions get a tile and in what order.
/// Placeholder rules for the MVP; proper filtering comes later.
enum VisibilityRules {
    static let idleCutoff: TimeInterval = 60 * 60

    static func isVisible(_ s: Session, now: Date) -> Bool {
        if s.status == .idle && now.timeIntervalSince(s.statusSince) > idleCutoff { return false }
        return true
    }

    /// waiting (oldest first), then idle, then busy, then anything unrecognised.
    static func ordered(_ sessions: [Session], now: Date) -> [Session] {
        sessions
            .filter { isVisible($0, now: now) }
            .sorted {
                if $0.status != $1.status { return $0.status < $1.status }
                if $0.statusSince != $1.statusSince { return $0.statusSince < $1.statusSince }
                return $0.id < $1.id
            }
    }
}
