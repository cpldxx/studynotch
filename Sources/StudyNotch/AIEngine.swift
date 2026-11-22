import Foundation
import Security

// The app has no server. An answer comes from one of four things on this Mac, whichever the
// user picks: Claude (the Claude Code inside the Claude app, signed in with their Claude plan),
// ChatGPT (the Codex inside the ChatGPT app, signed in with their ChatGPT plan), Gemini (Google's
// Antigravity CLI, `agy`, signed in with their Google account), or an Anthropic API key (in the Keychain).
// Google's older `gemini` command stopped answering personal Google accounts on 2026-06-18;
// `agy` replaced it, so that is the one used for Gemini.

/// Whose sign-in answers: the one this Mac already has (shared with the Claude or ChatGPT app), or
/// one kept only for StudyNotch, so a student can use another account without signing the apps out.
enum AIAccount: String, CaseIterable {
    case mac, own
}

enum AIKind: String, CaseIterable {
    case claudeCLI = "claude-cli"
    case codexCLI = "codex-cli"
    case geminiCLI = "gemini-cli"
    case apiKey = "api-key"

    var label: String {
        switch self {
        case .claudeCLI: return "Claude"
        case .codexCLI: return "ChatGPT"
        case .geminiCLI: return "Gemini"
        case .apiKey: return "API key"
        }
    }

    /// The command-line tool behind it (nil for the API key).
    var tool: String? {
        switch self {
        case .claudeCLI: return "claude"
        case .codexCLI: return "codex"
        case .geminiCLI: return "agy"
        case .apiKey: return nil
        }
    }

    /// Claude Code and Codex each keep their sign-in in a folder that can be moved, so StudyNotch
    /// can hold its own. `agy` has one Google sign-in for the whole Mac.
    var hasOwnAccount: Bool { self == .claudeCLI || self == .codexCLI }

    /// Pure: the environment that points the tool at StudyNotch's own sign-in instead of the Mac's.
    func accountEnvironment(_ account: AIAccount, folder: String) -> [String: String] {
        guard account == .own else { return [:] }
        switch self {
        case .claudeCLI: return ["CLAUDE_CONFIG_DIR": folder + "/claude"]
        case .codexCLI: return ["CODEX_HOME": folder + "/codex"]
        case .geminiCLI, .apiKey: return [:]
        }
    }

    /// The tool's own sign-out (for StudyNotch's own sign-in only; the Mac's is never touched).
    func signOutArguments() -> [String] {
        switch self {
        case .claudeCLI: return ["auth", "logout"]
        case .codexCLI: return ["logout"]
        case .geminiCLI, .apiKey: return []
        }
    }

    /// The three a student picks from in the first step. The API key is a fallback under them.
    static let choices: [AIKind] = [.claudeCLI, .codexCLI, .geminiCLI]

    /// What it runs through, in the words a student knows.
    var source: String {
        switch self {
        case .claudeCLI: return "Your Claude account"
        case .codexCLI: return "Your ChatGPT account"
        case .geminiCLI: return "Your Google account"
        case .apiKey: return "Anthropic API key"
        }
    }

    /// What the student needs before it can answer, when it isn't on this Mac.
    var getLabel: String {
        switch self {
        case .claudeCLI: return "Get the Claude app"
        case .codexCLI: return "Get the ChatGPT app"
        case .geminiCLI: return "Install"
        case .apiKey: return "Enter a key"
        }
    }

    /// Pure: shell lines that install it and then start its sign-in, when that can be done from a
    /// Terminal window (Gemini's `agy`, with Homebrew; Homebrew puts `agy` next to `brew`). The
    /// Claude and ChatGPT apps are downloaded from their pages instead.
    func installLines(brew: String?) -> [String]? {
        guard self == .geminiCLI, let brew else { return nil }
        let agy = (brew as NSString).deletingLastPathComponent + "/agy"
        return ["'\(brew)' install --cask antigravity-cli || exit 1", "'\(agy)'"]
    }

    /// Where to get it when it isn't on this Mac.
    var getURL: URL? {
        switch self {
        case .claudeCLI: return URL(string: "https://claude.ai/download")
        case .codexCLI: return URL(string: "https://chatgpt.com/download")
        case .geminiCLI: return URL(string: "https://antigravity.google/product/antigravity-cli")
        case .apiKey: return nil
        }
    }

