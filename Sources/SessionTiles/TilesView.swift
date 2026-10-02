import SwiftUI
import AppKit

struct TilesView: View {
    @ObservedObject var store: SessionStore

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 260), spacing: 6)]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let visible = VisibilityRules.ordered(store.sessions, now: context.date)
            VStack(alignment: .leading, spacing: 6) {
                if let err = store.fatalError {
                    Banner(text: err, symbol: "exclamationmark.octagon.fill", color: .red)
                    Spacer(minLength: 0)
                } else {
                    if let warn = store.warning {
                        Banner(text: warn, symbol: "exclamationmark.triangle.fill", color: .orange)
                    }
                    if visible.isEmpty {
                        Text("No active Claude sessions")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 6) {
                                ForEach(visible) { s in
                                    TileView(session: s, now: context.date)
                                }
                            }
                        }
                    }
                }
            }
            .padding(8)
            .padding(.top, 6) // room for the invisible title bar drag area
        }
        .frame(minWidth: 180, minHeight: 80)
    }
}

struct TileView: View {
    let session: Session
    let now: Date
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        Button {
            if let url = session.deepLink { NSWorkspace.shared.open(url) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Text(session.project).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(Self.duration(now.timeIntervalSince(session.statusSince)))
                        .monospacedDigit()
                }
                .font(.system(size: 10.5))
                .opacity(0.85)
                if session.status == .waiting {
                    Text(session.waitingFor.map { "Waiting: \($0)" } ?? "Waiting")
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1)
                } else if session.status == .unknown {
                    Text("Status: \(session.rawStatus)")
                        .font(.system(size: 10.5))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 7).fill(color.opacity(hovering ? 1 : 0.88)))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(session.name)\n\(session.project) · \(session.rawStatus)\nClick to open in Claude")
    }

    private var color: Color {
        let dark = scheme == .dark
        switch session.status {
        case .waiting: return Color(red: dark ? 0.78 : 0.86, green: 0.20, blue: 0.20)
        case .idle:    return Color(red: dark ? 0.78 : 0.88, green: dark ? 0.50 : 0.56, blue: 0.05)
        case .busy:    return Color(red: 0.16, green: dark ? 0.40 : 0.45, blue: dark ? 0.80 : 0.88)
        case .unknown: return Color.gray
        }
    }

    static func duration(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60)
    }
}

private struct Banner: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.12)))
            .textSelection(.enabled)
    }
}
