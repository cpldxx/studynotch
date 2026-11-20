import AppKit
import Combine
import SwiftUI

struct NotchGeometry: Equatable {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var hasNotch: Bool

    /// The resting bar on a screen without a notch: small and no taller than the menu bar, so it
    /// does not pretend to be a notch. Same size as Coucou's (MIT).
    static let barWidth: CGFloat = 80
    static let barHeight: CGFloat = 24
    static let fallback = NotchGeometry(notchWidth: barWidth, notchHeight: barHeight, hasNotch: false)

    static func of(_ screen: NSScreen) -> NotchGeometry {
        make(screenWidth: screen.frame.width, safeTop: screen.safeAreaInsets.top,
             leftWidth: screen.auxiliaryTopLeftArea?.width, rightWidth: screen.auxiliaryTopRightArea?.width,
             menuBar: screen.frame.maxY - screen.visibleFrame.maxY)
    }

    static func make(screenWidth: CGFloat, safeTop: CGFloat, leftWidth: CGFloat?, rightWidth: CGFloat?,
                     menuBar: CGFloat) -> NotchGeometry {
        if safeTop > 0, let left = leftWidth, let right = rightWidth {
            let width = screenWidth - left - right
            if width > 40 && width < screenWidth { return NotchGeometry(notchWidth: width, notchHeight: safeTop, hasNotch: true) }
        }
        // The menu bar can be hidden (visible frame up to the top): keep the usual height then.
        let bar = menuBar > 10 ? menuBar : barHeight
        return NotchGeometry(notchWidth: barWidth, notchHeight: min(barHeight, bar), hasNotch: false)
    }
}

/// Never takes focus from the app being read, except when a text field in it is clicked.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// AppKit pushes ordinary windows below the menu bar. This one belongs on top of it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// The app is never the active app, so every click on the island is a "first click".
/// Without this the first click would be swallowed instead of pressing the button.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("not used")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// A fixed transparent canvas at the top centre of one screen. The island is drawn inside it and
/// everything outside the island lets clicks through.
final class IslandController {
    static let canvas = CGSize(width: 760, height: 660)

    private let model: AppModel
    private let panel: IslandPanel
    private var screen: NSScreen?
    private var timer: Timer?
    private var monitors: [Any] = []
    private var displayWatch: AnyCancellable?

    init(model: AppModel) {
        self.model = model
        panel = IslandPanel(contentRect: NSRect(origin: .zero, size: Self.canvas),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        // Above the menu bar, so it can cover the notch area and show over full-screen apps.
        // Set after isFloatingPanel, which would otherwise pull the level back down.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = true

        let host = FirstClickHostingView(rootView: IslandRootView(model: model))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: Self.canvas)
        panel.contentView = host

        model.onIslandKey = { [weak self] want in self?.setKey(want) }
        place(on: pickScreen())
        panel.orderFrontRegardless()

        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // A click anywhere else, in any app, folds the island back into the notch.
        for mask in [NSEvent.EventTypeMask.leftMouseDown, .rightMouseDown] {
            if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
                self?.model.outsideClick()
            }) { monitors.append(monitor) }
        }

        // Chosen in the menu bar menu (or in config.json and read again): move right away.
        // @Published sends before the value is stored, so use the value it sends.
        displayWatch = model.$config.map(\.display).removeDuplicates().dropFirst().sink { [weak self] choice in
            guard let self else { return }
            self.place(on: self.pickScreen(choice))
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.place(on: self.pickScreen())
        }
    }

    private func pickScreen(_ choice: String? = nil) -> NSScreen? {
        let screens = NSScreen.screens
        let mouse = NSEvent.mouseLocation
        guard let index = Self.screenIndex(for: choice ?? model.config.display,
                                           hasNotch: screens.map { $0.safeAreaInsets.top > 0 },
                                           containsMouse: screens.map { $0.frame.contains(mouse) })
        else { return nil }
        return screens[index]
    }

    /// Which screen hosts the island, in `NSScreen.screens` order (the first one has the menu bar).
    /// "notch", the default: the screen with a notch, else the menu bar screen.
    /// "main": the menu bar screen. "mouse": the screen under the pointer.
    static func screenIndex(for choice: String, hasNotch: [Bool], containsMouse: [Bool]) -> Int? {
        guard !hasNotch.isEmpty else { return nil }
        let notch = hasNotch.firstIndex(of: true) ?? 0
        switch choice {
        case "main": return 0
        case "mouse": return containsMouse.firstIndex(of: true) ?? notch
        default: return notch
        }
    }

    private func place(on target: NSScreen?) {
        guard let target else { return }
        screen = target
        let frame = target.frame
        let origin = CGPoint(x: frame.midX - Self.canvas.width / 2, y: frame.maxY - Self.canvas.height)
        panel.setFrame(NSRect(origin: origin, size: Self.canvas), display: true)
        let geo = NotchGeometry.of(target)
        if geo != model.geo { model.geo = geo }
        dlog("placed on screen \(Int(frame.width))x\(Int(frame.height)) notch=\(geo.hasNotch) \(Int(geo.notchWidth))x\(Int(geo.notchHeight))")
    }

    private func setKey(_ want: Bool) {
        if want {
            panel.makeKey()
        } else if panel.isKeyWindow {
            // Hand the keyboard back to the app that was being read.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    private func poll() {
        let mouse = NSEvent.mouseLocation
        // Follow the pointer to another display only while folded, never while a card is open.
        if model.config.display == "mouse", !model.mode.isExpanded,
           let current = screen, !current.frame.contains(mouse),
           let next = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            place(on: next)
        }
        guard let frame = screen?.frame else { return }
        let size = model.size(for: model.mode)
        // A little slack around the island, except the resting bar on a screen without a notch:
        // it must not catch clicks meant for the window right under the menu bar.
        let slack: CGFloat = !model.geo.hasNotch && !model.mode.isExpanded ? 0 : 4
        let rect = CGRect(x: frame.midX - size.width / 2 - slack, y: frame.maxY - size.height - slack,
                          width: size.width + slack * 2, height: size.height + slack)
        let inside = rect.contains(mouse)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }

        // The mascot's eyes follow the pointer: where the pointer is, seen from the mascot.
        let spot = model.mascotSpot
        if spot.visible, !UITest.eyesOnly {
            let at = CGPoint(x: frame.midX - size.width / 2 + spot.x, y: frame.maxY - spot.y)
            PointerLook.shared.update(PointerLook.vector(from: .zero, to: CGPoint(x: mouse.x - at.x, y: at.y - mouse.y)))
        }

        model.pointer(inside: inside)
    }
}
