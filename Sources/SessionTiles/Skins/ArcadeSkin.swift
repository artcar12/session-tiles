import SwiftUI

/// 80s arcade cabinet: a CRT screen with scanlines and a pixel starfield, tiles with stepped pixel-art
/// corners and 8x8 sprites. Waiting tiles blink INSERT COIN, idle ones say PRESS START, busy ones are
/// NOW PLAYING, and an ended pinned session is GAME OVER.
struct ArcadeSkin: Skin {
    let grid = GridMetrics(minTileWidth: 150, maxTileWidth: 250, spacing: 8, padding: 10)
    let textColor = Color.white
    let secondaryTextColor = Color(hex: 0x7A7AA0)

    static let yellow = Color(hex: 0xFFE14D)

    let controls = ControlStyle(accent: Color(hex: 0xFF2D6F), track: Color(hex: 0x24243C), cap: Color(hex: 0x12121F),
                                capEdge: yellow.opacity(0.7), label: Color(hex: 0x7A7AA0), value: yellow,
                                design: .monospaced, radius: 0, glow: true)

    func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let pinnedIdle = Color(hex: 0x5CFF5C)

    static func color(_ status: SessionStatus) -> Color {
        switch status {
        case .waiting: return Color(hex: 0xFF2D6F)
        case .idle:    return yellow
        case .busy:    return Color(hex: 0x3DE0FF)
        case .unknown: return Color(hex: 0xB07CFF)
        case .dormant: return Color(hex: 0x6A7AB0)
        case .offline: return Color(hex: 0x55556A)
        }
    }

    func background() -> AnyView {
        AnyView(
            ZStack {
                Color(hex: 0x07071A)
                Canvas { ctx, size in
                    // Pixel starfield (fixed pseudo-random), then CRT scanlines.
                    var seed: UInt64 = 0xA2CADE
                    func next() -> CGFloat {
                        seed = seed &* 6364136223846793005 &+ 1442695040888963407
                        return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
                    }
                    let stars = Int(size.width * size.height / 1800)
                    for _ in 0..<stars {
                        let x = (next() * size.width / 2).rounded() * 2
                        let y = (next() * size.height / 2).rounded() * 2
                        let big = next() > 0.85
                        ctx.fill(Path(CGRect(x: x, y: y, width: big ? 2 : 1, height: big ? 2 : 1)),
                                 with: .color(.white.opacity(0.15 + next() * 0.35)))
                    }
                    var y: CGFloat = 0
                    while y < size.height {
                        ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.28)))
                        y += 3
                    }
                }
                // Tube vignette.
                RadialGradient(colors: [.clear, .black.opacity(0.55)], center: .center, startRadius: 120, endRadius: 420)
            }
        )
    }

    func header(_ summary: PanelSummary) -> AnyView {
        AnyView(ArcadeHeader(summary: summary))
    }

    func tile(_ model: TileModel, _ state: TileState) -> AnyView {
        AnyView(ArcadeTile(model: model, state: state))
    }
}

private extension Flicker {
    /// Hard on/off, like arcade attract-mode text.
    static let attract = Flicker(values: [1, 0], period: 1.0, discrete: true)
}

private struct ArcadeHeader: View {
    let summary: PanelSummary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Text("1UP")
                .foregroundStyle(ArcadeSkin.color(.waiting))
                .fixedSize()
                .flicker(!reduceMotion, .attract)
            Text("SESSION ARCADE")
                .foregroundStyle(ArcadeSkin.yellow)
                .shadow(color: ArcadeSkin.yellow.opacity(0.6), radius: 3)
            Spacer()
            Text("COIN \(summary.waiting)").foregroundStyle(summary.waiting > 0 ? ArcadeSkin.color(.waiting) : ArcadeSkin.color(.offline))
            Text("P1 \(summary.busy)").foregroundStyle(ArcadeSkin.color(.busy))
        }
        .font(.system(size: 10.5, weight: .black, design: .monospaced))
        .lineLimit(1)
        .frame(height: 24)
    }
}

/// Rectangle whose corners are cut in two pixel steps.
private struct PixelRect: InsettableShape {
    var step: CGFloat = 3
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset), s = step
        var p = Path()
        p.addLines([
            CGPoint(x: r.minX + 2 * s, y: r.minY), CGPoint(x: r.maxX - 2 * s, y: r.minY),
            CGPoint(x: r.maxX - 2 * s, y: r.minY + s), CGPoint(x: r.maxX - s, y: r.minY + s),
            CGPoint(x: r.maxX - s, y: r.minY + 2 * s), CGPoint(x: r.maxX, y: r.minY + 2 * s),
            CGPoint(x: r.maxX, y: r.maxY - 2 * s), CGPoint(x: r.maxX - s, y: r.maxY - 2 * s),
            CGPoint(x: r.maxX - s, y: r.maxY - s), CGPoint(x: r.maxX - 2 * s, y: r.maxY - s),
            CGPoint(x: r.maxX - 2 * s, y: r.maxY), CGPoint(x: r.minX + 2 * s, y: r.maxY),
            CGPoint(x: r.minX + 2 * s, y: r.maxY - s), CGPoint(x: r.minX + s, y: r.maxY - s),
            CGPoint(x: r.minX + s, y: r.maxY - 2 * s), CGPoint(x: r.minX, y: r.maxY - 2 * s),
            CGPoint(x: r.minX, y: r.minY + 2 * s), CGPoint(x: r.minX + s, y: r.minY + 2 * s),
            CGPoint(x: r.minX + s, y: r.minY + s), CGPoint(x: r.minX + 2 * s, y: r.minY + s),
        ])
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> Self { var s = self; s.inset += amount; return s }
}

