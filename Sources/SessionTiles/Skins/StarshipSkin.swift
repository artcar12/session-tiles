import SwiftUI

/// Bridge-console look: chamfered outlined panels, glowing indicator LEDs, monospaced readouts,
/// scanlines. Waiting stations raise an alarm, busy ones run an LED chase, idle ones sit on standby.
struct StarshipSkin: Skin {
    let grid = GridMetrics(minTileWidth: 165, maxTileWidth: 280, spacing: 7, padding: 10)
    let textColor = Color(hex: 0xBFEFFF)
    let secondaryTextColor = Color(hex: 0x5E8AA0)

    func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let cyan = Color(hex: 0x39C5FF)

    let controls = ControlStyle(accent: cyan, track: cyan.opacity(0.18), cap: Color(hex: 0x0A121A),
                                capEdge: cyan.opacity(0.7), label: Color(hex: 0x5E8AA0), value: Color(hex: 0xBFEFFF),
                                design: .monospaced, radius: 1.5, glow: true)

    static let pinnedIdle = Color(hex: 0xC77DFF)

    static func color(_ status: SessionStatus) -> Color {
        switch status {
        case .waiting: return Color(hex: 0xFF3B30)
        case .idle:    return Color(hex: 0xFFB000)
        case .busy:    return cyan
        case .unknown: return Color(hex: 0x8FA3AD)
        case .dormant: return Color(hex: 0x5A7A8C)
        case .offline: return Color(hex: 0x4A5A64)
        }
    }

    func background() -> AnyView {
        AnyView(
            ZStack {
                LinearGradient(colors: [Color(hex: 0x0F1A24), Color(hex: 0x060B10)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Canvas { ctx, size in
                    // Faint targeting grid.
                    let step: CGFloat = 24
                    var x: CGFloat = 0
                    while x < size.width {
                        ctx.fill(Path(CGRect(x: x, y: 0, width: 0.5, height: size.height)),
                                 with: .color(Self.cyan.opacity(0.05)))
                        x += step
                    }
                    var y: CGFloat = 0
                    while y < size.height {
                        ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.5)),
                                 with: .color(Self.cyan.opacity(0.05)))
                        y += step
                    }
                    // Scanlines.
                    y = 0
                    while y < size.height {
                        ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                                 with: .color(.black.opacity(0.18)))
                        y += 3
                    }
                    // Corner brackets.
                    let l: CGFloat = 14, inset: CGFloat = 4
                    var p = Path()
                    p.move(to: CGPoint(x: inset, y: size.height - inset - l))
                    p.addLine(to: CGPoint(x: inset, y: size.height - inset))
                    p.addLine(to: CGPoint(x: inset + l, y: size.height - inset))
                    p.move(to: CGPoint(x: size.width - inset - l, y: size.height - inset))
                    p.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset))
                    p.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset - l))
                    ctx.stroke(p, with: .color(Self.cyan.opacity(0.45)), lineWidth: 1.5)
                }
            }
        )
    }

    func header(_ summary: PanelSummary) -> AnyView {
        AnyView(StarshipHeader(summary: summary))
    }

    func tile(_ model: TileModel, _ state: TileState) -> AnyView {
        AnyView(StarshipStation(model: model, state: state))
    }
}

private struct StarshipHeader: View {
    let summary: PanelSummary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Text("◢ SESSION CONTROL")
                    .foregroundStyle(StarshipSkin.cyan)
                Text("// \(summary.online) ONLINE")
                    .foregroundStyle(StarshipSkin.cyan.opacity(0.5))
                Spacer()
                if summary.waiting > 0 {
                    Text("▲ RED ALERT · \(summary.waiting) WAITING")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(StarshipSkin.color(.waiting))
                        .fixedSize()  // blink() re-hosts the text; pin it to its ideal size
                        .blink(!reduceMotion, low: 0.2, period: 0.5)
                } else {
                    Text("● ALL SYSTEMS NOMINAL")
                        .foregroundStyle(Color(hex: 0x34E07A))
                }
            }
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            // Ruler with tick marks.
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)),
                         with: .color(StarshipSkin.cyan.opacity(0.4)))
                var x: CGFloat = 0, i = 0
                while x < size.width {
                    let h: CGFloat = i % 5 == 0 ? 4 : 2
                    ctx.fill(Path(CGRect(x: x, y: size.height - 1 - h, width: 1, height: h)),
                             with: .color(StarshipSkin.cyan.opacity(0.4)))
                    x += 6; i += 1
                }
            }
            .frame(height: 5)
        }
        .frame(height: 24)
    }
}

