import SwiftUI

/// Backlit rubber pads on a black deck, like a Launchpad / MPC. Waiting pads strobe, busy pads run a
/// level meter, idle pads sit dimly lit like a cued sample.
struct DJDeckSkin: Skin {
    let grid = GridMetrics(minTileWidth: 112, maxTileWidth: 170, spacing: 8, padding: 10)
    let textColor = Color.white
    let secondaryTextColor = Color(hex: 0x8A8A95)

    let controls = ControlStyle(accent: Color(hex: 0x1EA7FF), track: Color(hex: 0x34343C), cap: Color(hex: 0x3A3A42),
                                capEdge: .white.opacity(0.18), label: Color(hex: 0x8A8A95), value: .white,
                                design: .rounded, radius: 4, glow: true)

    func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let pinnedIdle = Color(hex: 0xB45CFF)

    static func color(_ status: SessionStatus) -> Color {
        switch status {
        case .waiting: return Color(hex: 0xFF2D55)
        case .idle:    return Color(hex: 0xFFA41B)
        case .busy:    return Color(hex: 0x1EA7FF)
        case .unknown: return Color(hex: 0x9A9AA5)
        case .dormant: return Color(hex: 0x3E4A63)
        case .offline: return Color(hex: 0x4A4A55)
        }
    }

    func background() -> AnyView {
        AnyView(
            ZStack {
                LinearGradient(colors: [Color(hex: 0x1C1C21), Color(hex: 0x0B0B0D)],
                               startPoint: .top, endPoint: .bottom)
                // Fine brushed-metal streaks.
                Canvas { ctx, size in
                    var y: CGFloat = 0
                    while y < size.height {
                        ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.5)),
                                 with: .color(.white.opacity(0.025)))
                        y += 2
                    }
                }
            }
        )
    }

    func header(_ summary: PanelSummary) -> AnyView {
        AnyView(
            HStack(spacing: 10) {
                Text("SESSION DECK")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                DJCounter(label: "CUE", count: summary.waiting, color: Self.color(.waiting), strobe: summary.waiting > 0)
                DJCounter(label: "IDLE", count: summary.idle, color: Self.color(.idle))
                DJCounter(label: "LIVE", count: summary.busy, color: Self.color(.busy))
            }
            .frame(height: 24)
        )
    }

    func tile(_ model: TileModel, _ state: TileState) -> AnyView {
        AnyView(DJPad(model: model, state: state))
    }
}

private struct DJCounter: View {
    let label: String
    let count: Int
    let color: Color
    var strobe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            BlinkingFill(color: count > 0 ? color : color.opacity(0.2), cornerRadius: 3,
                         blinking: strobe && !reduceMotion, low: 0.25, period: 0.4, glow: count > 0 ? 3 : 0)
                .frame(width: 6, height: 6)
            Text("\(label) \(count)")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

private struct DJPad: View {
    /// Source tag lettering, lit like the pads' LEDs.
    static let tagColors: [Color] = [Color(hex: 0x4FF0E0), Color(hex: 0xFF6FCF), Color(hex: 0xA8FF60), Color(hex: 0xFFE45C),
                                     Color(hex: 0xFFFFFF)]

    let model: TileModel
    let state: TileState

    private var color: Color { model.pinnedIdle ? DJDeckSkin.pinnedIdle : DJDeckSkin.color(model.status) }

    /// How brightly the pad is lit, 0...1.
    private var level: Double {
        let base: Double
        switch model.status {
        case .waiting: base = 0.95
        case .busy: base = 0.85
        case .idle: base = 0.72
        case .unknown: base = 0.4
        case .dormant, .offline: base = 0.3
        }
        return min(1, base + (state.hovering ? 0.15 : 0) + (state.pressed ? 0.2 : 0))
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        ZStack(alignment: .topLeading) {
            // Glow, unlit rubber, the backlight shining through it, then a soft hotspot in the middle.
            // The glow is its own layer so the blinking backlight doesn't take the shadow with it.
            shape.fill(Color(hex: 0x232328))
                .shadow(color: color.opacity(0.55 * level), radius: state.hovering ? 10 : 6)
            shape.fill(Color(hex: 0x232328))
            BlinkingFill(color: color.opacity(level * 0.85), cornerRadius: 7,
                         blinking: model.status == .waiting && !state.reduceMotion, low: 0.55, period: 0.5)
            shape.fill(RadialGradient(colors: [.white.opacity(0.28 * level), .clear],
                                      center: .center, startRadius: 2, endRadius: 90))
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.name)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.45), radius: 1, y: 1)
                Spacer(minLength: 2)
                if model.status == .waiting {
                    Text((model.waitingFor ?? "waiting").uppercased())
                        .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .lineLimit(1)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(.black.opacity(0.35)))
                } else if model.status == .unknown || model.status.isAsleep {
                    Text(model.rawStatus.uppercased()).font(.system(size: 8.5, weight: .heavy)).lineLimit(1)
                }
                HStack(alignment: .bottom, spacing: 4) {
                    Text(model.project.uppercased())
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .tracking(0.4)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .opacity(0.85)
                    TagRow(tags: model.tags, spacing: 2) { t in
                        let c = Self.tagColors.tag(t)
                        Text(t.text)
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .foregroundStyle(c)
                            .padding(.horizontal, 3.5).padding(.vertical, 1)
                            .background(Capsule().fill(.black.opacity(0.55)))
                            .shadow(color: c.opacity(0.6), radius: 2)
                    }
                    Spacer(minLength: 2)
                    if model.status == .busy {
                        LevelMeter(animated: !state.reduceMotion)
                    }
                    Text(model.clockDuration)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                }
            }
            .foregroundStyle(.white)
            .padding(7)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .scaleEffect(state.pressed ? 0.95 : 1)
        .animation(.easeOut(duration: 0.12), value: state.pressed)
        .animation(.easeOut(duration: 0.15), value: state.hovering)
    }
}
