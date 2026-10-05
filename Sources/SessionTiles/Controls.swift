import SwiftUI
import AppKit

/// Colors and type for the control strip. Each skin supplies one; the controls themselves are shared.
struct ControlStyle {
    /// Lit parts: switch when on, knob pointer and current detent, fader fill.
    var accent: Color
    /// Grooves, unlit detents, switch when off.
    var track: Color
    var cap: Color
    var capEdge: Color
    var label: Color
    var value: Color
    var design: Font.Design = .default
    var radius: CGFloat
    /// Soft glow on lit parts.
    var glow = false

    func font(_ size: CGFloat, _ weight: Font.Weight) -> Font { .system(size: size, weight: weight, design: design) }
}

/// Bottom strip: SHOW ALL switch, STATUS knob, STANDBY fader, SKIN selector.
struct ControlDeck: View {
    static let visibleKey = "showControls"

    let style: ControlStyle
    @Binding var showAll: Bool
    @Binding var status: StatusFilter
    @Binding var standbyStop: Int
    @Binding var skin: SkinID
    /// Live sessions the filters currently hide.
    let hidden: Int

    var body: some View {
        let statuses = StatusFilter.allCases
        let knobIndex = statuses.firstIndex(of: status) ?? 0
        // The fader only matters while idle sessions can show.
        let faderLive = !showAll && (status == .any || status == .idle)
        VStack(spacing: 6) {
            Rectangle().fill(style.track).frame(height: 1)
            HStack(alignment: .top, spacing: 14) {
                Labeled(style: style, caption: "SHOW ALL",
                        value: showAll ? "ON" : (hidden > 0 ? "\(hidden) HIDDEN" : "OFF")) {
                    ToggleSwitch(style: style, isOn: showAll) { showAll.toggle() }
                }
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Show all sessions")
                .accessibilityValue(showAll ? "On" : "Off")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { showAll.toggle() }
                .help("Show every live session, ignoring the status and standby filters")

                Labeled(style: style, caption: "STATUS", value: status.label) {
                    Knob(style: style, count: statuses.count, index: knobIndex) { status = statuses[$0] }
                }
                .fixedSize()
                .dimmed(showAll)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Status filter")
                .accessibilityValue(status.label)
                .accessibilityAdjustableAction { dir in
                    let i = knobIndex + (dir == .increment ? 1 : -1)
                    if statuses.indices.contains(i) { status = statuses[i] }
                }
                .help("Status filter: click or scroll to turn, drag up/down, Option-click to turn back")

                Labeled(style: style, caption: "STANDBY", value: "≤ " + TileFilter.standbyLabel(standbyStop)) {
                    Fader(style: style, count: TileFilter.standbyStops.count, index: standbyStop) { standbyStop = $0 }
                }
                .frame(maxWidth: .infinity)
                .dimmed(!faderLive)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Show idle sessions for")
                .accessibilityValue(TileFilter.standbyLabel(standbyStop))
                .accessibilityAdjustableAction { dir in
                    let i = standbyStop + (dir == .increment ? 1 : -1)
                    if TileFilter.standbyStops.indices.contains(i) { standbyStop = i }
                }
                .help("How long idle (standby) sessions stay on the panel; ∞ keeps them all")

                Labeled(style: style, caption: "SKIN", value: skin.shortName) {
                    SkinButton(style: style, skin: $skin)
                }
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Skin")
                .accessibilityValue(skin.displayName)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { skin = SkinID.allCases[((SkinID.allCases.firstIndex(of: skin) ?? 0) + 1) % SkinID.allCases.count] }
                .help("Change the panel's skin")
            }
        }
    }
}

private extension View {
    func dimmed(_ off: Bool) -> some View {
        opacity(off ? 0.35 : 1).allowsHitTesting(!off)
    }
}

/// Control on top, caption and current value underneath, like a label printed on a panel.
private struct Labeled<Control: View>: View {
    let style: ControlStyle
    let caption: String
    let value: String
    @ViewBuilder let control: Control

    var body: some View {
        VStack(spacing: 2) {
            control.frame(height: 34)
            Text(caption)
                .font(style.font(8, .bold))
                .tracking(0.8)
                .foregroundStyle(style.label)
            Text(value)
                .font(style.font(9, .semibold))
                .monospacedDigit()
                .foregroundStyle(style.value)
        }
        .lineLimit(1)
    }
}