    /// The tool's own sign-in, run once in a Terminal window. `agy` has no sign-in command: opened
    /// on its own the first time, it opens the browser for Google Sign-In.
    func signInArguments() -> [String] {
        switch self {
        case .claudeCLI: return ["auth", "login"]
        case .codexCLI: return ["login"]
        case .geminiCLI, .apiKey: return []
        }
    }

    /// What the sign-in window says before the tool starts.
    var signInHint: String {
        switch self {
        case .claudeCLI: return "Sign in with the Claude account StudyNotch should use, in the browser that opens. This sign-in is only for StudyNotch; the Claude app keeps its own. When it says you are signed in, close this window."
        case .codexCLI: return "Sign in with the ChatGPT account StudyNotch should use, in the browser that opens. This sign-in is only for StudyNotch; the ChatGPT app keeps its own. When it says you are signed in, close this window."
        case .geminiCLI: return "Sign in with your Google account in the browser that opens. When agy shows its prompt, you are signed in: close this window."
        case .apiKey: return ""
        }
    }
}

struct AIRequest {
    var system: String
    var prompt: String
    var imagePath: String?
    var model: String
    /// The course's project: folders the AI may open by itself, read-only. It works in the first.
    /// Empty for a question with no course files.
    var folders: [String] = []
    /// Claude only: the conversation is kept as a Claude Code session with this id, so the Claude
    /// app can show it. nil keeps nothing (`--no-session-persistence`).
    var session: ClaudeSession?
}

/// A question kept in Claude's own session history, in the course's folder, so the Claude app
/// lists it under the course's name (the user's request, 2026-11-22).
struct ClaudeSession: Equatable {
    var id: String
    /// The course's folder. Claude works in it, so the Claude app files the session under its name.
    var folder: String
    /// The session's name in the Claude app. Ignored when continuing.
    var name: String
    /// A follow-up: continue the session instead of starting it.
    var resume: Bool

    /// What the Claude app lists it as: the question, then the picked text, on one line.
    static func name(question: String, quote: String?) -> String {
        var name = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if let quote = quote?.trimmingCharacters(in: .whitespacesAndNewlines), !quote.isEmpty {
            name = name.isEmpty ? quote : name + ": " + quote
        }
        name = name.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        if name.isEmpty { name = "Question" }
        return name.count > 70 ? String(name.prefix(69)).trimmingCharacters(in: .whitespaces) + "…" : name
    }
}

enum AIEvent: Equatable {
    case delta(String)
    case replace(String)
    /// What the AI is doing before its answer, such as opening the course's files.
    case status(String)
    case done
    case failed(String)
}

enum Keychain {
    private static let service = "StudyNotch"
    private static let account = "anthropic-api-key"

    static func save(_ value: String) {
        delete()
        guard let data = value.data(using: .utf8) else { return }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data, let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Finds the `claude`, `codex` and `agy` tools. An app started from Finder gets a short PATH, so the
/// usual install folders are checked first and the login shell is asked once in the background.
final class CLILocator {
    static let shared = CLILocator()
    static let changed = Notification.Name("studynotch.cliLocatorChanged")

    private let lock = NSLock()
    private var found: [String: String] = [:]
    private var shellPath: String?
    /// True when `claude` is the copy that ships inside the Claude desktop app.
    private(set) var claudeFromDesktopApp = false

    /// The Claude desktop app keeps an official Claude Code inside its own support folder,
    /// already signed in with the same account. It answers in the background; the desktop
    /// app's window is never shown or driven.
    static func desktopClaude(home: String) -> String? {
        let root = "\(home)/Library/Application Support/Claude/claude-code"
        let fm = FileManager.default
        guard let versions = try? fm.contentsOfDirectory(atPath: root) else { return nil }
        let newestFirst = versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        for version in newestFirst {
            let folder = "\(root)/\(version)"
            guard let builds = try? fm.contentsOfDirectory(atPath: folder) else { continue }
            for build in builds.sorted() {
                let path = "\(folder)/\(build)/claude.app/Contents/MacOS/claude"
                if fm.isExecutableFile(atPath: path) { return path }
            }
        }
        return nil
    }

    func path(_ name: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return found[name]
    }

    var searchPath: String {
        lock.lock()
        let extra = shellPath
        lock.unlock()
        let base = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        return [extra, "/opt/homebrew/bin:/usr/local/bin", base].compactMap { $0 }.joined(separator: ":")
    }

    func scan() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var dirs = [
            "\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin",
            "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.volta/bin", "\(home)/Library/pnpm",
            "\(home)/.yarn/bin", "\(home)/.asdf/shims", "\(home)/.local/share/mise/shims",
        ]
        let nvm = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvm) {
            dirs += versions.sorted().reversed().map { "\(nvm)/\($0)/bin" }
        }
        var out: [String: String] = [:]
        for name in ["claude", "codex", "agy"] {
            if let dir = dirs.first(where: { fm.isExecutableFile(atPath: "\($0)/\(name)") }) {
                out[name] = "\(dir)/\(name)"
            }
        }
        // The ChatGPT app ships its own Codex, signed in with the same ChatGPT account.
        if out["codex"] == nil {
            out["codex"] = ["/Applications/ChatGPT.app/Contents/Resources/codex", "\(home)/Applications/ChatGPT.app/Contents/Resources/codex"]
                .first { fm.isExecutableFile(atPath: $0) }
        }
        var fromDesktop = false
        if out["claude"] == nil, let bundled = Self.desktopClaude(home: home) {
            out["claude"] = bundled
            fromDesktop = true
        }
        lock.lock()
        found.merge(out) { _, new in new }
        claudeFromDesktopApp = fromDesktop
        lock.unlock()
    }

