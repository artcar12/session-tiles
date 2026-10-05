import SwiftUI
import AppKit
import QuartzCore

// Looping skin animations run as Core Animation layer animations, which the system render server plays
// without waking the app. Driving them from SwiftUI (phaseAnimator / TimelineView) re-ran layout for the
// whole grid every tick and cost 15-30% CPU for a handful of tiles.
//
// Every repeating animation is phase-aligned to the wall clock, so all blinkers on the panel stay in
// sync, like LEDs on real hardware.

/// Decorative AppKit view that never takes clicks, so the SwiftUI Button underneath still gets them.
class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

enum LayerClock {
    /// beginTime that puts a repeating animation with a `cycle`-second period in phase with the wall clock.
    static func alignedBeginTime(for layer: CALayer, cycle: Double) -> CFTimeInterval {
        let phase = Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        return layer.convertTime(CACurrentMediaTime(), from: nil) - phase
    }
}

// MARK: - Blink

extension View {
    /// Fades between full and `low` opacity every `period` seconds. Plain view when disabled
    /// (Reduce Motion, or a state that shouldn't blink).
    ///
    /// The content is re-hosted in its own NSHostingController, and environment inheritance across that
    /// boundary is unreliable (some modifiers like `.minimumScaleFactor` leak through, `.font` may not):
    /// set fonts and colors on the content itself and `.fixedSize()` text. Meant for content with a
    /// natural size or a definite proposal (text, outlines in a `.background`); use `BlinkingFill` for
    /// fills and LEDs.
    @ViewBuilder
    func blink(_ enabled: Bool, low: Double = 0.45, period: Double = 0.6) -> some View {
        if enabled {
            BlinkHost(content: self, low: low, period: period)
        } else {
            self
        }
    }

    /// Like `blink`, but plays an irregular `Flicker` pattern (neon tube, torch flame). Same caveats.
    @ViewBuilder
    func flicker(_ enabled: Bool, _ pattern: Flicker) -> some View {
        if enabled {
            BlinkHost(content: self, low: 0, period: pattern.period, flicker: pattern)
        } else {
            self
        }
    }
}

/// An irregular opacity loop: `values` spread evenly over `period` seconds.
struct Flicker: Equatable {
    var values: [Double]
    var period: Double
    /// Jump between values instead of fading (a buzzing neon tube rather than a flame).
    var discrete = false

    static let torch = Flicker(values: [1, 0.72, 0.95, 0.6, 0.88, 0.78, 1, 0.66, 0.9, 0.82, 1], period: 1.4)
    static let neon = Flicker(values: [1, 1, 1, 1, 0.15, 1, 0.35, 1, 1, 1, 1, 1, 1, 0.1, 0.8, 1, 1, 1],
                              period: 2.6, discrete: true)

    func animation(for layer: CALayer) -> CAAnimation {
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = values.map { Float($0) }
        a.calculationMode = discrete ? .discrete : .linear
        a.duration = period
        a.repeatCount = .infinity
        a.isRemovedOnCompletion = false
        a.beginTime = LayerClock.alignedBeginTime(for: layer, cycle: period)
        return a
    }
}

/// Hosts the SwiftUI content in its own layer and animates that layer's opacity.
private struct BlinkHost<Content: View>: NSViewRepresentable {
    let content: Content
    let low: Double
    let period: Double
    var flicker: Flicker?

    func makeNSView(context: Context) -> BlinkView<Content> { BlinkView(content) }

    func updateNSView(_ view: BlinkView<Content>, context: Context) {
        view.host.rootView = SafeAreaFree(content: content)
        view.configure(low: Float(low), period: period, flicker: flicker)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: BlinkView<Content>, context: Context) -> CGSize? {
        // Unspecified dimensions are probed with a large finite size; content that grows to fill it is
        // flexible, so report SwiftUI's usual 10pt ideal size for it instead of something huge.
        let big: CGFloat = 100_000
        func finite(_ p: CGFloat?) -> CGFloat { p.map { $0.isFinite ? $0 : big } ?? big }
        let fit = view.host.sizeThatFits(in: CGSize(width: finite(proposal.width), height: finite(proposal.height)))
        func resolve(_ v: CGFloat, _ p: CGFloat?) -> CGFloat {
            guard let p else { return v >= big / 2 ? 10 : v }
            return p.isFinite ? min(v, p) : v
        }
        return CGSize(width: resolve(fit.width, proposal.width), height: resolve(fit.height, proposal.height))
    }
}

