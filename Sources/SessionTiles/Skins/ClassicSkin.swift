import SwiftUI

/// The original look: flat rounded tiles over the system blur, following light/dark mode.
struct ClassicSkin: Skin {
    let grid = GridMetrics(minTileWidth: 160, maxTileWidth: 260, spacing: 6, padding: 8)
    let textColor = Color.primary
    let secondaryTextColor = Color.secondary

    let controls = ControlStyle(accent: .accentColor, track: .primary.opacity(0.15), cap: Color(white: 0.96),
                                capEdge: .black.opacity(0.15), label: .secondary, value: .primary, radius: 9)

    func font(_ size: CGFloat, _ weight: Font.Weight) -> Font { .system(size: size, weight: weight) }

    func background() -> AnyView { AnyView(Color.clear) }

    func header(_ summary: PanelSummary) -> AnyView {
        AnyView(
            HStack(spacing: 8) {
                Text("Claude sessions").font(.system(size: 11, weight: .semibold))
                Spacer()
                if summary.waiting > 0 { Text("\(summary.waiting) waiting").foregroundStyle(.red) }
                Text("\(summary.total) shown")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .frame(height: 22)
        )
    }

    func tile(_ model: TileModel, _ state: TileState) -> AnyView {
        AnyView(ClassicTile(model: model, state: state))
    }
}

private struct ClassicTile: View {
    let model: TileModel
    let state: TileState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 4) {
                Text(model.project).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Text(model.shortDuration).monospacedDigit()
            }
            .font(.system(size: 10.5))
            .opacity(0.85)
            if model.status == .waiting {
                Text(model.waitingFor.map { "Waiting: \($0)" } ?? "Waiting")
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
            } else if model.status == .unknown {
                Text("Status: \(model.rawStatus)").font(.system(size: 10.5)).lineLimit(1)
            } else if model.status.isAsleep {
                Text(model.status == .dormant ? "Not running" : "Offline").font(.system(size: 10.5, weight: .medium)).lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 7).fill(color.opacity(state.hovering ? 1 : 0.88)))
        .scaleEffect(state.pressed ? 0.97 : 1)
    }

    private var color: Color {
        let dark = scheme == .dark
        if model.pinnedIdle { return Color(red: dark ? 0.50 : 0.56, green: 0.30, blue: dark ? 0.78 : 0.86) }
        switch model.status {
        case .waiting: return Color(red: dark ? 0.78 : 0.86, green: 0.20, blue: 0.20)
        case .idle:    return Color(red: dark ? 0.78 : 0.88, green: dark ? 0.50 : 0.56, blue: 0.05)
        case .busy:    return Color(red: 0.16, green: dark ? 0.40 : 0.45, blue: dark ? 0.80 : 0.88)
        case .unknown: return .gray
        case .dormant: return Color(red: 0.36, green: 0.42, blue: 0.52).opacity(dark ? 0.8 : 1)
        case .offline: return Color(white: dark ? 0.32 : 0.55)
        }
    }
}
