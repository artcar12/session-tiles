import SwiftUI
import AppKit
import Combine

@main
struct SessionTilesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(delegate: delegate, store: delegate.store)
        } label: {
            MenuBarLabel(store: delegate.store)
        }
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        let waiting = store.sessions.filter { $0.status == .waiting }.count
        if store.fatalError != nil {
            Image(systemName: "exclamationmark.square")
        } else if waiting > 0 {
            Label("\(waiting)", systemImage: "square.grid.2x2.fill").labelStyle(.titleAndIcon)
        } else {
            Image(systemName: "square.grid.2x2")
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var delegate: AppDelegate
    @ObservedObject var store: SessionStore
    @AppStorage(SkinID.defaultsKey) private var skinID: SkinID = .classic
    @AppStorage(ControlDeck.visibleKey) private var showControls = true

    var body: some View {
        Button(delegate.panelVisible ? "Hide Panel" : "Show Panel") { delegate.togglePanel() }
            .keyboardShortcut("t")
        Toggle("Show Controls", isOn: $showControls)
        Picker("Skin", selection: $skinID) {
            ForEach(SkinID.allCases) { Text($0.displayName).tag($0) }
        }
        Divider()
        Button("Quit Session Tiles") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let store = ProcessInfo.processInfo.environment["SESSION_TILES_DIR"]
        .map { SessionStore(directory: URL(fileURLWithPath: $0, isDirectory: true)) } ?? SessionStore()
    let pins = PinStore()
    private var panel: FloatingPanel?
    private var pinSync: AnyCancellable?
    private static let visibleKey = "panelVisible"

    @Published private(set) var panelVisible = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // belt and braces alongside LSUIElement
        pinSync = store.$sessions.sink { [pins] sessions in
            MainActor.assumeIsolated { pins.update(from: sessions) }
        }
        store.start()
        let p = FloatingPanel(content: TilesView(store: store, pins: pins))
        panel = p
        if UserDefaults.standard.object(forKey: Self.visibleKey) as? Bool ?? true {
            showPanel()
        }
        // Debug aid: SESSION_TILES_SNAPSHOT=/path.png writes the panel's contents to a PNG (and the
        // visible tiles to /path.png.txt) every 2s
        // (self-capture needs no Screen Recording permission).
        if let path = ProcessInfo.processInfo.environment["SESSION_TILES_SNAPSHOT"] {
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.panel?.writeSnapshot(to: path)
                    let lines = VisibilityRules.ordered(self.store.sessions, pinned: self.pins.pins,
                                                        filter: .saved, now: Date()).tiles
                        .map { "\($0.rawStatus)\t\($0.project)\t\($0.name)\t\($0.waitingFor ?? "")\t\($0.id)" }
                    try? (lines.joined(separator: "\n") + "\n").write(toFile: path + ".txt", atomically: true, encoding: .utf8)
                }
            }
        }
    }

    func togglePanel() {
        panelVisible ? hidePanel() : showPanel()
    }

    private func showPanel() {
        panel?.orderFrontRegardless()
        panelVisible = true
        UserDefaults.standard.set(true, forKey: Self.visibleKey)
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        panelVisible = false
        UserDefaults.standard.set(false, forKey: Self.visibleKey)
    }
}

/// Always-on-top, non-activating panel that floats over every Space and remembers its frame.
final class FloatingPanel: NSPanel {
    init<V: View>(content: V) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
            styleMask: [.titled, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(b)?.isHidden = true
        }
        isReleasedWhenClosed = false

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        let host = NSHostingView(rootView: content)
        host.sizingOptions = [.minSize]  // let the user size the panel; SwiftUI only sets the floor
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        contentView = effect

        if !setFrameUsingName("SessionTilesPanel") {
            if let screen = NSScreen.main?.visibleFrame {
                setFrameOrigin(NSPoint(x: screen.maxX - frame.width - 20, y: screen.maxY - frame.height - 20))
            }
        }
        setFrameAutosaveName("SessionTilesPanel")
    }

    /// Prefers a real window-server capture of this window (what's actually on screen, blur and layer
    /// animations included); falls back to cacheDisplay, which misdraws nested layer-backed views.
    func writeSnapshot(to path: String) {
        let url = URL(fileURLWithPath: path)
        if let image = Self.captureWindow(CGWindowID(windowNumber)) {
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            return
        }
        guard let view = contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// CGWindowListCreateImage is marked unavailable in the current SDK, so look it up at runtime.
    /// Debug-only; returns nil if the symbol is gone or capture isn't permitted.
    private static func captureWindow(_ id: CGWindowID) -> CGImage? {
        typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let fn = unsafeBitCast(sym, to: Fn.self)
        let optionIncludingWindow: UInt32 = 1 << 3, boundsIgnoreFraming: UInt32 = 1 << 0
        return fn(.null, optionIncludingWindow, id, boundsIgnoreFraming)?.takeRetainedValue()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
