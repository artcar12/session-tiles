import SwiftUI
import AppKit

struct TilesView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var pins: PinStore
    @ObservedObject var index: AppSessionIndex
    @AppStorage(SkinID.defaultsKey) private var skinID: SkinID = .classic
    @AppStorage(TileFilter.Keys.showAll) private var showAll = false
    @AppStorage(TileFilter.Keys.status) private var status: StatusFilter = .any
    @AppStorage(TileFilter.Keys.standbyStop) private var standbyStop = TileFilter.defaultStandbyStop
    @AppStorage(TileFilter.Keys.showPinned) private var showPinned = true
    @AppStorage(TileFilter.Keys.showDormant) private var showDormant = false
    @AppStorage(ControlDeck.visibleKey) private var showControls = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let skin = skinID.skin
        let filter = TileFilter(showAll: showAll, status: status, standbyStop: standbyStop, showPinned: showPinned,
                                showDormant: showDormant)
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let result = VisibilityRules.ordered(store.sessions, pinned: pins.pins, dormant: index.entries,
                                                 filter: filter, now: context.date)
            let visible = result.tiles
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
                        Text(result.hidden > 0 ? "\(result.hidden) hidden by filters" : "No active Claude sessions")
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
                                               model: TileModel(session: s, elapsed: context.date.timeIntervalSince(s.statusSince),
                                                              pinned: pins.isPinned(s.id)),
                                               pinned: pins.isPinned(s.id),
                                               reduceMotion: reduceMotion) { pins.toggle(s) }
                                }
                            }
                            .padding(6)   // room for glows/shadows so the scroll view doesn't clip them
                            .padding(-6)
                        }
                    }
                    if showControls {
                        ControlDeck(style: skin.controls, showAll: $showAll, showPinned: $showPinned,
                                    showDormant: $showDormant, status: $status,
                                    standbyStop: $standbyStop, skin: $skinID, hidden: result.hidden,
                                    dormant: result.dormant)
                    }
                }
            }
            .padding(skin.grid.padding)
            .padding(.top, 2)
        }
        // The header occupies the (invisible) title-bar strip, which doubles as the drag handle.
        .ignoresSafeArea(edges: .top)
        // Right-click on the panel (tiles have their own menu). Reachable with the control strip hidden.
        .contentShape(Rectangle())
        .contextMenu {
            Picker("Skin", selection: $skinID) {
                ForEach(SkinID.allCases) { Text($0.displayName).tag($0) }
            }
            Toggle("Show Controls", isOn: $showControls)
        }
        .background(skin.background().ignoresSafeArea())
        .frame(minWidth: showControls ? 360 : 200, minHeight: showControls ? 170 : 100)
    }
}

/// Shared click + hover handling; the skin only draws.
private struct TileButton: View {
    let skin: any Skin
    let model: TileModel
    let pinned: Bool
    let reduceMotion: Bool
    let togglePin: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            Color.clear
        }
        .buttonStyle(SkinButtonStyle(skin: skin, model: model, hovering: hovering, reduceMotion: reduceMotion))
        .overlay(alignment: .topTrailing) {
            PinBadge(pinned: pinned, visible: pinned || hovering, action: togglePin)
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open in Claude", action: open)
            Button(pinned ? "Unpin" : "Pin", action: togglePin)
        }
        .help("\(model.name)\n\(model.project) · \(model.rawStatus)\(pinned ? " · pinned" : "")\nClick to open in Claude")
    }

    private func open() {
        if let url = model.session.deepLink { NSWorkspace.shared.open(url) }
    }
}

/// Pin toggle in a tile's top-right corner: always shown on pinned tiles, on hover otherwise.
private struct PinBadge: View {
    let pinned: Bool
    let visible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: pinned ? "pin.fill" : "pin")
                .font(.system(size: 9, weight: .bold))
                .rotationEffect(.degrees(45))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 1.5)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(visible ? (pinned ? 0.95 : 0.6) : 0)
        .allowsHitTesting(visible)
        .help(pinned ? "Unpin: let filters hide this tile again" : "Pin: keep this tile on the panel")
        .accessibilityLabel(pinned ? "Unpin" : "Pin")
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