private struct ToggleSwitch: View {
    let style: ControlStyle
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        let r = min(style.radius, 9)
        ZStack(alignment: isOn ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(isOn ? style.accent : style.track)
                .shadow(color: style.glow && isOn ? style.accent.opacity(0.7) : .clear, radius: 4)
            Cap(style: style, radius: max(r - 2, 1))
                .frame(width: 14, height: 14)
                .padding(2)
        }
        .frame(width: 32, height: 18)
        .animation(.easeOut(duration: 0.15), value: isOn)
        .overlay(PointerSurface(onUp: { _, _ in toggle() }))
    }
}

/// Rotary knob with `count` detents spread over 270°.
private struct Knob: View {
    let style: ControlStyle
    let count: Int
    let index: Int
    let set: (Int) -> Void
    @State private var dragStart: Int?

    private static let size: CGFloat = 34
    private static let stepDistance: CGFloat = 14

    private func angle(_ i: Int) -> Angle {
        .degrees(count > 1 ? -135 + 270 * Double(i) / Double(count - 1) : 0)
    }

    private func clamp(_ i: Int) -> Int { min(max(i, 0), count - 1) }

    var body: some View {
        let s = Self.size
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == index ? style.accent : style.track)
                    .shadow(color: style.glow && i == index ? style.accent : .clear, radius: 2)
                    .frame(width: 3.5, height: 3.5)
                    .frame(width: s, height: s, alignment: .top)
                    .rotationEffect(angle(i))
            }
            Cap(style: style, radius: 13)
                .frame(width: 24, height: 24)
            Capsule()
                .fill(style.accent)
                .frame(width: 2.5, height: 7)
                .padding(.top, 7)
                .frame(width: s, height: s, alignment: .top)
                .rotationEffect(angle(index))
        }
        .frame(width: s, height: s)
        .animation(.easeOut(duration: 0.12), value: index)
        .overlay(PointerSurface(
            onDown: { _ in dragStart = index },
            // Up or right turns clockwise.
            onDrag: { _, t in
                guard let start = dragStart else { return }
                let steps = Int(((t.width - t.height) / Self.stepDistance).rounded(.towardZero))
                let i = clamp(start + steps)
                if i != index { set(i) }
            },
            onUp: { _, dragged in
                dragStart = nil
                guard !dragged else { return }
                let back = NSEvent.modifierFlags.contains(.option)
                set((index + (back ? count - 1 : 1)) % count)
            },
            onScroll: { step in
                let i = clamp(index + step)
                if i != index { set(i) }
            }))
    }
}

/// Horizontal fader that snaps to `count` stops.
private struct Fader: View {
    let style: ControlStyle
    let count: Int
    let index: Int
    let set: (Int) -> Void

    private static let capWidth: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, mid = geo.size.height / 2
            let inset = Self.capWidth / 2
            let span = max(w - 2 * inset, 1)
            let x = { (i: Int) in inset + span * CGFloat(i) / CGFloat(max(count - 1, 1)) }
            let stop = { (px: CGFloat) in min(max(Int(((px - inset) / span * CGFloat(count - 1)).rounded()), 0), count - 1) }
            ZStack(alignment: .topLeading) {
                ForEach(0..<count, id: \.self) { i in
                    Rectangle()
                        .fill(i <= index ? style.accent.opacity(0.8) : style.track)
                        .frame(width: 1, height: i == 0 || i == count - 1 ? 6 : 4)
                        .position(x: x(i), y: mid + 11)
                }
                Capsule()
                    .fill(style.track)
                    .frame(width: span, height: 3)
                    .position(x: w / 2, y: mid)
                Capsule()
                    .fill(style.accent)
                    .shadow(color: style.glow ? style.accent.opacity(0.8) : .clear, radius: 3)
                    .frame(width: max(x(index) - inset, 0), height: 3)
                    .position(x: inset + (x(index) - inset) / 2, y: mid)
                Cap(style: style, radius: min(style.radius, 2.5))
                    .overlay(Rectangle().fill(style.accent).frame(width: 6, height: 1.5))
                    .frame(width: Self.capWidth, height: 18)
                    .position(x: x(index), y: mid)
            }
            .animation(.easeOut(duration: 0.1), value: index)
            .overlay(PointerSurface(
                onDown: { p in if stop(p.x) != index { set(stop(p.x)) } },
                onDrag: { p, _ in if stop(p.x) != index { set(stop(p.x)) } },
                onScroll: { step in
                    let i = min(max(index + step, 0), count - 1)
                    if i != index { set(i) }
                }))
        }
        .frame(minWidth: 70)
    }
}

