import SwiftUI

/// Castle hall: heraldic banners hung on a stone wall. Waiting banners are lit by a flickering torch,
/// busy ones are at work, idle ones hang dim. Serif type, gold trim.
struct MedievalSkin: Skin {
    let grid = GridMetrics(minTileWidth: 120, maxTileWidth: 190, spacing: 10, padding: 10)
    let textColor = Color(hex: 0xF3E6C4)
    let secondaryTextColor = Color(hex: 0xA8957A)

    static let gold = Color(hex: 0xD4AF37)
    static let parchment = Color(hex: 0xF3E6C4)
    static let torch = Color(hex: 0xFF8A1E)

    let controls = ControlStyle(accent: gold, track: Color(hex: 0x3A332D), cap: Color(hex: 0x5A4632),
                                capEdge: gold.opacity(0.6), label: Color(hex: 0xA8957A), value: parchment,
                                design: .serif, radius: 3)

    func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Heraldic tinctures: gules for a summons, azure at work, ochre at rest, purpure for a pinned rest.
    static let pinnedIdle = Color(hex: 0x5B2A86)

    static func color(_ status: SessionStatus) -> Color {
        switch status {
        case .waiting: return Color(hex: 0xA3201E)
        case .idle:    return Color(hex: 0x8A6A22)
        case .busy:    return Color(hex: 0x24508F)
        case .unknown: return Color(hex: 0x4F4F55)
        case .dormant: return Color(hex: 0x3E4A3A)
        case .offline: return Color(hex: 0x3A3633)
        }
    }

    func background() -> AnyView {
        AnyView(
            ZStack {
                Color(hex: 0x15120F)
                // Stone courses: staggered blocks with fixed pseudo-random shading, drawn once.
                Canvas { ctx, size in
                    var seed: UInt64 = 0x51ED270B
                    func next() -> CGFloat {
                        seed = seed &* 6364136223846793005 &+ 1442695040888963407
                        return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
                    }
                    let rowHeight: CGFloat = 18, mortar: CGFloat = 1.5
                    var y: CGFloat = 0, row = 0
                    while y < size.height {
                        var x: CGFloat = row % 2 == 0 ? 0 : -18
                        while x < size.width {
                            let w = 30 + next() * 22
                            let rect = CGRect(x: x + mortar / 2, y: y + mortar / 2,
                                              width: w - mortar, height: rowHeight - mortar)
                            let tone = 0.16 + next() * 0.07
                            ctx.fill(Path(roundedRect: rect, cornerRadius: 2),
                                     with: .color(Color(red: tone + 0.02, green: tone, blue: tone - 0.02)))
                            x += w
                        }
                        y += rowHeight; row += 1
                    }
                }
                // Torchlight from above, darkness below.
                LinearGradient(colors: [Self.torch.opacity(0.10), .clear, .black.opacity(0.45)],
                               startPoint: .top, endPoint: .bottom)
            }
        )
    }

    func header(_ summary: PanelSummary) -> AnyView {
        AnyView(
            HStack(spacing: 8) {
                Text("⚜ The Great Hall")
                    .font(.system(size: 12.5, weight: .bold, design: .serif))
                    .foregroundStyle(Self.gold)
                Spacer()
                Group {
                    if summary.waiting > 0 {
                        Text("\(summary.waiting) summons").foregroundStyle(Color(hex: 0xE0605A))
                    }
                    Text("\(summary.busy) at work")
                }
                .font(.system(size: 10.5, weight: .medium, design: .serif).italic())
                .foregroundStyle(Self.parchment.opacity(0.7))
            }
            .lineLimit(1)
            .frame(height: 24)
        )
    }

    func tile(_ model: TileModel, _ state: TileState) -> AnyView {
        AnyView(HeraldicBanner(model: model, state: state))
    }
}

/// Hanging banner: straight sides, a point at the bottom.
private struct BannerShape: InsettableShape {
    var tail: CGFloat = 12
    var inset: CGFloat = 0

    func path(in r: CGRect) -> Path {
        let r = r.insetBy(dx: inset, dy: inset)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - tail))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - tail))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> Self { var s = self; s.inset += amount; return s }
}

private struct HeraldicBanner: View {
    let model: TileModel
    let state: TileState

