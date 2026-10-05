import SwiftUI

/// Neon noir: a rainy black-violet night, tiles outlined in glowing neon tubes with clipped corners,
/// condensed caps and kanji status tags. Waiting tiles buzz like a failing neon sign and their titles
/// split into pink/cyan; busy tiles run a cyan data chase.
struct CyberpunkSkin: Skin {
    let grid = GridMetrics(minTileWidth: 150, maxTileWidth: 260, spacing: 8, padding: 10)
    let textColor = Color(hex: 0xF0E6FF)
    let secondaryTextColor = Color(hex: 0x8C7AA8)

    static let pink = Color(hex: 0xFF2E88)
    static let cyan = Color(hex: 0x00F0FF)

    let controls = ControlStyle(accent: pink, track: Color(hex: 0x2A1840), cap: Color(hex: 0x1A0F2A),
                                capEdge: cyan.opacity(0.6), label: Color(hex: 0x8C7AA8), value: Color(hex: 0xF0E6FF),
                                design: .monospaced, radius: 2, glow: true)

    func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    static let pinnedIdle = Color(hex: 0x7CFF4F)

    static func color(_ status: SessionStatus) -> Color {
        switch status {
        case .waiting: return pink
        case .idle:    return Color(hex: 0xFFD23F)
        case .busy:    return cyan
        case .unknown: return Color(hex: 0xA78BFA)
        case .dormant: return Color(hex: 0x5A5A8A)
        case .offline: return Color(hex: 0x4A4260)
        }
    }

    func background() -> AnyView {
        AnyView(
            ZStack {
                LinearGradient(colors: [Color(hex: 0x140A26), Color(hex: 0x05020A)],
                               startPoint: .top, endPoint: .bottom)
                // Faint city glow from below.
                RadialGradient(colors: [Self.pink.opacity(0.12), .clear],
                               center: .bottom, startRadius: 0, endRadius: 320)
                // Rain: fixed pseudo-random streaks, so it's static and cheap.
                Canvas { ctx, size in
                    var seed: UInt64 = 0x9E3779B97F4A7C15
                    func next() -> CGFloat {
                        seed = seed &* 6364136223846793005 &+ 1442695040888963407
                        return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
                    }
                    let count = Int(size.width * size.height / 700)
                    for _ in 0..<count {
                        let x = next() * size.width, y = next() * size.height
                        let len = 6 + next() * 16
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: y))
                        p.addLine(to: CGPoint(x: x - len * 0.18, y: y + len))
                        ctx.stroke(p, with: .color(Self.cyan.opacity(0.04 + next() * 0.07)), lineWidth: 0.6)
                    }
                }
            }
        )
    }

    func header(_ summary: PanelSummary) -> AnyView {
        AnyView(
            HStack(spacing: 8) {
                Text("NEON//SESSIONS")
                    .font(.system(size: 12, weight: .black).width(.condensed))
                    .tracking(1.5)
                    .foregroundStyle(Self.pink)
                    .shadow(color: Self.pink.opacity(0.8), radius: 4)
                Text("セッション")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Self.cyan.opacity(0.6))
                Spacer()
                if summary.waiting > 0 {
                    Text("■ \(summary.waiting) ALERT").foregroundStyle(Self.pink)
                }
                Text("■ \(summary.busy) LIVE").foregroundStyle(Self.cyan)
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .lineLimit(1)
            .frame(height: 24)
        )
    }

    func tile(_ model: TileModel, _ state: TileState) -> AnyView {
        AnyView(CyberTile(model: model, state: state))
    }
}

/// Rectangle with the top-right and bottom-left corners cut off.
private struct ClippedRect: InsettableShape {
    var cut: CGFloat = 10
    var inset: CGFloat = 0

    func path(in r: CGRect) -> Path {
        let r = r.insetBy(dx: inset, dy: inset)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - cut, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + cut))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + cut, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - cut))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> Self { var s = self; s.inset += amount; return s }
}

private struct CyberTile: View {
    let model: TileModel
    let state: TileState

