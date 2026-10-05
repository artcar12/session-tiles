import SwiftUI

/// 1970s reactor control room: pale green enamel panel, instrument modules with black engraved label
/// plates, incandescent indicator lamps and analog dials. Waiting = flashing red SCRAM lamp with the
/// needle pegged in the red, busy = green RUN lamp with a swinging needle, idle = amber standby lamp.
struct ReactorSkin: Skin {
    let grid = GridMetrics(minTileWidth: 160, maxTileWidth: 260, spacing: 8, padding: 10)
    let textColor = Color(hex: 0x1E2219)
    let secondaryTextColor = Color(hex: 0x4A5243)

    static let ink = Color(hex: 0x1E2219)
    static let plate = Color(hex: 0x16181A)
    static let engraving = Color(hex: 0xE8E4D4)

    let controls = ControlStyle(accent: Color(hex: 0xD8352A), track: Color(hex: 0x6F7563), cap: Color(hex: 0x22241F),
                                capEdge: .black.opacity(0.6), label: Color(hex: 0x2E3328), value: ink,
                                design: .monospaced, radius: 3)

    func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Lamp colors.
    static func color(_ status: SessionStatus) -> Color {
        switch status {
        case .waiting: return Color(hex: 0xFF3B2A)
        case .idle:    return Color(hex: 0xFFAA22)
        case .busy:    return Color(hex: 0x4BE065)
        case .unknown: return Color(hex: 0xF4F1E0)
        case .offline: return Color(hex: 0x3C3F38)
        }
    }

    func background() -> AnyView {
        AnyView(
            ZStack {
                LinearGradient(colors: [Color(hex: 0xA9B39C), Color(hex: 0x8D9781)],
                               startPoint: .top, endPoint: .bottom)
                Canvas { ctx, size in
                    // Panel seams every 110pt and a screw in each panel corner.
                    var y: CGFloat = 110
                    while y < size.height {
                        ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.25)))
                        ctx.fill(Path(CGRect(x: 0, y: y + 1, width: size.width, height: 1)), with: .color(.white.opacity(0.2)))
                        y += 110
                    }
                    for (x, y) in [(7.0, 7.0), (size.width - 7, 7), (7, size.height - 7), (size.width - 7, size.height - 7)] {
                        let r = CGRect(x: x - 3, y: y - 3, width: 6, height: 6)
                        ctx.fill(Path(ellipseIn: r), with: .color(Color(hex: 0x6E7566)))
                        ctx.stroke(Path(ellipseIn: r), with: .color(.black.opacity(0.35)), lineWidth: 0.5)
                        var slot = Path()
                        slot.move(to: CGPoint(x: x - 2, y: y + 1))
                        slot.addLine(to: CGPoint(x: x + 2, y: y - 1))
                        ctx.stroke(slot, with: .color(.black.opacity(0.5)), lineWidth: 0.8)
                    }
                }
            }
        )
    }

    func header(_ summary: PanelSummary) -> AnyView {
        AnyView(ReactorHeader(summary: summary))
    }

    func tile(_ model: TileModel, _ state: TileState) -> AnyView {
        AnyView(ReactorModule(model: model, state: state))
    }
}

private struct ReactorHeader: View {
    let summary: PanelSummary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Text("REACTOR CONTROL")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(1)
                .foregroundStyle(ReactorSkin.engraving)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 2).fill(ReactorSkin.plate))
            Spacer()
            HeaderLamp(label: "SCRAM", count: summary.waiting, status: .waiting, flashing: summary.waiting > 0 && !reduceMotion)
            HeaderLamp(label: "STBY", count: summary.idle, status: .idle)
            HeaderLamp(label: "RUN", count: summary.busy, status: .busy)
        }
        .lineLimit(1)
        .frame(height: 24)
    }
}

private struct HeaderLamp: View {
    let label: String
    let count: Int
    let status: SessionStatus
    var flashing = false

    var body: some View {
        HStack(spacing: 3) {
            Lamp(status: count > 0 ? status : .offline, flashing: flashing, size: 7)
            Text("\(label) \(count)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(ReactorSkin.ink.opacity(0.8))
        }
    }
}

/// Round incandescent lamp in a black bezel.
private struct Lamp: View {
    let status: SessionStatus
    let flashing: Bool
    var size: CGFloat = 12

    var body: some View {
        let lit = status != .offline
        ZStack {
            Circle().fill(Color(hex: 0x111210))
                .frame(width: size + 4, height: size + 4)
            BlinkingFill(color: ReactorSkin.color(status), cornerRadius: size / 2, blinking: flashing,
                         low: 0.15, period: 0.45, glow: lit ? size * 0.6 : 0)
                .frame(width: size, height: size)
            // Glass highlight.
            Circle().fill(RadialGradient(colors: [.white.opacity(lit ? 0.6 : 0.2), .clear],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.45))
                .frame(width: size, height: size)
                .allowsHitTesting(false)
        }
    }
}

/// Analog dial: cream face, black scale with a red zone at the top end.
private struct Dial: View {
    let status: SessionStatus
    let animated: Bool