    /// Homebrew, if this Mac has it (used to install Gemini's `agy`).
    static func brew() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func askLoginShell() {
        DispatchQueue.global(qos: .utility).async {
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            let script = "echo __PATH__$PATH; echo __CLAUDE__$(command -v claude); echo __CODEX__$(command -v codex); echo __AGY__$(command -v agy)"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = ["-lic", script]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            process.standardInput = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return }
            let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: killer)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            killer.cancel()
            let text = String(decoding: data, as: UTF8.self)
            var updates: [String: String] = [:]
            var path: String?
            for line in text.split(whereSeparator: \.isNewline) {
                if line.hasPrefix("__PATH__") { path = String(line.dropFirst(8)) }
                if line.hasPrefix("__CLAUDE__") {
                    let p = String(line.dropFirst(10))
                    if p.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: p) { updates["claude"] = p }
                }
                if line.hasPrefix("__CODEX__") {
                    let p = String(line.dropFirst(9))
                    if p.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: p) { updates["codex"] = p }
                }
                if line.hasPrefix("__AGY__") {
                    let p = String(line.dropFirst(7))
                    if p.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: p) { updates["agy"] = p }
                }
            }
            self.lock.lock()
            if let path, !path.isEmpty { self.shellPath = path }
            for (name, p) in updates where self.found[name] == nil || (name == "claude" && self.claudeFromDesktopApp) {
                self.found[name] = p
                if name == "claude" { self.claudeFromDesktopApp = false }
            }
            self.lock.unlock()
            DispatchQueue.main.async { NotificationCenter.default.post(name: Self.changed, object: nil) }
        }
    }
}

struct ClaudeStreamState {
    var gotPartial = false
    var text = ""
}

final class AIEngine {
    static let shared = AIEngine()
    static let defaultAPIModel = "claude-opus-5-5"

    private var process: Process?
    private var task: Task<Void, Never>?
    private var runID = 0
    /// Points the tool at the connected account's sign-in for the run that is starting.
    private var runEnvironment: [String: String] = [:]
    /// Where the run that is starting works: the course's project folder, if it has one.
    private var runFolder: String?

    /// Whether each tool is signed in, for the Mac's sign-in and for StudyNotch's own: missing
    /// until it has been checked.
    private var signedIn: [AIKind: [AIAccount: Bool]] = [:]
    /// Which account ("name@school.edu · Max"), where the tool says. Shown on screen, never logged.
    private var accounts: [AIKind: [AIAccount: String]] = [:]
    private let statusLock = NSLock()
    static let statusChanged = Notification.Name("studynotch.aiStatusChanged")

    func installed(_ kind: AIKind) -> Bool {
        guard let tool = kind.tool else { return Keychain.load() != nil }
        return CLILocator.shared.path(tool) != nil
    }

    /// true, false, or nil while it is still being checked. A tool with one sign-in for the whole
    /// Mac (Gemini's `agy`) answers the same for both accounts.
    func isSignedIn(_ kind: AIKind, account: AIAccount = .mac) -> Bool? {
        if kind == .apiKey { return Keychain.load() != nil }
        statusLock.lock()
        defer { statusLock.unlock() }
        return signedIn[kind]?[kind.hasOwnAccount ? account : .mac]
    }

    /// The ones that can answer now with the Mac's sign-in (for the log line at launch).
    func available() -> [AIKind] {
        AIKind.allCases.filter { installed($0) && isSignedIn($0) != false }
    }

