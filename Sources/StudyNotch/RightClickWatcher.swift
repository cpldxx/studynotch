import AppKit
import SwiftUI

// macOS does not let one app add items to another app's right-click menu, except through the
// Services submenu at the bottom. So this places a small button of its own directly on top of
// the menu the moment it opens, lined up with it, and takes it away when the menu closes.

final class AskButtonState: ObservableObject {
    @Published var label = ""
    @Published var hovered = false
}

private struct AskMenuButton: View {
    @ObservedObject var state: AskButtonState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "highlighter")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(state.hovered ? .black : Ink.text)
                Text(state.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(state.hovered ? .black : .white)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(state.hovered ? Ink.primary : Color.black))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.16), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .animation(Motion.hover, value: state.hovered)
    }
}

final class RightClickWatcher {
    static let buttonHeight: CGFloat = 34
    static let gap: CGFloat = 4

    /// Whether something is highlighted in the app in front right now.
    var shouldOffer: () -> Bool = { false }
    var label: () -> String = { "" }
    /// Called with the place that was right-clicked.
    var onAsk: ((CGPoint) -> Void)?

    private let state = AskButtonState()
    private let panel: NSPanel
    private var monitors: [Any] = []
    private var timer: Timer?
    private var clickPoint = CGPoint.zero
    private var frontPid: pid_t = 0
    private var attempts = 0
    private var missing = 0
    private var shownAt = Date.distantPast
    private var fired = false
    private var menuFound = false

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: Self.buttonHeight),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // One step above menus, so the menu never covers it.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        let host = FirstClickHostingView(rootView: AskMenuButton(state: state) { [weak self] in self?.fire() })
        host.sizingOptions = []
        panel.contentView = host
    }

    func start() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown, handler: { [weak self] _ in
            self?.begin()
        }) { monitors.append(m) }
        // While another app's menu is open that app receives the click, so it is caught here too.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            guard let self, self.panel.isVisible else { return }
            if self.panel.frame.contains(NSEvent.mouseLocation) { self.fire() } else { self.hide() }
        }) { monitors.append(m) }
    }

    /// A right click (or control-click) just happened in another app.
    func begin() {
        hide()
        guard shouldOffer() else { return }
        clickPoint = NSEvent.mouseLocation
        frontPid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        attempts = 0
        missing = 0
        fired = false
        menuFound = false
        let t = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let menu = Self.menuRect(near: clickPoint, pid: frontPid)
        if !panel.isVisible {
            attempts += 1
            if let menu {
                menuFound = true
                show(Self.buttonFrame(menu: menu, screen: Self.screenFrame(containing: clickPoint)))
            } else if attempts >= 12 {
                // No native menu showed up; sit just above the pointer instead.
                show(NSRect(x: clickPoint.x, y: clickPoint.y + 8, width: 230, height: Self.buttonHeight))
            }
            return
        }
        let hovered = panel.frame.contains(NSEvent.mouseLocation)
        if hovered != state.hovered { state.hovered = hovered }
        let age = Date().timeIntervalSince(shownAt)
        if menuFound {
            // The menu went away (an item was chosen, or Esc): leave with it.
            if menu == nil {
                missing += 1
                if missing >= 4 { hide() }
            } else {
                missing = 0
            }
        } else if age > 6 {
            hide()
        }
        if age > 40 { hide() }
    }

    private func show(_ frame: NSRect) {
        state.label = label()
        state.hovered = false
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        shownAt = Date()
        dlog("ask button shown menuFound=\(menuFound)")
    }

    private func hide() {
        timer?.invalidate()
        timer = nil
        if panel.isVisible { panel.orderOut(nil) }
    }

    private func fire() {
        guard !fired else { return }
        fired = true
        hide()
        dlog("ask button pressed")
        onAsk?(clickPoint)
    }

    // MARK: - Geometry

    static func screenFrame(containing point: CGPoint) -> NSRect {
        (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.screens.first)?.frame ?? .zero
    }

    /// Where the button goes: on top of the menu, same left edge, at least as wide. If the menu
    /// is right under the top of the screen, it goes underneath instead. (AppKit coordinates.)
    static func buttonFrame(menu: NSRect, screen: NSRect) -> NSRect {
        let width = max(menu.width, 220)
        var y = menu.maxY + gap
        if screen != .zero, y + buttonHeight > screen.maxY { y = menu.minY - gap - buttonHeight }
        var x = menu.minX
        if screen != .zero { x = min(max(screen.minX + 4, x), screen.maxX - width - 4) }
        return NSRect(x: x, y: y, width: width, height: buttonHeight)
    }

    /// The frame of the context menu that just opened at `point`, in AppKit coordinates.
    /// Reading window frames and levels needs no permission; window contents are never read.
    static func menuRect(near point: CGPoint, pid: pid_t) -> NSRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else { return nil }
        let flip = primary.frame.height
        let cgPoint = CGPoint(x: point.x, y: flip - point.y)
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        var best: NSRect?
        for window in list {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == menuLevel,
                  let owner = window[kCGWindowOwnerPID as String] as? Int, pid == 0 || pid_t(owner) == pid,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
            guard rect.width > 60, rect.height > 30, rect.insetBy(dx: -24, dy: -24).contains(cgPoint) else { continue }
            let converted = NSRect(x: rect.minX, y: flip - rect.maxY, width: rect.width, height: rect.height)
            // With submenus open there are several; the root menu is the one touching the click.
            if best == nil || converted.width * converted.height > best!.width * best!.height { best = converted }
        }
        return best
    }
}