    private var color: Color { model.pinnedIdle ? MedievalSkin.pinnedIdle : MedievalSkin.color(model.status) }
    private var burning: Bool { model.status == .waiting && !state.reduceMotion }
    private var dim: Bool { (model.status == .idle && !model.pinned) || model.status.isAsleep }

    private var charge: String {
        switch model.status {
        case .waiting: return "flame.fill"
        case .busy: return "hammer.fill"
        case .idle: return "moon.fill"
        case .unknown: return "questionmark"
        case .dormant: return "zzz"
        case .offline: return "shield.slash"
        }
    }

    var body: some View {
        let shape = BannerShape()
        VStack(spacing: 0) {
            // Iron rod the banner hangs from.
            Capsule()
                .fill(LinearGradient(colors: [Color(hex: 0x6B5A48), Color(hex: 0x2E241B)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: 5)
                .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
            VStack(spacing: 3) {
                Image(systemName: charge)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.status == .waiting ? MedievalSkin.torch : MedievalSkin.gold)
                    .flicker(burning, .torch)
                    .padding(.top, 5)
                Text(model.name)
                    .font(.system(size: 11.5, weight: .bold, design: .serif))
                    .foregroundStyle(MedievalSkin.parchment)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Text("House \(model.project)")
                    .font(.system(size: 9, weight: .regular, design: .serif).italic())
                    .foregroundStyle(MedievalSkin.parchment.opacity(0.75))
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 2)
                statusLine
                Text(model.shortDuration)
                    .font(.system(size: 9.5, weight: .semibold, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(MedievalSkin.gold.opacity(0.9))
            }
            .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
            .padding(.horizontal, 9)
            .padding(.bottom, 15)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                ZStack {
                    // Torch glow behind a summoning banner.
                    if model.status == .waiting {
                        BlinkingFill(color: MedievalSkin.torch.opacity(0.35), cornerRadius: 4, blinking: burning,
                                     glow: 12, flicker: .torch)
                            .padding(4)
                    }
                    shape.fill(color.opacity(dim ? 0.55 : 1))
                        .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
                    // Cloth folds.
                    shape.fill(LinearGradient(stops: [
                        .init(color: .white.opacity(0.08), location: 0),
                        .init(color: .black.opacity(0.18), location: 0.25),
                        .init(color: .white.opacity(0.06), location: 0.5),
                        .init(color: .black.opacity(0.18), location: 0.75),
                        .init(color: .white.opacity(0.08), location: 1),
                    ], startPoint: .leading, endPoint: .trailing))
                    shape.fill(LinearGradient(colors: [.clear, .black.opacity(0.25)],
                                              startPoint: .top, endPoint: .bottom))
                    shape.inset(by: 3).stroke(MedievalSkin.gold.opacity(dim ? 0.45 : 0.85), lineWidth: 1.2)
                    if state.hovering {
                        shape.fill(.white.opacity(0.07))
                    }
                }
                .padding(.horizontal, 4)
            )
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .top)
        .scaleEffect(state.pressed ? 0.97 : 1, anchor: .top)
        .animation(.easeOut(duration: 0.12), value: state.pressed)
        .animation(.easeOut(duration: 0.15), value: state.hovering)
    }

    @ViewBuilder private var statusLine: some View {
        let font = Font.system(size: 9, weight: .semibold, design: .serif).smallCaps()
        switch model.status {
        case .waiting:
            Text("Summons: \(model.waitingFor ?? "thy presence")")
                .font(font).foregroundStyle(Color(hex: 0xFFD9A0)).lineLimit(1)
        case .busy:
            Text("At work").font(font).foregroundStyle(MedievalSkin.parchment.opacity(0.85))
        case .idle:
            Text("At rest").font(font).foregroundStyle(MedievalSkin.parchment.opacity(0.6))
        case .unknown:
            Text(model.rawStatus).font(font).foregroundStyle(MedievalSkin.parchment.opacity(0.7)).lineLimit(1)
        case .dormant:
            Text("Slumbering").font(font).foregroundStyle(MedievalSkin.parchment.opacity(0.55))
        case .offline:
            Text("Departed").font(font).foregroundStyle(MedievalSkin.parchment.opacity(0.5))
        }
    }
}