/// A nested hosting view under the (invisible) title bar would apply the title bar's safe-area inset by
/// itself and shove its content down; the outer layout already handled that.
private struct SafeAreaFree<Content: View>: View {
    let content: Content
    var body: some View { content.ignoresSafeArea() }
}

private final class BlinkView<Content: View>: PassThroughView {
    let host: NSHostingController<SafeAreaFree<Content>>
    private var low: Float = 0.45
    private var period: Double = 0.6
    private var flicker: Flicker?

    init(_ content: Content) {
        host = NSHostingController(rootView: SafeAreaFree(content: content))
        host.sizingOptions = []
        super.init(frame: .zero)
        wantsLayer = true
        host.view.frame = bounds
        addSubview(host.view)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // SwiftUI resizes this view by setting its frame, which doesn't always trigger layout(); keep the
    // hosted view matched on every size change or it renders at a stale size.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        host.view.frame = bounds
    }

    override func layout() {
        super.layout()
        host.view.frame = bounds
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        addAnimationIfNeeded(force: true)
    }

    func configure(low: Float, period: Double, flicker: Flicker?) {
        let changed = low != self.low || period != self.period || flicker != self.flicker
        self.low = low
        self.period = period
        self.flicker = flicker
        addAnimationIfNeeded(force: changed)
    }

    private func addAnimationIfNeeded(force: Bool) {
        guard let layer, window != nil else { return }
        if !force && layer.animation(forKey: "blink") != nil { return }
        if let flicker {
            layer.add(flicker.animation(for: layer), forKey: "blink")
            return
        }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 1
        a.toValue = low
        a.duration = period
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        a.isRemovedOnCompletion = false
        a.beginTime = LayerClock.alignedBeginTime(for: layer, cycle: period * 2)
        layer.add(a, forKey: "blink")
    }
}

// MARK: - Blinking fill

/// A rounded rectangle filling its frame whose color blinks between full and `low` opacity (or plays
/// `flicker`), with an optional glow. Pure CALayer, for backlights, LEDs, lamps and flames.
struct BlinkingFill: NSViewRepresentable {
    var color: Color
    var cornerRadius: CGFloat
    var blinking: Bool
    var low: Double = 0.45
    var period: Double = 0.6
    var glow: CGFloat = 0
    var flicker: Flicker?

    func makeNSView(context: Context) -> BlinkingFillView { BlinkingFillView() }
    func updateNSView(_ view: BlinkingFillView, context: Context) { view.configure(self) }
}

final class BlinkingFillView: PassThroughView {
    private var config: BlinkingFill?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(_ c: BlinkingFill) {
        let old = config
        config = c
        guard let layer else { return }
        let cg = NSColor(c.color).cgColor
        layer.backgroundColor = cg
        layer.cornerRadius = c.cornerRadius
        layer.masksToBounds = false
        layer.shadowColor = cg.copy(alpha: 1)
        layer.shadowOffset = .zero
        layer.shadowRadius = c.glow
        layer.shadowOpacity = c.glow > 0 ? 1 : 0
        if old?.blinking != c.blinking || old?.low != c.low || old?.period != c.period || old?.flicker != c.flicker {
            updateAnimation()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimation()
    }

    private func updateAnimation() {
        guard let layer, let c = config else { return }
        guard c.blinking, window != nil else {
            layer.removeAnimation(forKey: "blink")
            return
        }
        if let f = c.flicker {
            layer.add(f.animation(for: layer), forKey: "blink")
            return
        }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 1
        a.toValue = Float(c.low)
        a.duration = c.period
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        a.isRemovedOnCompletion = false
        a.beginTime = LayerClock.alignedBeginTime(for: layer, cycle: c.period * 2)
        layer.add(a, forKey: "blink")
    }
}

// MARK: - LED chase

/// A row of segments with one lit segment (and a fading tail) running along it.
struct LEDChase: NSViewRepresentable {
    var color: Color
    var animated: Bool
    var count = 10
    var segment = CGSize(width: 5, height: 4)
    var spacing: CGFloat = 2
    var step: Double = 0.1

