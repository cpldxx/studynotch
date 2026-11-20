import AppKit
import ApplicationServices

struct FrontInfo {
    var appName: String
    var bundleID: String
    var pid: pid_t
    var title: String
    var url: String?

    var host: String? {
        guard let url, let host = URL(string: url)?.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

enum Verdict: Equatable {
    case allowed, distract, neutral
}

/// Reads what is in front: app, window title, and the tab address for known browsers.
/// Nothing read here leaves the Mac.
final class FocusWatcher {
    static let chromiumBrowsers = [
        "com.google.Chrome", "com.google.Chrome.canary", "com.microsoft.edgemac", "com.brave.Browser",
        "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.naver.Whale", "com.operasoftware.Opera",
    ]

    static func urlScript(for bundleID: String) -> String? {
        if bundleID == "com.apple.Safari" {
            return "tell application id \"com.apple.Safari\" to return URL of current tab of front window"
        }
        if chromiumBrowsers.contains(bundleID) {
            return "tell application id \"\(bundleID)\" to return URL of active tab of front window"
        }
        return nil
    }

    private var urlCache: (bundle: String, url: String, at: Date)?
    private var fetching = false

    func snapshot(withURL: Bool = true) -> FrontInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let bundle = app.bundleIdentifier ?? ""
        var info = FrontInfo(appName: app.localizedName ?? "", bundleID: bundle, pid: app.processIdentifier,
                             title: Self.windowTitle(pid: app.processIdentifier), url: nil)
        if withURL, Self.urlScript(for: bundle) != nil {
            if let cached = urlCache, cached.bundle == bundle, Date().timeIntervalSince(cached.at) < 8 {
                info.url = cached.url
            }
            refreshURL(bundle)
        }
        return info
    }

    static func windowTitle(pid: pid_t) -> String {
        guard AXIsProcessTrusted() else { return "" }
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return "" }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success else { return "" }
        return (title as? String) ?? ""
    }

    /// Asks the browser for its front tab in a short-lived helper so the app never waits on it.
    private func refreshURL(_ bundle: String) {
        guard !fetching, let script = Self.urlScript(for: bundle) else { return }
        fetching = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            var url: String?
            if (try? process.run()) != nil {
                let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 4, execute: killer)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                killer.cancel()
                let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if process.terminationStatus == 0, text.contains("://") { url = text }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.fetching = false
                if let url { self.urlCache = (bundle, url, Date()) }
            }
        }
    }

    // MARK: - Rules (pure)

    /// The name shown on the card: the site for a browser tab, otherwise the app.
    static func target(_ info: FrontInfo) -> String {
        info.host ?? info.appName
    }

    /// An entry with a dot is a website (matches the host and its subdomains); anything else is an app name.
    static func matches(_ entry: String, _ info: FrontInfo) -> Bool {
        let rule = entry.lowercased().trimmingCharacters(in: .whitespaces)
        guard !rule.isEmpty else { return false }
        if rule.contains(".") {
            guard let host = info.host else { return false }
            return host == rule || host.hasSuffix("." + rule)
        }
        return info.appName.lowercased().contains(rule)
    }

    static func classify(_ info: FrontInfo, presetAllow: [String], config: AppConfig,
                         tempAllow: Set<String>) -> (verdict: Verdict, target: String) {
        let name = target(info)
        if tempAllow.contains(name) { return (.allowed, name) }
        if (presetAllow + config.allowAlways).contains(where: { matches($0, info) }) { return (.allowed, name) }
        if config.distractions.contains(where: { matches($0, info) }) { return (.distract, name) }
        return (.neutral, name)
    }
}