/// 8x8 pixel sprite from rows of "#" and ".".
private struct PixelSprite: View {
    let rows: [String]
    let color: Color
    var pixel: CGFloat = 2

    static let coin = ["..####..", ".##..##.", "##.##.##", "##.##.##", "##.##.##", "##.##.##", ".##..##.", "..####.."]
    static let ship = ["...##...", "...##...", "..####..", ".##..##.", "########", "##.##.##", "#..##..#", "...##..."]
    static let hourglass = ["########", ".#....#.", "..#..#..", "...##...", "...##...", "..#..#..", ".#.##.#.", "########"]
    static let moon = ["..####..", ".###....", "###.....", "###.....", "###.....", "###.....", ".###....", "..####.."]
    static let skull = [".######.", "########", "#..##..#", "#..##..#", "########", ".##..##.", ".#.##.#.", ".######."]
    static let question = ["..####..", ".##..##.", ".....##.", "....##..", "...##...", "...##...", "........", "...##..."]

    var body: some View {
        Canvas { ctx, _ in
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() where ch == "#" {
                    ctx.fill(Path(CGRect(x: CGFloat(x) * pixel, y: CGFloat(y) * pixel, width: pixel, height: pixel)),
                             with: .color(color))
                }
            }
        }
        .frame(width: 8 * pixel, height: 8 * pixel)
        .shadow(color: color.opacity(0.6), radius: 2)
    }
}

private struct ArcadeTile: View {
    let model: TileModel
    let state: TileState

    private var color: Color { model.pinnedIdle ? ArcadeSkin.pinnedIdle : ArcadeSkin.color(model.status) }
    private var blinking: Bool { model.status == .waiting && !state.reduceMotion }

    private var sprite: [String] {
        switch model.status {
        case .waiting: return PixelSprite.coin
        case .busy: return PixelSprite.ship
        case .idle: return PixelSprite.hourglass
        case .unknown: return PixelSprite.question
        case .dormant: return PixelSprite.moon
        case .offline: return PixelSprite.skull
        }
    }

    var body: some View {
        let shape = PixelRect()
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 7) {
                PixelSprite(rows: sprite, color: color)
                    .padding(.top, 1)
                Text(model.name.uppercased())
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .foregroundStyle(model.status.isAsleep ? ArcadeSkin.color(.offline) : .white)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            HStack(spacing: 4) {
                Text("STAGE \(model.project.uppercased())")
                    .lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(Color(hex: 0x9A9AC8))
                Spacer(minLength: 4)
                Text("TIME \(model.clockDuration)").foregroundStyle(ArcadeSkin.yellow)
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            HStack(spacing: 4) {
                statusLine
                Spacer(minLength: 4)
                TagRow(tags: model.tags) { t in
                    Text(t)
                        .font(.system(size: 8.5, weight: .black, design: .monospaced))
                        .foregroundStyle(ArcadeSkin.yellow)
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(Rectangle().fill(Color(hex: 0x1C1C40)))
                        .overlay(Rectangle().strokeBorder(Color(hex: 0x9A9AC8), lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
        .background(
            ZStack {
                shape.fill(Color(hex: 0x0B0B20))
                shape.fill(color.opacity(state.hovering ? 0.16 : 0.07))
                shape.strokeBorder(color.opacity(model.status.isAsleep ? 0.6 : 1), lineWidth: 2)
                    .shadow(color: color.opacity(model.status.isAsleep ? 0 : 0.6), radius: state.hovering ? 6 : 3)
                shape.inset(by: 4).stroke(color.opacity(0.25), lineWidth: 1)
            }
        )
        .scaleEffect(state.pressed ? 0.96 : 1)
        .animation(.easeOut(duration: 0.1), value: state.pressed)
        .animation(.easeOut(duration: 0.15), value: state.hovering)
    }

    @ViewBuilder private var statusLine: some View {
        let font = Font.system(size: 9.5, weight: .black, design: .monospaced)
        switch model.status {
        case .waiting:
            HStack(spacing: 6) {
                Text("INSERT COIN")
                    .font(font).foregroundStyle(color)
                    .fixedSize()
                    .flicker(blinking, .attract)
                if let why = model.waitingFor {
                    Text(why.uppercased())
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(color.opacity(0.75))
                        .lineLimit(1)
                }
            }
        case .busy:
            HStack(spacing: 6) {
                Text("NOW PLAYING").font(font).foregroundStyle(color)
                    .lineLimit(1).layoutPriority(1)
                // Shorter with source tags on the line, so the label doesn't wrap.
                LEDChase(color: color, animated: !state.reduceMotion, count: model.tags.isEmpty ? 6 : 3,
                         segment: CGSize(width: 4, height: 4), spacing: 2, step: 0.12)
            }
        case .idle:
            Text("PRESS START").font(font).foregroundStyle(color)
        case .unknown:
            Text(model.rawStatus.uppercased()).font(font).foregroundStyle(color).lineLimit(1)
        case .dormant:
            Text("CONTINUE?").font(font).foregroundStyle(color)
        case .offline:
            Text("GAME OVER").font(font).foregroundStyle(ArcadeSkin.color(.waiting).opacity(0.7))
        }
    }
}