    func makeNSView(context: Context) -> LEDChaseView { LEDChaseView() }

    func updateNSView(_ view: LEDChaseView, context: Context) {
        view.configure(self)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LEDChaseView, context: Context) -> CGSize? {
        CGSize(width: CGFloat(count) * segment.width + CGFloat(count - 1) * spacing, height: segment.height)
    }
}

final class LEDChaseView: PassThroughView {
    private var config: LEDChase?
    private var segments: [CALayer] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(_ c: LEDChase) {
        let old = config
        config = c
        guard old?.count != c.count || old?.animated != c.animated || old?.step != c.step
                || NSColor(old?.color ?? .clear) != NSColor(c.color) else { return }
        rebuild()
    }

    override func layout() {
        super.layout()
        guard let c = config else { return }
        for (i, seg) in segments.enumerated() {
            seg.frame = CGRect(x: CGFloat(i) * (c.segment.width + c.spacing), y: 0,
                               width: c.segment.width, height: c.segment.height)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { rebuild() }
    }

    /// Opacity of a segment `d` steps behind the lit one.
    private static func level(_ d: Int) -> Float {
        switch d { case 0: return 1; case 1: return 0.55; case 2: return 0.3; default: return 0.12 }
    }

    private func rebuild() {
        guard let layer, let c = config else { return }
        segments.forEach { $0.removeFromSuperlayer() }
        segments = (0..<c.count).map { _ in
            let l = CALayer()
            l.backgroundColor = NSColor(c.color).cgColor
            l.opacity = c.animated ? 0.12 : 0.3
            layer.addSublayer(l)
            return l
        }
        needsLayout = true
        guard c.animated, window != nil else { return }
        let cycle = Double(c.count) * c.step
        let begin = LayerClock.alignedBeginTime(for: layer, cycle: cycle)
        for (i, seg) in segments.enumerated() {
            let a = CAKeyframeAnimation(keyPath: "opacity")
            a.values = (0..<c.count).map { k in Self.level((k - i + c.count) % c.count) }
            a.keyTimes = (0...c.count).map { NSNumber(value: Double($0) / Double(c.count)) }
            a.calculationMode = .discrete
            a.duration = cycle
            a.repeatCount = .infinity
            a.isRemovedOnCompletion = false
            a.beginTime = begin
            seg.add(a, forKey: "chase")
        }
    }
}

// MARK: - Level meter

/// Tiny EQ bars bouncing at slightly different rates, for things that are "playing".
struct LevelMeter: NSViewRepresentable {
    var color: Color = .white
    var animated: Bool
    var bars = 4
    var barWidth: CGFloat = 2
    var spacing: CGFloat = 1.5
    var height: CGFloat = 9

    func makeNSView(context: Context) -> LevelMeterView { LevelMeterView() }

    func updateNSView(_ view: LevelMeterView, context: Context) { view.configure(self) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LevelMeterView, context: Context) -> CGSize? {
        CGSize(width: CGFloat(bars) * barWidth + CGFloat(bars - 1) * spacing, height: height)
    }
}

final class LevelMeterView: PassThroughView {
    private var config: LevelMeter?
    private var barLayers: [CALayer] = []
    private static let rest: [CGFloat] = [0.6, 0.85, 0.5, 0.7, 0.9, 0.4]
    private static let periods: [Double] = [0.23, 0.31, 0.19, 0.27, 0.35, 0.21]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(_ c: LevelMeter) {
        let old = config
        config = c
        guard old?.bars != c.bars || old?.animated != c.animated || NSColor(old?.color ?? .clear) != NSColor(c.color)
        else { return }
        rebuild()
    }