    /// The environment for a run or a check with this account.
    static func environment(_ kind: AIKind, _ account: AIAccount) -> [String: String] {
        kind.accountEnvironment(account, folder: Paths.accounts.path)
    }

    private var checking = false

    /// Checks each tool's sign-in in the background (about a second each), then tells the app.
    /// A check already running is not started twice.
    func refreshStatus() {
        statusLock.lock()
        if checking { statusLock.unlock(); return }
        checking = true
        statusLock.unlock()
        DispatchQueue.global(qos: .utility).async {
            var result: [AIKind: [AIAccount: Bool]] = [:]
            var found: [AIKind: [AIAccount: String]] = [:]
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            if let p = CLILocator.shared.path("claude") {
                for account in AIAccount.allCases {
                    let text = Self.capture(p, ["auth", "status"], environment: Self.environment(.claudeCLI, account)).text
                    result[.claudeCLI, default: [:]][account] = Self.claudeSignedIn(text)
                    found[.claudeCLI, default: [:]][account] = Self.claudeAccount(text)
                }
            }
            if let p = CLILocator.shared.path("codex") {
                for account in AIAccount.allCases {
                    let env = Self.environment(.codexCLI, account)
                    let out = Self.capture(p, ["login", "status"], environment: env)
                    let ok = Self.codexSignedIn(status: out.status, text: out.text)
                    result[.codexCLI, default: [:]][account] = ok
                    // Codex doesn't say which account; its sign-in file does. Only the email and
                    // the plan are read out of it, and they stay on screen.
                    let folder = env["CODEX_HOME"] ?? ProcessInfo.processInfo.environment["CODEX_HOME"] ?? "\(home)/.codex"
                    if ok, let data = FileManager.default.contents(atPath: folder + "/auth.json") {
                        found[.codexCLI, default: [:]][account] = Self.codexAccount(authJSON: data)
                    }
                }
            }
            if let p = CLILocator.shared.path("agy") {
                // `agy` keeps its Google sign-in in the macOS Keychain. Listing its models is the one
                // way to ask: signed out, it only prints "Please sign in" and opens nothing.
                let env = ProcessInfo.processInfo.environment
                result[.geminiCLI] = [.mac: (env["GEMINI_API_KEY"].map { !$0.isEmpty } ?? false)
                    || Self.geminiSignedIn(models: Self.capture(p, ["models"], timeout: 20).text)]
            }
            self.statusLock.lock()
            self.signedIn = result
            self.accounts = found
            self.checking = false
            self.statusLock.unlock()
            dlog("ai status " + result.map { kind, by in
                "\(kind.rawValue)=\(by[.mac] ?? false)" + (by[.own] == true ? "+own" : "")
            }.sorted().joined(separator: " "))
            DispatchQueue.main.async { NotificationCenter.default.post(name: Self.statusChanged, object: nil) }
        }
    }