/// Square cap with a palette icon; pops up a menu of skins.
private struct SkinButton: View {
    let style: ControlStyle
    @Binding var skin: SkinID

    var body: some View {
        Cap(style: style, radius: min(style.radius, 5))
            .overlay(Image(systemName: "paintpalette.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(style.accent))
            .frame(width: 26, height: 22)
            .overlay(PointerSurface(menu: {
                SkinID.allCases.map { id in
                    MenuChoice(title: id.displayName, checked: id == skin) { skin = id }
                }
            }))
    }
}

/// Knob / switch / fader cap: the skin's cap color with a top sheen and an edge.
private struct Cap: View {
    let style: ControlStyle
    let radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape.fill(style.cap)
            .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.22), .clear],
                                               startPoint: .top, endPoint: .bottom)))
            .overlay(shape.strokeBorder(style.capEdge, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
    }
}

// MARK: - Mouse input

/// Transparent AppKit view that takes a control's mouse input. The panel is movable by its background,
/// so a plain SwiftUI drag gesture can end up dragging the window; this view opts out of that, accepts
/// the first click in the non-activating panel, and turns scroll-wheel motion into whole steps.
/// Locations are in the view's own coordinates, top-left origin.
private struct PointerSurface: NSViewRepresentable {
    var onDown: (CGPoint) -> Void = { _ in }
    var onDrag: (_ location: CGPoint, _ translation: CGSize) -> Void = { _, _ in }
    var onUp: (_ location: CGPoint, _ dragged: Bool) -> Void = { _, _ in }
    /// +1 for scrolling up (finger up on a trackpad, whatever the natural-scrolling setting), -1 for down.
    var onScroll: (Int) -> Void = { _ in }
    /// When set, a press pops up these choices as a menu under the view instead of tracking the mouse.
    var menu: (() -> [MenuChoice])?

    func makeNSView(context: Context) -> PointerSurfaceView { PointerSurfaceView() }
    func updateNSView(_ view: PointerSurfaceView, context: Context) { view.handlers = self }
}

private final class PointerSurfaceView: NSView {
    var handlers: PointerSurface?
    private var start: CGPoint?
    private var dragged = false
    private var scrolled: CGFloat = 0

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func location(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    override func mouseDown(with e: NSEvent) {
        if let choices = handlers?.menu?() {
            let menu = NSMenu()
            for c in choices { menu.addItem(ClosureMenuItem(c)) }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY + 4), in: self)
            return
        }
        let p = location(e)
        start = p
        dragged = false
        handlers?.onDown(p)
    }

    override func mouseDragged(with e: NSEvent) {
        guard let start else { return }
        let p = location(e)
        let t = CGSize(width: p.x - start.x, height: p.y - start.y)
        if !dragged && hypot(t.width, t.height) < 3 { return }  // ignore jitter in a click
        dragged = true
        handlers?.onDrag(p, t)
    }

    override func mouseUp(with e: NSEvent) {
        guard start != nil else { return }
        start = nil
        handlers?.onUp(location(e), dragged)
    }

    override func scrollWheel(with e: NSEvent) {
        var d = abs(e.scrollingDeltaY) >= abs(e.scrollingDeltaX) ? e.scrollingDeltaY : -e.scrollingDeltaX
        if e.isDirectionInvertedFromDevice { d = -d }
        // Trackpads report points, wheels report lines.
        scrolled += e.hasPreciseScrollingDeltas ? d / 16 : d
        while scrolled >= 1 { scrolled -= 1; handlers?.onScroll(1) }
        while scrolled <= -1 { scrolled += 1; handlers?.onScroll(-1) }
    }
}

struct MenuChoice {
    let title: String
    let checked: Bool
    let action: () -> Void
}

private final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void

    init(_ c: MenuChoice) {
        run = c.action
        super.init(title: c.title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = c.checked ? .on : .off
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { run() }
}