    override func layout() {
        super.layout()
        guard let c = config else { return }
        for (i, bar) in barLayers.enumerated() {
            // Anchored at the bottom edge (layer y grows upward), so scaling grows the bar upward.
            bar.bounds = CGRect(x: 0, y: 0, width: c.barWidth, height: c.height)
            bar.position = CGPoint(x: CGFloat(i) * (c.barWidth + c.spacing) + c.barWidth / 2, y: 0)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { rebuild() }
    }

    private func rebuild() {
        guard let layer, let c = config else { return }
        barLayers.forEach { $0.removeFromSuperlayer() }
        barLayers = (0..<c.bars).map { i in
            let l = CALayer()
            l.backgroundColor = NSColor(c.color).withAlphaComponent(0.9).cgColor
            l.cornerRadius = 0.5
            l.anchorPoint = CGPoint(x: 0.5, y: 0)
            l.transform = CATransform3DMakeScale(1, Self.rest[i % Self.rest.count], 1)
            layer.addSublayer(l)
            return l
        }
        needsLayout = true
        guard c.animated, window != nil else { return }
        for (i, bar) in barLayers.enumerated() {
            let period = Self.periods[i % Self.periods.count]
            let a = CABasicAnimation(keyPath: "transform.scale.y")
            a.fromValue = 0.25
            a.toValue = 1.0
            a.duration = period
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.isRemovedOnCompletion = false
            a.beginTime = LayerClock.alignedBeginTime(for: layer, cycle: period * 2)
            bar.add(a, forKey: "level")
        }
    }
}

// MARK: - Swinging needle

/// Gauge needle pivoting on the bottom-centre of its frame. Angles are degrees from vertical, clockwise
/// positive. Animated, it loops through `angles` over `period`; otherwise it rests on the first one.
struct SwingingNeedle: NSViewRepresentable {
    var color: Color
    var angles: [Double]
    var period: Double = 2
    var animated: Bool
    var width: CGFloat = 1.5

    func makeNSView(context: Context) -> SwingingNeedleView { SwingingNeedleView() }
    func updateNSView(_ view: SwingingNeedleView, context: Context) { view.configure(self) }
}

final class SwingingNeedleView: PassThroughView {
    private var config: SwingingNeedle?
    private let needle = CALayer()
    private let hub = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        needle.anchorPoint = CGPoint(x: 0.5, y: 0)
        layer?.addSublayer(needle)
        layer?.addSublayer(hub)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private static func rotation(_ degrees: Double) -> CGFloat { CGFloat(-degrees * .pi / 180) }

    func configure(_ c: SwingingNeedle) {
        let old = config
        config = c
        guard old?.angles != c.angles || old?.animated != c.animated || old?.period != c.period
                || old?.width != c.width || NSColor(old?.color ?? .clear) != NSColor(c.color) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let cg = NSColor(c.color).cgColor
        needle.backgroundColor = cg
        needle.cornerRadius = c.width / 2
        hub.backgroundColor = cg
        needle.setValue(Self.rotation(c.angles.first ?? 0), forKeyPath: "transform.rotation.z")
        CATransaction.commit()
        needsLayout = true
        updateAnimation()
    }

    override func layout() {
        super.layout()
        guard let c = config else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let pivot = CGPoint(x: bounds.midX, y: 2)
        let length = max(min(bounds.height - 3, bounds.width / 2), 1)
        needle.bounds = CGRect(x: 0, y: 0, width: c.width, height: length)
        needle.position = pivot
        hub.frame = CGRect(x: pivot.x - 2.5, y: pivot.y - 2.5, width: 5, height: 5)
        hub.cornerRadius = 2.5
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimation()
    }

    private func updateAnimation() {
        guard let c = config, c.animated, c.angles.count > 1, window != nil else {
            needle.removeAnimation(forKey: "swing")
            return
        }
        let a = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        let values = c.angles + [c.angles[0]]
        a.values = values.map { Self.rotation($0) }
        a.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: values.count - 1)
        a.duration = c.period
        a.repeatCount = .infinity
        a.isRemovedOnCompletion = false
        a.beginTime = LayerClock.alignedBeginTime(for: needle, cycle: c.period)
        needle.add(a, forKey: "swing")
    }
}