    private var color: Color { model.pinnedIdle ? CyberpunkSkin.pinnedIdle : CyberpunkSkin.color(model.status) }
    private var alarm: Bool { model.status == .waiting && !state.reduceMotion }

    static let tagColors: [Color] = [CyberpunkSkin.cyan, CyberpunkSkin.pink, Color(hex: 0xB6FF3B), Color(hex: 0xFFE53B),
                                     Color(hex: 0xFFFFFF)]

    private var tag: String {
        switch model.status {
        case .waiting: return "警告"
        case .idle: return "待機"
        case .busy: return "稼働"
        case .unknown: return "不明"
        case .dormant: return "休眠"
        case .offline: return "切断"
        }
    }

    var body: some View {
        let shape = ClippedRect()
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Text(tag)
                    .font(.system(size: 8.5, weight: .heavy))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(Rectangle().fill(color))
                    .padding(.top, 1)
                title
            }
            HStack(spacing: 4) {
                Text(model.project.lowercased())
                    .lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(CyberpunkSkin.cyan.opacity(0.7))
                Text("//").foregroundStyle(color.opacity(0.6))
                Spacer(minLength: 4)
                TagRow(tags: model.tags, spacing: 2) { t in
                    Text(t.text)
                        .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(Rectangle().fill(Self.tagColors.tag(t)))
                        .opacity(model.status.isAsleep ? 0.6 : 1)
                }
                Text(model.clockDuration).foregroundStyle(color)
            }
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            statusLine
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background(
            ZStack {
                shape.fill(Color(hex: 0x0E0818))
                shape.fill(LinearGradient(colors: [color.opacity(state.hovering ? 0.22 : 0.12), .clear],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                // The neon tube: a soft halo plus a bright core, buzzing when waiting.
                ZStack {
                    shape.stroke(color.opacity(0.5), lineWidth: 4).blur(radius: 4)
                    shape.strokeBorder(color, lineWidth: 1.5)
                }
                .opacity(model.status.isAsleep ? 0.5 : (state.hovering ? 1 : 0.9))
                .flicker(alarm, .neon)
            }
        )
        .scaleEffect(state.pressed ? 0.97 : 1)
        .animation(.easeOut(duration: 0.12), value: state.pressed)
        .animation(.easeOut(duration: 0.15), value: state.hovering)
    }

    /// Waiting titles get a pink/cyan chromatic split.
    private var title: some View {
        let text = Text(model.name.uppercased())
            .font(.system(size: 12, weight: .heavy).width(.condensed))
            .lineLimit(3)
            .multilineTextAlignment(.leading)
        return ZStack(alignment: .topLeading) {
            if model.status == .waiting {
                text.foregroundStyle(CyberpunkSkin.pink.opacity(0.8)).offset(x: -1.2)
                text.foregroundStyle(CyberpunkSkin.cyan.opacity(0.7)).offset(x: 1.2)
            }
            text.foregroundStyle(model.status.isAsleep ? Color(hex: 0x8C7AA8) : .white)
        }
    }

    @ViewBuilder private var statusLine: some View {
        let font = Font.system(size: 9, weight: .heavy, design: .monospaced)
        switch model.status {
        case .waiting:
            Text("!! \((model.waitingFor ?? "input required").uppercased()) !!")
                .font(font).foregroundStyle(color).lineLimit(1)
                .fixedSize()
                .flicker(alarm, .neon)
        case .busy:
            HStack(spacing: 6) {
                Text("▶ JACKED IN").font(font).foregroundStyle(color)
                LEDChase(color: color, animated: !state.reduceMotion, count: 8,
                         segment: CGSize(width: 6, height: 3), spacing: 2, step: 0.08)
            }
        case .idle:
            Text("// IDLE").font(font).foregroundStyle(color.opacity(0.8))
        case .unknown:
            Text("// \(model.rawStatus.uppercased())").font(font).foregroundStyle(color).lineLimit(1)
        case .dormant:
            Text("// SLEEP MODE").font(font).foregroundStyle(color)
        case .offline:
            Text("// FLATLINED").font(font).foregroundStyle(color)
        }
    }
}
