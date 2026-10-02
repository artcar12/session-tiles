import SwiftUI

/// A skin owns everything visual: panel background, header strip, tile look, grid metrics and chrome
/// fonts. Data, ordering and click handling stay shared (TilesView / TileButton), so a new skin is one
/// file plus a case in `SkinID`.
protocol Skin {
    var grid: GridMetrics { get }
    var textColor: Color { get }
    var secondaryTextColor: Color { get }
    func font(_ size: CGFloat, _ weight: Font.Weight) -> Font

    /// Fills the whole panel, title-bar area included. Return `Color.clear` to keep the system blur.
    func background() -> AnyView
    /// Strip at the top of the panel. It sits under the invisible title bar, so it's also the drag handle.
    func header(_ summary: PanelSummary) -> AnyView
    func tile(_ model: TileModel, _ state: TileState) -> AnyView
}

enum SkinID: String, CaseIterable, Identifiable {
    case classic, djDeck, starship

    static let defaultsKey = "skin"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .djDeck: return "DJ Deck"
        case .starship: return "Starship Console"
        }
    }

    var skin: any Skin {
        switch self {
        case .classic: return ClassicSkin()
        case .djDeck: return DJDeckSkin()
        case .starship: return StarshipSkin()
        }
    }
}

struct GridMetrics {
    var minTileWidth: CGFloat
    var maxTileWidth: CGFloat
    var spacing: CGFloat
    var padding: CGFloat
}

/// What a tile needs to draw itself, precomputed so skins don't touch Session parsing details.
struct TileModel {
    let session: Session
    let elapsed: TimeInterval

    var name: String { session.name }
    var project: String { session.project }
    var status: SessionStatus { session.status }
    var rawStatus: String { session.rawStatus }
    var waitingFor: String? { session.waitingFor }

    /// "45s", "12m", "3h 05m"
    var shortDuration: String {
        let s = max(0, Int(elapsed))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60)
    }

    /// "04:07" or "1:04:07"
    var clockDuration: String {
        let s = max(0, Int(elapsed))
        return s < 3600 ? String(format: "%02d:%02d", s / 60, s % 60)
                        : String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}

struct TileState {
    var hovering: Bool
    var pressed: Bool
    var reduceMotion: Bool
}

struct PanelSummary {
    var waiting = 0, idle = 0, busy = 0, other = 0
    var total: Int { waiting + idle + busy + other }

    init(_ sessions: [Session]) {
        for s in sessions {
            switch s.status {
            case .waiting: waiting += 1
            case .idle: idle += 1
            case .busy: busy += 1
            case .unknown: other += 1
            }
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
