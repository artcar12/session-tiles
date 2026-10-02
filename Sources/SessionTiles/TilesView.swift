import SwiftUI
import AppKit

struct TilesView: View {
    @ObservedObject var store: SessionStore
    @AppStorage(SkinID.defaultsKey) private var skinID: SkinID = .classic
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let skin = skinID.skin
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let visible = VisibilityRules.ordered(store.sessions, now: context.date)
            VStack(alignment: .leading, spacing: skin.grid.spacing) {
                skin.header(PanelSummary(visible))
                if let err = store.fatalError {
                    Banner(text: err, symbol: "exclamationmark.octagon.fill", color: .red, skin: skin)
                    Spacer(minLength: 0)
                } else {
                    if let warn = store.warning {
                        Banner(text: warn, symbol: "exclamationmark.triangle.fill", color: .orange, skin: skin)
                    }
                    if visible.isEmpty {
                        Text("No active Claude sessions")
                            .font(skin.font(12, .regular))
                            .foregroundStyle(skin.secondaryTextColor)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: skin.grid.minTileWidth,
                                                                   maximum: skin.grid.maxTileWidth),
                                                         spacing: skin.grid.spacing)],
                                      spacing: skin.grid.spacing) {
                                ForEach(visible) { s in
                                    TileButton(skin: skin,
                                               model: TileModel(session: s, elapsed: context.date.timeIntervalSince(s.statusSince)),
                                               reduceMotion: reduceMotion)
                                }
                            }
                            .padding(6)   // room for glows/shadows so the scroll view doesn't clip them
                            .padding(-6)
                        }
                    }
                }
            }
            .padding(skin.grid.padding)
            .padding(.top, 2)
        }
        // The header occupies the (invisible) title-bar strip, which doubles as the drag handle.
        .ignoresSafeArea(edges: .top)
        .background(skin.background().ignoresSafeArea())
        .frame(minWidth: 200, minHeight: 100)
    }
}

/// Shared click + hover handling; the skin only draws.
private struct TileButton: View {
    let skin: any Skin
    let model: TileModel
    let reduceMotion: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            if let url = model.session.deepLink { NSWorkspace.shared.open(url) }
        } label: {
            Color.clear
        }
        .buttonStyle(SkinButtonStyle(skin: skin, model: model, hovering: hovering, reduceMotion: reduceMotion))
        .onHover { hovering = $0 }
        .help("\(model.name)\n\(model.project) · \(model.rawStatus)\nClick to open in Claude")
    }
}

private struct SkinButtonStyle: ButtonStyle {
    let skin: any Skin
    let model: TileModel
    let hovering: Bool
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        skin.tile(model, TileState(hovering: hovering, pressed: configuration.isPressed, reduceMotion: reduceMotion))
            .contentShape(Rectangle())
    }
}

private struct Banner: View {
    let text: String
    let symbol: String
    let color: Color
    let skin: any Skin

    var body: some View {
        Label(text, systemImage: symbol)
            .font(skin.font(11, .medium))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.14)))
            .textSelection(.enabled)
    }
}
