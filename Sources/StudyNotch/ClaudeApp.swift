import AppKit

/// Puts questions asked with Claude into the Claude app (the user's request, 2026-11-22).
///
/// A question is kept as a Claude Code session in the course's folder (`ClaudeSession`). The Claude
/// app's own link `claude://resume?session=<id>` adds such a session to the app's list, under the
/// folder's name, with the question and the answer. Opening the link again for a session it already
/// has only shows it. StudyNotch opens the link without bringing Claude forward; "Open in Claude"
/// brings it forward. When the Claude app isn't open, the ids wait and are handed over when it opens.
/// Nothing here reads, drives or scrapes the Claude app's windows.
enum ClaudeApp {
    static let bundleID = "com.anthropic.claudefordesktop"
    private static let waitingKey = "claudeSessionsWaiting"

    static func link(_ id: String) -> URL? {
        var c = URLComponents()
        c.scheme = "claude"
        c.host = "resume"
        c.queryItems = [URLQueryItem(name: "session", value: id)]
        return c.url
    }

    static var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }
    static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

    /// After a question's first answer: add it to the Claude app's list, behind other windows.
    static func keep(_ id: String) {
        guard isInstalled else { return }
        if isRunning {
            open(id, bringForward: false)
        } else {
            var list = waiting
            if !list.contains(id) { list.append(id) }
            waiting = list
        }
    }

    /// "Open in Claude": the question's session, in front.
    static func show(_ id: String) {
        open(id, bringForward: true)
    }

    private static func open(_ id: String, bringForward: Bool) {
        guard let url = link(id) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = bringForward
        NSWorkspace.shared.open(url, configuration: config) { _, error in
            if error != nil { dlog("claude app link failed") }
        }
    }

    private static var waiting: [String] {
        get { UserDefaults.standard.stringArray(forKey: waitingKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: waitingKey) }
    }

    /// Hands over the questions that waited, one every two seconds, starting after `delay`.
    private static func handOver(after delay: TimeInterval) {
        let list = waiting
        guard !list.isEmpty else { return }
        waiting = []
        for (i, id) in list.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + Double(i) * 2) { open(id, bringForward: false) }
        }
        dlog("claude app: handed over \(list.count) waiting")
    }

    /// At launch: hand over what waited if Claude is open, and again whenever it opens.
    static func watch() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                                          object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == bundleID { handOver(after: 8) }
        }
        if isRunning { handOver(after: 2) }
    }
}
