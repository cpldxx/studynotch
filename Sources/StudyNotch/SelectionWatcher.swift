import AppKit
import ApplicationServices

/// Set while the app itself touches the clipboard, so its own copy is not mistaken for a screenshot.
enum ClipboardGuard {
    static var ignoreUntil = Date.distantPast
}

/// Keeps track of whether the user has probably just highlighted something, and reads the
/// highlighted text when they ask about it. Nothing is read until they ask.
final class SelectionWatcher {
    /// Called for a control-click, which opens the same menu a right click does.
    var onControlClick: (() -> Void)?

    private var monitors: [Any] = []
    private var downPoint = CGPoint.zero
    private var likelyPid: pid_t = 0
    private var webEnabled = Set<pid_t>()

    func start() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event in
            self?.downPoint = NSEvent.mouseLocation
            if event.modifierFlags.contains(.control) { self?.onControlClick?() }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] event in
            self?.mouseUp(event)
        }) { monitors.append(m) }
    }

    /// A drag or a double click usually leaves something highlighted; a plain click clears it.
    private func mouseUp(_ event: NSEvent) {
        if event.modifierFlags.contains(.control) { return }
        let point = NSEvent.mouseLocation
        let moved = hypot(point.x - downPoint.x, point.y - downPoint.y)
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        likelyPid = (moved > 8 || event.clickCount >= 2) ? pid : 0
    }

    /// Whether the app in front probably has text highlighted right now.
    func hasSelection() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }
        enableWebAccessibility(app)
        if let text = Self.selectedText(pid: app.processIdentifier),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        // Apps such as Preview do not say what is highlighted; go by the last drag instead.
        return likelyPid != 0 && likelyPid == app.processIdentifier
    }

    /// The user asked: read the highlighted text now, copying if that is the only way.
    func grabNow(completion: @escaping (String?) -> Void) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            completion(nil)
            return
        }
        enableWebAccessibility(app)
        if let text = Self.selectedText(pid: app.processIdentifier) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                completion(String(trimmed.prefix(6000)))
                return
            }
        }
        guard AXIsProcessTrusted() else {
            completion(nil)
            return
        }
        Self.copySelection { text in
            let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            completion(trimmed.isEmpty ? nil : String(trimmed.prefix(6000)))
        }
    }

    /// Chromium browsers only expose page text once an assistive app asks for it.
    private func enableWebAccessibility(_ app: NSRunningApplication) {
        guard AXIsProcessTrusted(), let bundle = app.bundleIdentifier,
              FocusWatcher.chromiumBrowsers.contains(bundle),
              !webEnabled.contains(app.processIdentifier) else { return }
        webEnabled.insert(app.processIdentifier)
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    // MARK: - Reading the selection

    static func selectedText(pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        var element = focused as! AXUIElement
        for _ in 0..<6 {
            if let text = readSelection(element) { return text }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            element = parent as! AXUIElement
        }
        return nil
    }

    private static func readSelection(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
           let text = value as? String, !text.isEmpty {
            return text
        }
        // Web pages (Safari, Chromium) describe the selection as a marker range.
        var range: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &range) == .success, let range {
            var out: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString, range, &out) == .success,
               let text = out as? String, !text.isEmpty {
                return text
            }
        }
        return nil
    }

    /// Presses ⌘C for the user, reads the text, then puts the clipboard back as it was.
    static func copySelection(completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        let before = pasteboard.changeCount
        ClipboardGuard.ignoreUntil = Date().addingTimeInterval(2)

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyC: CGKeyCode = 8
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            var text: String?
            if pasteboard.changeCount != before {
                text = pasteboard.string(forType: .string)
                pasteboard.clearContents()
                let items = saved.map { pairs -> NSPasteboardItem in
                    let item = NSPasteboardItem()
                    for (type, data) in pairs { item.setData(data, forType: type) }
                    return item
                }
                if !items.isEmpty { pasteboard.writeObjects(items) }
            }
            ClipboardGuard.ignoreUntil = Date().addingTimeInterval(1.5)
            completion(text)
        }
    }
}
