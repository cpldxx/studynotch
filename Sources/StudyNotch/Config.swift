import Foundation

// Everything the app stores lives in one folder in the user's home. No server.
enum Paths {
    static var root: URL = {
        if let custom = ProcessInfo.processInfo.environment["STUDYNOTCH_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("StudyNotch", isDirectory: true)
    }()
    static var config: URL { root.appendingPathComponent("config.json") }
    static var courses: URL { root.appendingPathComponent("Courses", isDirectory: true) }
    static var sessions: URL { root.appendingPathComponent("sessions.jsonl") }
    static var captures: URL { root.appendingPathComponent("Captures", isDirectory: true) }
    static var runDir: URL { root.appendingPathComponent(".run", isDirectory: true) }
    /// Sign-ins kept only for StudyNotch ("use another account"), one folder per tool.
    static var accounts: URL { root.appendingPathComponent(".accounts", isDirectory: true) }
    /// The text of PDFs in linked folders, so nothing is ever written into the student's own folders.
    static var textCache: URL { root.appendingPathComponent(".cache/text", isDirectory: true) }
    static var debugLog: URL { root.appendingPathComponent("debug.log") }

    static func ensure() {
        for dir in [root, courses, captures, runDir] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}

private let logQueue = DispatchQueue(label: "studynotch.log")
private let logStamp: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MM-dd HH:mm:ss"
    return f
}()

/// Appends one line to ~/StudyNotch/debug.log. Never logs selected text or answers.
func dlog(_ message: String) {
    let line = "\(logStamp.string(from: Date())) \(message)\n"
    logQueue.async {
        let url = Paths.debugLog
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 400_000 {
            try? FileManager.default.removeItem(at: url)
        }
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}

extension KeyedDecodingContainer {
    /// Missing or mistyped keys fall back to a default, so a hand-edited config never breaks the app.
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

struct Preset: Codable, Identifiable, Equatable {
    var id: String
    var course: String
    var task: String
    var minutes: Int
    var allow: [String]
    /// Folders on this Mac linked to the course: their PDFs are read where they are, never copied.
    var folders: [String]

    init(id: String, course: String, task: String, minutes: Int, allow: [String] = [], folders: [String] = []) {
        self.id = id
        self.course = course
        self.task = task
        self.minutes = minutes
        self.allow = allow
        self.folders = folders
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        course = AppConfig.renamed(c.value(.course, AppConfig.generalCourse))
        task = c.value(.task, "Focus")
        minutes = max(1, c.value(.minutes, 25))
        allow = c.value(.allow, [])
        folders = c.value(.folders, [])
        id = c.value(.id, "\(course)-\(task)-\(minutes)")
    }
}

struct AISettings: Codable, Equatable {
    /// The AI the student connected: claude-cli | codex-cli | gemini-cli | api-key, or empty for
    /// none. An old "auto" means none too: nothing answers until the student connects one.
    var provider: String
    /// Empty = the provider's default (API key: claude-opus-5-5).
    var model: String
    /// Whose sign-in the connected AI uses: "mac" (the one this Mac already has, shared with the
    /// Claude or ChatGPT app) or "own" (one kept only for StudyNotch).
    var account: String
    // No language setting: answers follow what the student types (`Prompts.answerLanguage`).
    // An old config's `language` key is simply ignored.

    init(provider: String = "", model: String = "", account: String = "mac") {
        self.provider = provider
        self.model = model
        self.account = account
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = c.value(.provider, "")
        model = c.value(.model, "")
        account = c.value(.account, "mac")
    }
}

struct AppConfig: Codable, Equatable {
    static let generalCourse = "General"

    /// Course names from before the app was in English. Only the timer-only course had a Korean name.
    static func renamed(_ course: String) -> String {
        course == "일반" ? generalCourse : course
    }

    var presets: [Preset]
    /// Length of a new session, whichever course is picked.
    var sessionMinutes: Int
    /// Always fine, in every session. A dot means a website, otherwise an app name.
    var allowAlways: [String]
    /// Counted as off-task while a session runs.
    var distractions: [String]
    var nudgeAfterSeconds: Int
    var breakMinutes: Int
    /// Offer "Ask" on selections and screenshots even when no session is running.
    var offerOutsideSession: Bool
    /// Apps where a drag is read through a quick copy when the app does not expose its selection.
    var copyFallbackApps: [String]
    /// notch (the screen with a notch, else the menu bar screen) | main (the menu bar screen)
    /// | mouse (the screen under the pointer). Same choices and default as Coucou.
    var display: String
    var ai: AISettings
    /// How many times "It’s for study" was chosen per target; three makes it permanent for that preset.
    var studyVotes: [String: Int]
    /// Quiet system sounds when the island peeks, opens and when a pill is pressed.
    var sounds: Bool

    static let `default` = AppConfig(
        // Only General: the student adds their own courses. No sample courses.
        presets: [
            Preset(id: generalCourse, course: generalCourse, task: "", minutes: 50),
        ],
        sessionMinutes: 50,
        allowAlways: ["learn.uwaterloo.ca"],
        distractions: [
            "youtube.com", "instagram.com", "tiktok.com", "x.com", "twitter.com", "facebook.com",
            "reddit.com", "netflix.com", "twitch.tv", "Discord", "KakaoTalk", "카카오톡",
        ],
        nudgeAfterSeconds: 60,
        breakMinutes: 5,
        offerOutsideSession: false,
        copyFallbackApps: ["com.apple.Preview", "net.sourceforge.skim-app.skim"],
        display: "notch",
        ai: AISettings(),
        studyVotes: [:],
        sounds: true
    )

    init(presets: [Preset], sessionMinutes: Int, allowAlways: [String], distractions: [String], nudgeAfterSeconds: Int,
         breakMinutes: Int, offerOutsideSession: Bool, copyFallbackApps: [String], display: String,
         ai: AISettings, studyVotes: [String: Int], sounds: Bool) {
        self.presets = presets
        self.sessionMinutes = sessionMinutes
        self.allowAlways = allowAlways
        self.distractions = distractions
        self.nudgeAfterSeconds = nudgeAfterSeconds
        self.breakMinutes = breakMinutes
        self.offerOutsideSession = offerOutsideSession
        self.copyFallbackApps = copyFallbackApps
        self.display = display
        self.ai = ai
        self.studyVotes = studyVotes
        self.sounds = sounds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig.default
        let loaded: [Preset] = c.value(.presets, d.presets)
        presets = loaded.isEmpty ? d.presets : loaded
        sessionMinutes = max(1, c.value(.sessionMinutes, d.sessionMinutes))
        allowAlways = c.value(.allowAlways, d.allowAlways)
        distractions = c.value(.distractions, d.distractions)
        nudgeAfterSeconds = max(5, c.value(.nudgeAfterSeconds, d.nudgeAfterSeconds))
        breakMinutes = max(1, c.value(.breakMinutes, d.breakMinutes))
        offerOutsideSession = c.value(.offerOutsideSession, d.offerOutsideSession)
        copyFallbackApps = c.value(.copyFallbackApps, d.copyFallbackApps)
        display = c.value(.display, d.display)
        ai = c.value(.ai, d.ai)
        studyVotes = c.value(.studyVotes, d.studyVotes)
        sounds = c.value(.sounds, d.sounds)
    }
}

extension AppConfig {
    /// The courses (projects) shown in the notch, in the order they were added.
    var courses: [String] {
        var seen = Set<String>()
        return presets.map(\.course).filter { seen.insert($0).inserted }
    }

    /// The folders linked to a course, in the order they were linked.
    func folders(for course: String) -> [String] {
        var seen = Set<String>()
        return presets.filter { $0.course == course }.flatMap(\.folders).filter { seen.insert($0).inserted }
    }

    /// Links a folder to a course. False when the course doesn't exist or already has it.
    @discardableResult
    mutating func link(_ folder: String, to course: String) -> Bool {
        guard let index = presets.firstIndex(where: { $0.course == course }), !folders(for: course).contains(folder) else { return false }
        presets[index].folders.append(folder)
        return true
    }

    mutating func unlink(_ folder: String, from course: String) {
        for index in presets.indices where presets[index].course == course {
            presets[index].folders.removeAll { $0 == folder }
        }
    }

    /// Pure: whether a course can be called this. Empty, taken and the built-in name are refused.
    func canName(_ name: String, renaming old: String? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != old else { return false }
        return !courses.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame && $0 != old }
    }

    /// Renames a course everywhere in the settings.
    mutating func rename(_ old: String, to new: String) {
        for index in presets.indices where presets[index].course == old {
            if presets[index].id == old { presets[index].id = new }
            presets[index].course = new
        }
    }
}

enum ConfigStore {
    static func load() -> AppConfig {
        Paths.ensure()
        guard let data = try? Data(contentsOf: Paths.config) else {
            save(.default)
            return .default
        }
        guard let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            // A broken file is left alone so the user's edits are not lost.
            dlog("config.json could not be read; using defaults for this run")
            return .default
        }
        return config
    }

    static func save(_ config: AppConfig) {
        Paths.ensure()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: Paths.config, options: .atomic)
    }
}
