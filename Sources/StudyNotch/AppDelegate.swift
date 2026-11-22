import AppKit
import UniformTypeIdentifiers

/// A menu item that runs a closure.
private final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) {
        fatalError("not used")
    }

    @objc private func fire() {
        handler()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = AppModel()
    private var island: IslandController?
    private var popup: AskPopupController?
    private let rightClick = RightClickWatcher()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
                .filter { $0 != NSRunningApplication.current }
            if !others.isEmpty {
                NSApp.terminate(nil)
                return
            }
        }
        model.onAskAPIKey = { [weak self] in self?.askAPIKey() }
        model.onChoose = { [weak self] folders, done in self?.choose(folders: folders, done: done) }
        model.start()
        island = IslandController(model: model)
        popup = AskPopupController(model: model)
        if UITest.active { UITest.run(model: model) } else { ClaudeApp.watch() }

        // Right click on highlighted text, in any app, session or not: our button sits on top of the menu.
        rightClick.shouldOffer = { [model] in model.selection.hasSelection() }
        rightClick.label = { [model] in model.rightClickLabel }
        rightClick.onAsk = { [model] point in model.askFromRightClick(at: point) }
        model.selection.onControlClick = { [weak self] in self?.rightClick.begin() }
        rightClick.start()

        // The island is invisible while idle on a notch, so the menu bar always has a way in.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "highlighter", accessibilityDescription: "StudyNotch")
            ?? NSImage(systemSymbolName: "book.closed", accessibilityDescription: "StudyNotch")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let session = model.session {
            let header = NSMenuItem(title: "\(session.preset.course) · \(model.remainingShort)", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(ActionItem("End session") { [model] in model.endSession() })
        } else {
            let start = NSMenuItem(title: "Start a session", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for course in model.config.courses {
                sub.addItem(ActionItem("\(course) · \(model.config.sessionMinutes) min") { [model] in model.start(course: course) })
            }
            start.submenu = sub
            menu.addItem(start)
        }
        menu.addItem(ActionItem("Ask") { [model] in model.manualAsk() })
        menu.addItem(ActionItem("Capture and ask") { [model] in model.captureAsk() })
        menu.addItem(.separator())

        // Which AI answers is changed only in the setup card, where connecting asks first.
        let ai = model.connectedAI.map { "AI connection: \($0.label)…" } ?? "Connect an AI…"
        menu.addItem(ActionItem(ai) { [model] in model.openSetup(step: .ai) })
        if model.connectedAI == .claudeCLI, model.connectedAccount == .mac {
            menu.addItem(ActionItem("Keep questions in the Claude app", checked: model.config.ai.keepInClaude) { [model] in
                model.toggleKeepInClaude()
            })
        }

        let where_ = NSMenuItem(title: "Notch island position", action: nil, keyEquivalent: "")
        let whereMenu = NSMenu()
        for (value, title) in [("notch", "Screen with the notch"), ("main", "Screen with the menu bar"), ("mouse", "Screen with the pointer")] {
            whereMenu.addItem(ActionItem(title, checked: model.config.display == value) { [model] in model.setDisplay(value) })
        }
        where_.submenu = whereMenu
        menu.addItem(where_)

        menu.addItem(ActionItem("Sounds", checked: model.config.sounds) { [model] in model.toggleSounds() })
        menu.addItem(ActionItem("React to screenshots outside a session", checked: model.config.offerOutsideSession) { [model] in
            model.toggleOfferOutsideSession()
        })
        menu.addItem(ActionItem("Show connections and permissions") { [model] in model.openSetup() })
        menu.addItem(.separator())
        menu.addItem(ActionItem("Open course folder") {
            Paths.ensure()
            NSWorkspace.shared.open(Paths.courses)
        })
        menu.addItem(ActionItem("Open settings file") {
            Paths.ensure()
            NSWorkspace.shared.open(Paths.config)
        })
        menu.addItem(ActionItem("Reload settings") { [model] in model.reloadConfig() })
        menu.addItem(.separator())
        menu.addItem(ActionItem("Quit StudyNotch") { NSApp.terminate(nil) })

        // AppKit greys out items whose target does not validate; these are all plain actions.
        menu.autoenablesItems = false
    }

    /// The Mac's Open panel, for linking a folder or adding PDFs to a course.
    private func choose(folders: Bool, done: @escaping ([URL]) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = folders
        panel.canChooseFiles = !folders
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        if !folders { panel.allowedContentTypes = [.pdf] }
        panel.message = folders ? "Link a folder to this course. Its PDFs are read where they are; nothing is copied."
                                : "Add PDFs to this course. Each one is copied into the course’s folder."
        panel.prompt = folders ? "Link" : "Add"
        panel.begin { response in
            done(response == .OK ? panel.urls : [])
        }
    }

    /// The user types the key themselves; it goes straight to the Keychain.
    private func askAPIKey() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Anthropic API key"
        alert.informativeText = "The key is stored only in this Mac’s Keychain. Save it empty to remove it."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "sk-ant-…"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                Keychain.delete()
                if model.connectedAI == .apiKey { model.disconnect() }
            } else {
                // Typing a key in is the student's own connect.
                Keychain.save(value)
                model.connect(.apiKey)
            }
            model.refresh += 1
        }
    }
}