/// Rectangle with the top-left and bottom-right corners cut off.
struct ChamferedRect: InsettableShape {
    var cut: CGFloat = 9
    var inset: CGFloat = 0

    func path(in r: CGRect) -> Path {
        let r = r.insetBy(dx: inset, dy: inset)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + cut, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - cut))
        p.addLine(to: CGPoint(x: r.maxX - cut, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + cut))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> Self { var s = self; s.inset += amount; return s }
}

private struct StarshipStation: View {
    let model: TileModel
    let state: TileState

    static let tagColors: [Color] = [Color(hex: 0x5FE3FF), Color(hex: 0xFF6AD5), Color(hex: 0x6BF09A), Color(hex: 0xFFE066),
                                     Color(hex: 0xFFFFFF)]

    private var color: Color { model.pinnedIdle ? StarshipSkin.pinnedIdle : StarshipSkin.color(model.status) }
    private var alarm: Bool { model.status == .waiting && !state.reduceMotion }

    var body: some View {
        let shape = ChamferedRect()
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                BlinkingFill(color: color, cornerRadius: 3.5, blinking: alarm, low: 0.15, period: 0.4, glow: 4)
                    .frame(width: 7, height: 7)
                    .padding(.top, 3)
                Text(model.name.uppercased())
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xE6F8FF))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            HStack(spacing: 4) {
                Text("SECTOR \(model.project.uppercased())")
                    .lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(StarshipSkin.cyan.opacity(0.7))
                Spacer(minLength: 4)
                Text("T+\(model.clockDuration)")
                    .foregroundStyle(color)
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            HStack(spacing: 4) {
                statusLine
                Spacer(minLength: 4)
                TagRow(tags: model.tags) { t in
                    let c = Self.tagColors.tag(t)
                    Text(t.text)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(c)
                        .padding(.horizontal, 3).padding(.vertical, 0.5)
                        .background(Rectangle().fill(c.opacity(0.12)))
                        .overlay(Rectangle().strokeBorder(c.opacity(0.7), lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .background(
            ZStack {
                shape.fill(Color(hex: 0x0A121A))
                    .shadow(color: color.opacity(state.hovering ? 0.6 : 0.3), radius: state.hovering ? 8 : 4)
                shape.fill(color.opacity(state.hovering ? 0.22 : 0.12))
                shape.fill(LinearGradient(colors: [.white.opacity(0.06), .clear],
                                          startPoint: .top, endPoint: .center))
                shape.strokeBorder(color.opacity(state.hovering ? 1 : 0.75), lineWidth: 1)
                    .blink(alarm, low: 0.3, period: 0.4)
            }
        )
        .scaleEffect(state.pressed ? 0.97 : 1)
        .animation(.easeOut(duration: 0.12), value: state.pressed)
        .animation(.easeOut(duration: 0.15), value: state.hovering)
    }

    @ViewBuilder private var statusLine: some View {
        let font = Font.system(size: 9, weight: .heavy, design: .monospaced)
        switch model.status {
        case .waiting:
            Text("⚠ \((model.waitingFor ?? "awaiting orders").uppercased())")
                .font(font).foregroundStyle(color).lineLimit(1)
                .blink(alarm, low: 0.25, period: 0.5)
        case .busy:
            HStack(spacing: 6) {
                Text("ENGAGED").font(font).foregroundStyle(color)
                LEDChase(color: color, animated: !state.reduceMotion)
            }
        case .idle:
            Text("STANDBY").font(font).foregroundStyle(color.opacity(0.85))
        case .unknown:
            Text("STATUS \(model.rawStatus.uppercased())").font(font).foregroundStyle(color).lineLimit(1)
        case .dormant:
            Text("❄ CRYOSLEEP").font(font).foregroundStyle(color)
        case .offline:
            Text("◌ SIGNAL LOST").font(font).foregroundStyle(color)
        }
    }
}