    /// Pure: `claude auth status` prints JSON with "loggedIn".
    static func claudeSignedIn(_ text: String) -> Bool {
        guard let start = text.firstIndex(of: "{"), let data = String(text[start...]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return json["loggedIn"] as? Bool ?? false
    }

    /// Pure: `codex login status` says "Logged in …" and exits 0.
    static func codexSignedIn(status: Int32, text: String) -> Bool {
        status == 0 && text.lowercased().contains("logged in") && !text.lowercased().contains("not logged in")
    }

    /// Pure: what `agy models` printed. Signed out, it says "Please sign in …"; signed in, it lists
    /// models after its "Fetching available models..." line.
    static func geminiSignedIn(models text: String) -> Bool {
        let lower = text.lowercased()
        if ["sign in", "signin", "log in", "login", "authenticat", "error"].contains(where: lower.contains) { return false }
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .contains { !$0.isEmpty && !$0.lowercased().hasPrefix("fetching") }
    }

    /// Pure: the model setting is passed only to the AI it names, so a Claude model name never
    /// reaches ChatGPT or Gemini. Empty means each one's own default.
    static func model(_ setting: String, for kind: AIKind) -> String {
        let m = setting.lowercased()
        switch kind {
        case .claudeCLI, .apiKey:
            return m.hasPrefix("claude") || ["opus", "sonnet", "haiku", "fable"].contains(where: m.hasPrefix) ? setting : ""
        case .codexCLI:
            return m.hasPrefix("gpt") || m.hasPrefix("codex") || (m.hasPrefix("o") && m.dropFirst().first?.isNumber == true) ? setting : ""
        case .geminiCLI:
            return m.hasPrefix("gemini") ? setting : ""
        }
    }

    /// Runs a tool briefly and returns what it printed (for status checks only, never a question).
    static func capture(_ path: String, _ arguments: [String], timeout: Double = 12,
                        environment: [String: String] = [:]) -> (status: Int32, text: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = arguments
        p.currentDirectoryURL = Paths.runDir
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (path as NSString).deletingLastPathComponent + ":" + CLILocator.shared.searchPath
        env.merge(environment) { _, new in new }
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        p.standardInput = FileHandle.nullDevice
        Paths.ensure()
        guard (try? p.run()) != nil else { return (-1, "") }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// The AI the student connected, if it can answer now; otherwise nil. Never another one:
    /// being signed in on this Mac (say, in the ChatGPT app) doesn't make an AI answer.
    func resolve(_ preference: String, account: AIAccount = .mac) -> AIKind? {
        Self.resolve(preference, installed: installed, signedIn: { self.isSignedIn($0, account: account) })
    }

    /// Pure: only the connected one, and only while it is on this Mac and not signed out.
    static func resolve(_ preference: String, installed: (AIKind) -> Bool, signedIn: (AIKind) -> Bool?) -> AIKind? {
        guard let kind = AIKind(rawValue: preference), installed(kind), signedIn(kind) != false else { return nil }
        return kind
    }

    /// Which account a sign-in is ("name@school.edu · Max"), so the student sees what they connect.
    func account(_ kind: AIKind, _ account: AIAccount = .mac) -> String? {
        statusLock.lock()
        defer { statusLock.unlock() }
        return accounts[kind]?[kind.hasOwnAccount ? account : .mac]
    }

    /// Pure: the "email" in `claude auth status`, with the plan when it says one.
    static func claudeAccount(_ text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let data = String(text[start...]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String, email.contains("@") else { return nil }
        return labelled(email, plan: json["subscriptionType"] as? String)
    }

    /// Pure: the email and plan inside Codex's sign-in file (the middle part of its ID token).
    static func codexAccount(authJSON: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: authJSON) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any], let token = tokens["id_token"] as? String else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var middle = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while middle.count % 4 != 0 { middle += "=" }
        guard let data = Data(base64Encoded: middle),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = claims["email"] as? String, email.contains("@") else { return nil }
        let plan = (claims["https://api.openai.com/auth"] as? [String: Any])?["chatgpt_plan_type"] as? String
        return labelled(email, plan: plan)
    }

    static func labelled(_ email: String, plan: String?) -> String {
        guard let plan, !plan.isEmpty, plan != "none", plan != "unknown" else { return email }
        return email + " · " + plan.prefix(1).uppercased() + plan.dropFirst()
    }

    /// Signs StudyNotch's own sign-in out (the Mac's is never touched), then calls back on the main queue.
    func signOutOwn(_ kind: AIKind, then: @escaping () -> Void) {
        guard kind.hasOwnAccount, let tool = kind.tool, let path = CLILocator.shared.path(tool) else { then(); return }
        DispatchQueue.global(qos: .utility).async {
            _ = Self.capture(path, kind.signOutArguments(), environment: Self.environment(kind, .own))
            self.statusLock.lock()
            self.signedIn[kind, default: [:]][.own] = false
            self.accounts[kind]?[.own] = nil
            self.statusLock.unlock()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.statusChanged, object: nil)
                then()
            }
        }
    }

    func cancel() {
        runID += 1
        if let p = process, p.isRunning { p.terminate() }
        process = nil
        task?.cancel()
        task = nil
    }

    func run(_ request: AIRequest, kind: AIKind, account: AIAccount = .mac, onEvent: @escaping (AIEvent) -> Void) {
        cancel()
        let id = runID
        runEnvironment = Self.environment(kind, account)
        switch kind {
        case .apiKey: runFolder = nil
        case .claudeCLI: runFolder = request.session?.folder ?? request.folders.first
        default: runFolder = request.folders.first
        }
        let emit: (AIEvent) -> Void = { [weak self] event in
            DispatchQueue.main.async {
                guard let self, self.runID == id else { return }
                onEvent(event)
            }
        }
        switch kind {
        case .claudeCLI: runClaude(request, emit: emit)
        case .codexCLI: runCodex(request, emit: emit)
        case .geminiCLI: runGemini(request, emit: emit)
        case .apiKey: runAPI(request, emit: emit)
        }
    }

    // MARK: - Command lines (pure, so the self-test can check them)

    static func claudeArguments(_ r: AIRequest) -> [String] {
        var args = ["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages"]
        if !r.model.isEmpty { args += ["--model", r.model] }
        args += ["--system-prompt", r.system]
        // Reading only: no shell, no edits, no web. Claude Code lets it read the folder it runs in
        // and the ones added here, and refuses anything else when nobody is there to approve it.
        // It runs in the course's folder when the question is kept, else in the first project folder.
        let home = r.session?.folder ?? r.folders.first
        var readable = r.folders.filter { home == nil || !Self.isInside($0, home!) }
        if let image = r.imagePath { readable.append((image as NSString).deletingLastPathComponent) }
        if r.folders.isEmpty && r.imagePath == nil {
            args += ["--tools", ""]
        } else {
            args += ["--tools", r.folders.isEmpty ? "Read" : "Read,Glob,Grep"]
            for folder in readable { args += ["--add-dir", folder] }
        }
        args += ["--setting-sources", "", "--strict-mcp-config", "--disable-slash-commands"]
        guard let session = r.session else { return args + ["--no-session-persistence"] }
        if session.resume { return args + ["--resume", session.id] }
        return args + ["--session-id", session.id, "--name", session.name]
    }

    /// Whether `path` is `folder` or somewhere inside it.
    static func isInside(_ path: String, _ folder: String) -> Bool {
        let a = (path as NSString).standardizingPath, b = (folder as NSString).standardizingPath
        return a == b || a.hasPrefix(b.hasSuffix("/") ? b : b + "/")
    }

    static func claudeInput(_ r: AIRequest) -> String {
        guard let image = r.imagePath else { return r.prompt }
        return r.prompt + "\n\nScreen capture file: \(image)\nRead this image with the Read tool first, then answer. Do not mention reading the image in the answer."
    }

    static func codexArguments(_ r: AIRequest) -> [String] {
        var args = ["exec", "--json", "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only", "--color", "never"]
        if !r.model.isEmpty { args += ["--model", r.model] }
        if let image = r.imagePath { args += ["--image", image] }
        // The course's project folder is where it works.
        if let project = r.folders.first { args += ["-C", project] }
        return args + ["-"]
    }

    static func codexInput(_ r: AIRequest) -> String {
        "<instructions>\n\(r.system)\n</instructions>\n\n\(r.prompt)"
    }

    /// `agy` has no system-prompt flag: the instructions go first in the prompt. It runs in print
    /// mode, in our empty folder, with slash commands off so a student's "/…" is just text. A
    /// screen capture's folder is added and the file named with "@".
    static func geminiArguments(_ r: AIRequest) -> [String] {
        var args = ["--print", geminiInput(r), "--output-format", "text", "--disable-slash-commands", "--print-timeout", "180s"]
        if !r.model.isEmpty { args += ["--model", r.model] }
        if let image = r.imagePath { args += ["--add-dir", (image as NSString).deletingLastPathComponent] }
        for folder in r.folders { args += ["--add-dir", folder] }
        return args
    }

    static func geminiInput(_ r: AIRequest) -> String {
        var text = "<instructions>\n\(r.system)\n</instructions>\n\n\(r.prompt)"
        if let image = r.imagePath { text += "\n\nScreen capture: @\(image)" }
        return text
    }

    // MARK: - Output parsing (pure)

    static func parseClaudeLine(_ line: String, state: inout ClaudeStreamState) -> [AIEvent] {
        guard let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = object["type"] as? String else { return [] }
        switch type {
        case "stream_event":
            guard let event = object["event"] as? [String: Any],
                  let kind = event["type"] as? String else { return [] }
            // It opens one of the course's files: whatever it said first was not the answer.
            if kind == "content_block_start", let block = event["content_block"] as? [String: Any], block["type"] as? String == "tool_use" {
                state.text = ""
                return [.replace(""), .status(readingStatus)]
            }
            guard kind == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String, !text.isEmpty else { return [] }
            state.gotPartial = true
            state.text += text
            return [.delta(text)]
        case "assistant":
            guard !state.gotPartial,
                  let message = object["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { return [] }
            let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
            guard !text.isEmpty else { return [] }
            state.text = text
            return [.replace(text)]
        case "result":
            let text = (object["result"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if object["is_error"] as? Bool == true {
                return [.failed(friendly(text.isEmpty ? "Claude couldn’t answer." : text, tool: "Claude", signIn: "claude"))]
            }
            guard !text.isEmpty else { return [.done] }
            state.text = text
            return [.replace(text), .done]
        default:
            return []
        }
    }

    static let readingStatus = "Reading your course files"

    /// `codex exec --json` prints one event per line; the answer is the last finished agent message.
    static func parseCodexLine(_ line: String) -> [AIEvent] {
        guard let data = line.data(using: .utf8),
              let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        switch event["type"] as? String {
        case "item.started":
            // It runs a command to look inside the course's files.
            if let item = event["item"] as? [String: Any], item["type"] as? String == "command_execution" {
                return [.status(readingStatus)]
            }
            return []
        case "item.completed":
            if let item = event["item"] as? [String: Any], item["type"] as? String == "agent_message",
               let text = item["text"] as? String, !text.isEmpty {
                return [.replace(text.trimmingCharacters(in: .whitespacesAndNewlines))]
            }
        case "turn.failed":
            if let error = event["error"] as? [String: Any], let message = error["message"] as? String {
                return [.failed(friendly(message, tool: "Codex", signIn: "codex login"))]
            }
        case "error":
            if let message = event["message"] as? String {
                return [.failed(friendly(message, tool: "Codex", signIn: "codex login"))]
            }
        default:
            break
        }
        return []
    }

    /// One line of the Messages API event stream.
    static func parseSSELine(_ line: String) -> [AIEvent] {
        guard line.hasPrefix("data:") else { return [] }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = object["type"] as? String else { return [] }
        switch type {
        case "content_block_delta":
            if let delta = object["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
               let text = delta["text"] as? String, !text.isEmpty {
                return [.delta(text)]
            }
        case "message_delta":
            if let delta = object["delta"] as? [String: Any], delta["stop_reason"] as? String == "refusal" {
                return [.failed("It says it can’t answer this question. Try asking another way.")]
            }
        case "error":
            let message = (object["error"] as? [String: Any])?["message"] as? String
            return [.failed(message ?? "The AI service returned an error.")]
        default:
            break
        }
        return []
    }

    static func friendly(_ message: String, tool: String, signIn: String) -> String {
        let lower = message.lowercased()
        let needsSignIn = ["log in", "login", "logged in", "authenticat", "unauthorized", "401", "sign in", "invalid api key"]
            .contains { lower.contains($0) }
        if needsSignIn {
            return "\(tool) isn’t signed in. Click the StudyNotch icon in the menu bar › AI connection › \(tool) to sign in."
        }
        return String(message.prefix(300))
    }

    private static func lastLine(_ data: Data) -> String {
        let text = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last(where: { !$0.isEmpty }) ?? ""
    }

    // MARK: - Running the tools

    private func launch(path: String, arguments: [String], input: String,
                        onLine: @escaping (String) -> Void, onExit: @escaping (Int32, String) -> Void) {
        Paths.ensure()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = arguments
        // The course's project folder; without one, an empty folder of our own, so no other
        // project's instructions are picked up.
        p.currentDirectoryURL = runFolder.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Paths.runDir
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (path as NSString).deletingLastPathComponent + ":" + CLILocator.shared.searchPath
        env.merge(runEnvironment) { _, new in new }
        p.environment = env
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stderr

        var buffer = Data()
        var errors = Data()
        let queue = DispatchQueue(label: "studynotch.ai.read")
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            queue.async {
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<newline)
                    buffer.removeSubrange(buffer.startIndex...newline)
                    if let line = String(data: lineData, encoding: .utf8), !line.isEmpty { onLine(line) }
                }
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            queue.async { errors.append(chunk) }
        }
        p.terminationHandler = { finished in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            queue.async {
                if let rest = String(data: buffer, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !rest.isEmpty {
                    onLine(rest)
                }
                onExit(finished.terminationStatus, Self.lastLine(errors))
            }
        }
        do {
            try p.run()
        } catch {
            onExit(-1, "Couldn’t run it: \(error.localizedDescription)")
            return
        }
        process = p
        if let data = input.data(using: .utf8) {
            stdin.fileHandleForWriting.write(data)
        }
        try? stdin.fileHandleForWriting.close()
        DispatchQueue.global().asyncAfter(deadline: .now() + 180) { [weak p] in
            if let p, p.isRunning { p.terminate() }
        }
    }

    private func runClaude(_ r: AIRequest, emit: @escaping (AIEvent) -> Void) {
        guard let path = CLILocator.shared.path("claude") else {
            emit(.failed("Couldn’t find Claude Code."))
            return
        }
        var state = ClaudeStreamState()
        var finished = false
        launch(path: path, arguments: Self.claudeArguments(r), input: Self.claudeInput(r), onLine: { line in
            for event in Self.parseClaudeLine(line, state: &state) {
                if finished { return }
                if event == .done { finished = true }
                if case .failed = event { finished = true }
                emit(event)
            }
        }, onExit: { status, errorLine in
            guard !finished else { return }
            finished = true
            if !state.text.isEmpty {
                emit(.done)
            } else if errorLine.isEmpty {
                emit(.failed("Claude Code didn’t answer (exit code \(status))."))
            } else {
                emit(.failed(Self.friendly(errorLine, tool: "Claude", signIn: "claude")))
            }
        })
    }

    private func runCodex(_ r: AIRequest, emit: @escaping (AIEvent) -> Void) {
        guard let path = CLILocator.shared.path("codex") else {
            emit(.failed("Couldn’t find Codex."))
            return
        }
        var answered = false
        var finished = false
        launch(path: path, arguments: Self.codexArguments(r), input: Self.codexInput(r), onLine: { line in
            for event in Self.parseCodexLine(line) {
                if finished { return }
                if case .replace = event { answered = true }
                if case .failed = event { finished = true }
                emit(event)
            }
        }, onExit: { status, errorLine in
            guard !finished else { return }
            finished = true
            if answered {
                emit(.done)
            } else if errorLine.isEmpty {
                emit(.failed("Codex didn’t answer (exit code \(status))."))
            } else {
                emit(.failed(Self.friendly(errorLine, tool: "ChatGPT", signIn: "codex login")))
            }
        })
    }

    private func runGemini(_ r: AIRequest, emit: @escaping (AIEvent) -> Void) {
        guard let path = CLILocator.shared.path("agy") else {
            emit(.failed("Couldn’t find Gemini."))
            return
        }
        var answered = false
        var finished = false
        // Plain text comes back line by line.
        launch(path: path, arguments: Self.geminiArguments(r), input: "", onLine: { line in
            if finished { return }
            answered = true
            emit(.delta(line + "\n"))
        }, onExit: { status, errorLine in
            guard !finished else { return }
            finished = true
            if answered && status == 0 {
                emit(.done)
            } else if errorLine.isEmpty {
                emit(.failed("Gemini didn’t answer (exit code \(status))."))
            } else {
                emit(.failed(Self.friendly(errorLine, tool: "Gemini", signIn: "agy")))
            }
        })
    }

    // MARK: - API key

    static func apiBody(_ r: AIRequest) -> [String: Any] {
        let model = r.model.isEmpty ? defaultAPIModel : r.model
        var content: [[String: Any]] = []
        if let image = r.imagePath, let data = FileManager.default.contents(atPath: image) {
            content.append([
                "type": "image",
                "source": ["type": "base64", "media_type": "image/png", "data": data.base64EncodedString()],
            ])
        }
        content.append(["type": "text", "text": r.prompt])
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 64000,
            "stream": true,
            "system": r.system,
            "messages": [["role": "user", "content": content]],
        ]
        // If the model declines a request, let the service hand it to its default fallback model.
        if model == defaultAPIModel { body["fallbacks"] = "default" }
        return body
    }

    private func runAPI(_ r: AIRequest, emit: @escaping (AIEvent) -> Void) {
        guard let key = Keychain.load() else {
            emit(.failed("There’s no API key."))
            return
        }
        let body = Self.apiBody(r)
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
            emit(.failed("Couldn’t build the request."))
            return
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        if body["fallbacks"] != nil {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = payload

        task = Task {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status != 200 {
                    var collected = Data()
                    for try await byte in bytes {
                        collected.append(byte)
                        if collected.count > 20_000 { break }
                    }
                    let object = (try? JSONSerialization.jsonObject(with: collected)) as? [String: Any]
                    let message = (object?["error"] as? [String: Any])?["message"] as? String
                    if status == 401 {
                        emit(.failed("The API key isn’t valid. Enter it again from the menu."))
                    } else if status == 429 {
                        emit(.failed("Too many requests. Try again in a moment."))
                    } else {
                        emit(.failed(message.map { String($0.prefix(300)) } ?? "AI service error (\(status))"))
                    }
                    return
                }
                var gotText = false
                for try await line in bytes.lines {
                    if Task.isCancelled { return }
                    for event in Self.parseSSELine(line) {
                        if case .delta = event { gotText = true }
                        emit(event)
                        if case .failed = event { return }
                    }
                }
                emit(gotText ? .done : .failed("The answer came back empty. Try again."))
            } catch {
                if Task.isCancelled { return }
                emit(.failed("Can’t connect. Check your internet connection and try again."))
            }
        }
    }
}