    /// Needle keyframes in degrees from vertical (scale runs -60...60).
    private var angles: [Double] {
        switch status {
        case .waiting: return [55, 59, 53, 58, 54]          // pegged in the red, trembling
        case .busy: return [-25, 20, -5, 38, 5, 30, -15]    // hunting around the working range
        case .idle: return [-48]
        case .unknown: return [0]
        case .offline: return [-60]
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xEDE8D2))
            RoundedRectangle(cornerRadius: 3).strokeBorder(.black.opacity(0.6), lineWidth: 1)
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height - 3)
                let r = min(size.height - 7, size.width / 2 - 4)
                for i in 0...12 {
                    let deg = -60 + Double(i) * 10
                    let a = (deg - 90) * .pi / 180
                    let long = i % 3 == 0
                    let r0 = r - (long ? 5 : 3)
                    var p = Path()
                    p.move(to: CGPoint(x: c.x + cos(a) * r0, y: c.y + sin(a) * r0))
                    p.addLine(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
                    ctx.stroke(p, with: .color(deg >= 40 ? Color(hex: 0xC8281E) : .black.opacity(0.8)),
                               lineWidth: long ? 1.2 : 0.7)
                }
                var red = Path()
                red.addArc(center: c, radius: r - 1, startAngle: .degrees(-50), endAngle: .degrees(-30), clockwise: false)
                ctx.stroke(red, with: .color(Color(hex: 0xC8281E)), lineWidth: 2)
            }
            SwingingNeedle(color: Color(hex: 0x1A1A1A), angles: angles, period: status == .waiting ? 0.6 : 3.2,
                           animated: animated && angles.count > 1, width: 1.3)
                .padding(.horizontal, 4)
                .padding(.top, 4)
                .padding(.bottom, 1)
        }
        .frame(width: 46, height: 28)
    }
}

private struct ReactorModule: View {
    let model: TileModel
    let state: TileState

    private var flashing: Bool { model.status == .waiting && !state.reduceMotion }

    /// Stable channel number from the session id.
    private var channel: String {
        let h = model.session.id.unicodeScalars.reduce(UInt32(7)) { $0 &* 31 &+ $1.value }
        return String(format: "CH-%02d", h % 100)
    }

    private var stamp: (String, Color) {
        switch model.status {
        case .waiting: return ("SCRAM", Color(hex: 0xC8281E))
        case .busy: return ("RUN", Color(hex: 0x2E7D3A))
        case .idle: return ("STBY", Color(hex: 0x9A6510))
        case .unknown: return (model.rawStatus.uppercased(), ReactorSkin.ink)
        case .offline: return ("OFF", ReactorSkin.ink.opacity(0.5))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Engraved label plate.
            HStack(alignment: .top, spacing: 6) {
                Text(model.name.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(ReactorSkin.engraving)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .padding(.trailing, 12)  // room for the pin
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ReactorSkin.plate)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 6) {
                    Lamp(status: model.status, flashing: flashing)
                    let (text, color) = stamp
                    Text(text)
                        .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .overlay(Rectangle().strokeBorder(color, lineWidth: 1))
                    Text(model.clockDuration)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xFFB23A))
                        .fixedSize()
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(Rectangle().fill(Color(hex: 0x141412)))
                    Spacer(minLength: 0)
                    Dial(status: model.status, animated: !state.reduceMotion)
                }
                Text(model.status == .waiting ? (model.waitingFor ?? "operator required").uppercased()
                                              : "\(channel) · \(model.project)")
                    .font(.system(size: 9, weight: model.status == .waiting ? .bold : .medium, design: .monospaced))
                    .foregroundStyle(model.status == .waiting ? Color(hex: 0xC8281E) : ReactorSkin.ink.opacity(0.8))
                    .lineLimit(1).truncationMode(.tail)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xD3CFB8))
                RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: [.white.opacity(0.25), .clear],
                                                                      startPoint: .top, endPoint: .bottom))
                if state.hovering { RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.12)) }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(hex: 0x2B2F27), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1.5)
        .opacity(model.status == .offline ? 0.7 : 1)
        .scaleEffect(state.pressed ? 0.97 : 1)
        .animation(.easeOut(duration: 0.12), value: state.pressed)
        .animation(.easeOut(duration: 0.15), value: state.hovering)
    }
}
