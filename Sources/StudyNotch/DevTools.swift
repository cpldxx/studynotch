import AppKit
import SwiftUI

/// Checks that run without the app's window: `StudyNotch --selftest` and `StudyNotch --render <folder>`.
enum DevTools {
    private static var failures = 0

    private static func check(_ name: String, _ ok: Bool) {
        if !ok { failures += 1 }
        print("\(ok ? "PASS" : "FAIL")  \(name)")
    }

    private static func useTemporaryHome() -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("studynotch-test-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.removeItem(at: home)
        Paths.root = home
        Paths.ensure()
        return home
    }

    private static func makePDF(at url: URL, pages: [String]) {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
        for text in pages {
            context.beginPDFPage(nil)
            let graphics = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            (text as NSString).draw(in: CGRect(x: 72, y: 72, width: 468, height: 648),
                                    withAttributes: [.font: NSFont.systemFont(ofSize: 14)])
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
    }

    private static func cal(_ y: Int, _ m: Int, _ d: Int, _ h: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    static func selfTest() -> Bool {
        let home = useTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        // Config
        let saved = AppConfig.default
        ConfigStore.save(saved)
        check("config round trip", ConfigStore.load() == saved)
        let partial = #"{"presets":[{"course":"PHYS 121","minutes":40}],"nudgeAfterSeconds":30}"#
        let decoded = try? JSONDecoder().decode(AppConfig.self, from: Data(partial.utf8))
        check("partial config fills defaults", decoded?.presets.first?.course == "PHYS 121"
              && decoded?.presets.first?.task == "Focus" && decoded?.nudgeAfterSeconds == 30
              && decoded?.breakMinutes == 5 && decoded?.distractions.isEmpty == false)

        // Off-task rules
        let config = AppConfig.default
        func front(_ app: String, _ url: String? = nil) -> FrontInfo {
            FrontInfo(appName: app, bundleID: "", pid: 0, title: "", url: url)
        }
        let youtube = front("Google Chrome", "https://www.youtube.com/watch?v=abc")
        check("youtube is off-task", FocusWatcher.classify(youtube, presetAllow: [], config: config, tempAllow: []).verdict == .distract)
        check("target is the site", FocusWatcher.target(youtube) == "youtube.com")
        check("subdomain matches", FocusWatcher.classify(front("Safari", "https://m.youtube.com/"), presetAllow: [], config: config, tempAllow: []).verdict == .distract)
        check("lookalike host does not match", FocusWatcher.classify(front("Safari", "https://notyoutube.com/"), presetAllow: [], config: config, tempAllow: []).verdict == .neutral)
        check("preset allow wins", FocusWatcher.classify(youtube, presetAllow: ["youtube.com"], config: config, tempAllow: []).verdict == .allowed)
        check("this-session allow wins", FocusWatcher.classify(youtube, presetAllow: [], config: config, tempAllow: ["youtube.com"]).verdict == .allowed)
        check("always-allowed site", FocusWatcher.classify(front("Safari", "https://learn.uwaterloo.ca/d2l/home"), presetAllow: [], config: config, tempAllow: []).verdict == .allowed)
        check("app by name", FocusWatcher.classify(front("Discord"), presetAllow: [], config: config, tempAllow: []).verdict == .distract)
        check("unknown app is neutral", FocusWatcher.classify(front("Preview"), presetAllow: [], config: config, tempAllow: []).verdict == .neutral)
        check("browser without address is neutral", FocusWatcher.classify(front("Google Chrome"), presetAllow: [], config: config, tempAllow: []).verdict == .neutral)

        // Course materials
        let course = "TEST 101"
        let materials = CourseStore.shared.dir(course).appendingPathComponent("materials")
        let pdf = materials.appendingPathComponent("Lecture 9.pdf")
        makePDF(at: pdf, pages: [
            "Chapter 1. Limits of functions of two variables are defined with open neighbourhoods.",
            "Theorem 2. If f is differentiable at (a,b) then f is continuous at (a,b). The converse is false in general.",
            "Chapter 3. The chain rule for functions of several variables uses the Jacobian matrix.",
        ])
        check("pdf written", FileManager.default.fileExists(atPath: pdf.path))
        let hit = CourseStore.shared.locate("If f is differentiable at (a,b)\nthen f is  continuous at (a,b).", course: course, hint: nil)
        check("locate finds page 2", hit?.page == 2 && hit?.file == "Lecture 9.pdf")
        check("located context holds the sentence", hit?.context.contains("converse") == true)
        check("locate misses unrelated text", CourseStore.shared.locate("Eigenvalues of a symmetric matrix are real numbers.", course: course, hint: nil) == nil)
        check("text cache written", FileManager.default.fileExists(atPath: materials.appendingPathComponent("_text/Lecture 9.pdf.json").path))
        check("normalize ignores spacing", CourseStore.normalize("Dif-\nferen tiable!") == "differentiable")
        CourseStore.shared.appendCard(course: course, front: "differentiable", back: "implies continuous")
        let cards = try? String(contentsOf: CourseStore.shared.dir(course).appendingPathComponent("cards.md"), encoding: .utf8)
        check("card saved", cards?.contains("differentiable") == true)

        // Session log
        SessionLog.append(SessionRecord(course: course, task: "Reading", start: Date(), end: Date(), plannedMinutes: 50,
                                        focusSeconds: 2400, distractSeconds: 120, questions: ["I don’t get this: Theorem 2"]))
        check("last stuck comes back", SessionLog.lastStuck(course: course) == ["I don’t get this: Theorem 2"])
        check("other course has none", SessionLog.lastStuck(course: "NONE").isEmpty)
        // A line that can't be read (a half-written one, or one from another version) is nobody's to throw away.
        let logBefore = try? Data(contentsOf: Paths.sessions)
        let damaged = #"{"course":"TEST 101","task":"Reading","start":"2026-11-0"#
        try? ((logBefore ?? Data()) + Data((damaged + "\n").utf8)).write(to: Paths.sessions)
        SessionLog.append(SessionRecord(course: "OLD 100", task: "", start: Date(), end: Date(), plannedMinutes: 50,
                                        focusSeconds: 60, distractSeconds: 0, questions: ["Why?"]))
        SessionLog.rename("OLD 100", to: "NEW 100")
        let renamedLog = (try? String(contentsOf: Paths.sessions, encoding: .utf8)) ?? ""
        check("renaming a course keeps a log line it can't read",
              SessionLog.lastStuck(course: "NEW 100") == ["Why?"] && SessionLog.lastStuck(course: "OLD 100").isEmpty
              && renamedLog.components(separatedBy: "\n").contains(damaged)
              && SessionLog.lastStuck(course: course) == ["I don’t get this: Theorem 2"])
        // A log that stops in the middle of a line (the Mac went down while it was written).
        try? ((logBefore ?? Data()) + Data(damaged.utf8)).write(to: Paths.sessions)
        SessionLog.append(SessionRecord(course: "OLD 100", task: "", start: Date(), end: Date(), plannedMinutes: 50,
                                        focusSeconds: 60, distractSeconds: 0, questions: ["After the cut"]))
        check("a session saved after a half-written line starts its own line",
              SessionLog.lastStuck(course: "OLD 100") == ["After the cut"])
        if let logBefore { try? logBefore.write(to: Paths.sessions) }

        // Command lines
        let textRequest = AIRequest(system: "SYS", prompt: "PROMPT", imagePath: nil, model: "")
        let imageRequest = AIRequest(system: "SYS", prompt: "PROMPT", imagePath: "/tmp/caps/a.png", model: "m1")
        let plain = AIEngine.claudeArguments(textRequest)
        check("claude: no tools without an image", zip(plain, plain.dropFirst()).contains { $0 == "--tools" && $1 == "" })
        check("claude: streams", plain.contains("stream-json") && plain.contains("--include-partial-messages"))
        check("claude: isolated from user settings", plain.contains("--strict-mcp-config") && plain.contains("--no-session-persistence"))
        let withImage = AIEngine.claudeArguments(imageRequest)
        check("claude: a capture may be read, and only its folder", zip(withImage, withImage.dropFirst()).contains { $0 == "--add-dir" && $1 == "/tmp/caps" }
              && zip(withImage, withImage.dropFirst()).contains { $0 == "--tools" && $1 == "Read" } && !withImage.contains("--allowedTools"))
        let projectRequest = AIRequest(system: "SYS", prompt: "PROMPT", imagePath: nil, model: "", folders: ["/c/A/text", "/c/A/materials"])
        let asProject = AIEngine.claudeArguments(projectRequest)
        check("claude: a course is its project, read-only: it works in the text folder and may open the PDFs",
              zip(asProject, asProject.dropFirst()).contains { $0 == "--tools" && $1 == "Read,Glob,Grep" }
              && zip(asProject, asProject.dropFirst()).contains { $0 == "--add-dir" && $1 == "/c/A/materials" }
              && !asProject.contains("/c/A/text") && !asProject.contains("--allowedTools") && !asProject.contains("Bash")
              && asProject.contains("--no-session-persistence"))
        // Kept in the Claude app: a named session in the course's folder; a follow-up continues it.
        var keptRequest = projectRequest
        keptRequest.folders = ["/c/A/text", "/c/A/materials", "/cache/text/x"]
        keptRequest.session = ClaudeSession(id: "s-1", folder: "/c/A", name: "Explain: Theorem 2", resume: false)
        let kept = AIEngine.claudeArguments(keptRequest)
        let pairs = Array(zip(kept, kept.dropFirst()))
        check("claude app: a kept question is a named session, saved, working in the course's folder",
              pairs.contains { $0 == "--session-id" && $1 == "s-1" } && pairs.contains { $0 == "--name" && $1 == "Explain: Theorem 2" }
              && !kept.contains("--no-session-persistence") && !kept.contains("--resume")
              && !kept.contains("/c/A/text") && !kept.contains("/c/A/materials")
              && pairs.contains { $0 == "--add-dir" && $1 == "/cache/text/x" }
              && pairs.contains { $0 == "--tools" && $1 == "Read,Glob,Grep" })
        keptRequest.session?.resume = true
        let followUp = AIEngine.claudeArguments(keptRequest)
        check("claude app: a follow-up continues the same session",
              zip(followUp, followUp.dropFirst()).contains { $0 == "--resume" && $1 == "s-1" }
              && !followUp.contains("--session-id") && !followUp.contains("--name") && !followUp.contains("--no-session-persistence"))
        check("claude app: inside a folder means the folder or below it, not a name that starts the same",
              AIEngine.isInside("/c/A/text", "/c/A") && AIEngine.isInside("/c/A", "/c/A/") && !AIEngine.isInside("/c/AB/text", "/c/A"))
        check("claude app: a session's name is the question and the picked text, on one line, short",
              ClaudeSession.name(question: "Explain", quote: "If f is\ndifferentiable") == "Explain: If f is differentiable"
              && ClaudeSession.name(question: "", quote: nil) == "Question"
              && ClaudeSession.name(question: "Explain", quote: String(repeating: "word ", count: 40)).count <= 70
              && ClaudeSession.name(question: "Explain", quote: String(repeating: "word ", count: 40)).hasSuffix("…"))
        check("claude app: the app's own link that adds a session to its list",
              ClaudeApp.link("4eb2e1f1-02e6")?.absoluteString == "claude://resume?session=4eb2e1f1-02e6")
        let codexProject = AIEngine.codexArguments(projectRequest)
        check("chatgpt: works in the course's project folder, still read-only",
              zip(codexProject, codexProject.dropFirst()).contains { $0 == "-C" && $1 == "/c/A/text" }
              && zip(codexProject, codexProject.dropFirst()).contains { $0 == "--sandbox" && $1 == "read-only" } && codexProject.last == "-"
              && !AIEngine.codexArguments(textRequest).contains("-C"))
        let geminiProject = AIEngine.geminiArguments(projectRequest)
        check("gemini: the course's folders are added to its workspace",
              zip(geminiProject, geminiProject.dropFirst()).contains { $0 == "--add-dir" && $1 == "/c/A/text" }
              && zip(geminiProject, geminiProject.dropFirst()).contains { $0 == "--add-dir" && $1 == "/c/A/materials" })
        var toolState = ClaudeStreamState()
        toolState.text = "Let me look."
        let opening = AIEngine.parseClaudeLine(#"{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","name":"Grep","input":{}}}}"#, state: &toolState)
        check("claude: opening a file clears what it said first and says so",
              opening == [.replace(""), .status(AIEngine.readingStatus)] && toolState.text.isEmpty
              && AIEngine.parseCodexLine(#"{"type":"item.started","item":{"type":"command_execution","command":"rg secret"}}"#) == [.status(AIEngine.readingStatus)])
        check("claude: model passed", zip(withImage, withImage.dropFirst()).contains { $0 == "--model" && $1 == "m1" })
        check("claude: image path in the prompt", AIEngine.claudeInput(imageRequest).contains("/tmp/caps/a.png"))
        let codex = AIEngine.codexArguments(imageRequest)
        check("codex: read-only", zip(codex, codex.dropFirst()).contains { $0 == "--sandbox" && $1 == "read-only" } && codex.last == "-")
        let gemini = AIEngine.geminiArguments(imageRequest)
        check("gemini (agy): print mode, instructions first, the capture's folder added",
              gemini.first == "--print" && gemini[1].hasPrefix("<instructions>") && gemini[1].contains("@/tmp/caps/a.png")
              && zip(gemini, gemini.dropFirst()).contains { $0 == "--model" && $1 == "m1" }
              && zip(gemini, gemini.dropFirst()).contains { $0 == "--add-dir" && $1 == "/tmp/caps" }
              && gemini.contains("--disable-slash-commands"))
        check("gemini (agy): signed in when it can list its models",
              !AIEngine.geminiSignedIn(models: "Fetching available models...\nError: Please sign in to view available models. Launch the CLI without arguments to sign in.\n")
              && AIEngine.geminiSignedIn(models: "Fetching available models...\ngemini-3-pro\ngemini-3-flash\n")
              && !AIEngine.geminiSignedIn(models: "Fetching available models...\n") && !AIEngine.geminiSignedIn(models: ""))
        check("gemini (agy): installed with Homebrew, then its sign-in",
              AIKind.geminiCLI.installLines(brew: "/opt/homebrew/bin/brew")
                == ["'/opt/homebrew/bin/brew' install --cask antigravity-cli || exit 1", "'/opt/homebrew/bin/agy'"]
              && AIKind.geminiCLI.installLines(brew: nil) == nil && AIKind.claudeCLI.installLines(brew: "/b/brew") == nil)
        check("ai: a model name only goes to the AI it names",
              AIEngine.model("claude-opus-5-5", for: .claudeCLI) == "claude-opus-5-5"
              && AIEngine.model("claude-opus-5-5", for: .geminiCLI) == "" && AIEngine.model("opus", for: .codexCLI) == ""
              && AIEngine.model("gpt-5", for: .codexCLI) == "gpt-5" && AIEngine.model("o4-mini", for: .codexCLI) == "o4-mini"
              && AIEngine.model("gemini-3-pro", for: .geminiCLI) == "gemini-3-pro" && AIEngine.model("", for: .apiKey) == "")
        let script = AppModel.terminalScript(hint: "It's here", folder: "/tmp/run dir", lines: ["'/x/agy'"])
        check("sign-in window: runs in our folder, says what happens first",
              script.hasPrefix("#!/bin/zsh\ncd '/tmp/run dir' || exit 1\necho 'It'\\''s here'") && script.hasSuffix("'/x/agy'\n"))
        check("first step: signed in on this Mac is not connected",
              AppModel.choiceState(installed: false, signedIn: nil, connected: false) == .get
              && AppModel.choiceState(installed: true, signedIn: true, connected: false) == .ready
              && AppModel.choiceState(installed: true, signedIn: true, connected: true) == .connected
              && AppModel.choiceState(installed: true, signedIn: false, connected: true) == .signIn
              && AppModel.choiceState(installed: true, signedIn: nil, connected: false) == .checking)
        check("first step: the tile words", AITile.words(.get, kind: .geminiCLI) == "Install"
              && AITile.words(.get, kind: .claudeCLI) == "Get the Claude app"
              && AITile.words(.ready, kind: .codexCLI) == "Signed in on this Mac"
              && AITile.words(.connected, kind: .codexCLI) == "Connected"
              && AIKind.choices == [.claudeCLI, .codexCLI, .geminiCLI])
        let everyoneReady: (AIKind) -> Bool = { _ in true }
        let allSignedIn: (AIKind) -> Bool? = { _ in true }
        check("ai: nothing answers until one is connected, and never another one",
              AIEngine.resolve("", installed: everyoneReady, signedIn: allSignedIn) == nil
              && AIEngine.resolve("auto", installed: everyoneReady, signedIn: allSignedIn) == nil
              && AIEngine.resolve("codex-cli", installed: everyoneReady, signedIn: allSignedIn) == .codexCLI
              && AIEngine.resolve("gemini-cli", installed: everyoneReady, signedIn: { $0 == .geminiCLI ? false : true }) == nil
              && AIEngine.resolve("claude-cli", installed: { $0 != .claudeCLI }, signedIn: allSignedIn) == nil
              && AISettings().provider == "")
        check("connect: asks with the account it will use",
              SetupPage.connectQuestion(.claudeCLI) == "Connect Claude with this account?"
              && SetupPage.connectAccount(.claudeCLI, account: "a@b.c · Max") == "a@b.c · Max"
              && SetupPage.connectAccount(.codexCLI, account: nil) == "The one signed in on this Mac"
              && AIEngine.claudeAccount(#"{"loggedIn": true, "email": "a@b.c", "subscriptionType": "max"}"#) == "a@b.c · Max"
              && AIEngine.claudeAccount(#"{"loggedIn": true, "email": "a@b.c"}"#) == "a@b.c"
              && AIEngine.claudeAccount(#"{"loggedIn": false}"#) == nil
              && AITile.accountLine(.claudeCLI, account: "a@b.c · Max", state: .ready) == "a@b.c"
              && AITile.accountLine(.claudeCLI, account: "a@b.c", state: .signIn) == "Your Claude account")
        // A made-up ID token: header.payload.signature, the payload holding an email and a plan.
        let claims = #"{"email":"s@school.edu","https://api.openai.com/auth":{"chatgpt_plan_type":"plus"}}"#
        let middle = Data(claims.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let authFile = Data(#"{"tokens":{"id_token":"aaa.\#(middle).bbb"}}"#.utf8)
        check("ChatGPT account: the email and plan in its sign-in file",
              AIEngine.codexAccount(authJSON: authFile) == "s@school.edu · Plus"
              && AIEngine.codexAccount(authJSON: Data("{}".utf8)) == nil)
        check("another account: StudyNotch's own sign-in, never the Mac's",
              AIKind.claudeCLI.accountEnvironment(.own, folder: "/a") == ["CLAUDE_CONFIG_DIR": "/a/claude"]
              && AIKind.codexCLI.accountEnvironment(.own, folder: "/a") == ["CODEX_HOME": "/a/codex"]
              && AIKind.claudeCLI.accountEnvironment(.mac, folder: "/a").isEmpty
              && AIKind.geminiCLI.accountEnvironment(.own, folder: "/a").isEmpty && !AIKind.geminiCLI.hasOwnAccount
              && AppModel.signInLines(path: "/x/claude", arguments: ["auth", "login"], environment: ["CLAUDE_CONFIG_DIR": "/a/claude"])
                == ["export CLAUDE_CONFIG_DIR='/a/claude'", "'/x/claude' 'auth' 'login'"]
              && AIKind.claudeCLI.signOutArguments() == ["auth", "logout"] && AIKind.codexCLI.signOutArguments() == ["logout"]
              && AISettings().account == "mac")
        check("connection test: says who answered, how fast and what",
              AppModel.testLine(kind: .claudeCLI, seconds: 2.34, reply: " Connected to\nStudyNotch ")
                == "Real answer from Claude in 2.3 s: “Connected to StudyNotch”"
              && SetupPage.aiLine(.running).hasPrefix("Sending one real question")
              && SetupPage.aiLine(.failed("Claude didn’t answer: x")) == "Claude didn’t answer: x")
        check("sign-in: Claude's status JSON", AIEngine.claudeSignedIn(#"{"loggedIn": true, "authMethod": "claude.ai"}"#)
              && !AIEngine.claudeSignedIn(#"{"loggedIn": false}"#) && !AIEngine.claudeSignedIn("error"))
        check("sign-in: ChatGPT's status line", AIEngine.codexSignedIn(status: 0, text: "Logged in using ChatGPT")
              && !AIEngine.codexSignedIn(status: 1, text: "Not logged in") && !AIEngine.codexSignedIn(status: 0, text: "Not logged in"))
        check("ai: the four choices, by name", AIKind.allCases.map(\.label) == ["Claude", "ChatGPT", "Gemini", "API key"]
              && AIKind.geminiCLI.tool == "agy" && AIKind.codexCLI.signInArguments() == ["login"])
        check("ai: a sign-in error points to the menu", AIEngine.friendly("Invalid API key · Please run /login", tool: "Claude", signIn: "claude")
              .contains("AI connection"))
        let body = AIEngine.apiBody(textRequest)
        check("api: default model and streaming", body["model"] as? String == "claude-opus-5-5" && body["stream"] as? Bool == true)

        // Output parsing
        var state = ClaudeStreamState()
        var events: [AIEvent] = []
        for line in [
            #"{"type":"system","subtype":"init"}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"미분"}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"..."}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"가능"}}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"미분가능"}]}}"#,
            #"{"type":"result","subtype":"success","is_error":false,"result":"미분가능하면 연속이다."}"#,
        ] {
            events += AIEngine.parseClaudeLine(line, state: &state)
        }
        check("claude stream: deltas then final text", events == [.delta("미분"), .delta("가능"), .replace("미분가능하면 연속이다."), .done])
        var plainState = ClaudeStreamState()
        let whole = AIEngine.parseClaudeLine(#"{"type":"assistant","message":{"content":[{"type":"text","text":"전체 답"}]}}"#, state: &plainState)
        check("claude stream: whole message when no deltas", whole == [.replace("전체 답")])
        var errorState = ClaudeStreamState()
        let failed = AIEngine.parseClaudeLine(#"{"type":"result","is_error":true,"result":"Invalid API key · Please run /login"}"#, state: &errorState)
        if case .failed(let message)? = failed.first {
            check("claude stream: sign-in message", message.contains("sign in"))
        } else {
            check("claude stream: sign-in message", false)
        }
        check("codex: agent message", AIEngine.parseCodexLine(#"{"type":"item.completed","item":{"type":"agent_message","text":" 답 "}}"#) == [.replace("답")])
        // The sign-in message names the tile and menu item the student clicks: ChatGPT, not Codex.
        let codexSignIn = AIEngine.parseCodexLine(#"{"type":"turn.failed","error":{"message":"401 Unauthorized"}}"#)
            + AIEngine.parseCodexLine(#"{"type":"error","message":"Not logged in"}"#)
        check("codex: the sign-in message names ChatGPT", codexSignIn.count == 2 && codexSignIn.allSatisfy {
            guard case .failed(let message) = $0 else { return false }
            return message.hasPrefix("ChatGPT isn’t signed in") && message.hasSuffix("› ChatGPT to sign in.") && !message.contains("Codex")
        })
        check("api stream: text delta", AIEngine.parseSSELine(#"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"안녕"}}"#) == [.delta("안녕")])
        check("api stream: other lines ignored", AIEngine.parseSSELine("event: message_start").isEmpty
              && AIEngine.parseSSELine(#"data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"x"}}"#).isEmpty)
        if case .failed? = AIEngine.parseSSELine(#"data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}"#).first {
            check("api stream: refusal reported", true)
        } else {
            check("api stream: refusal reported", false)
        }

        // Running a tool the way a question does: shell scripts stand in for the AI tools.
        func readAll(_ script: String, input: String = "", grace: Double = 2) -> (lines: [String], seconds: Double) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", script]
            let stdin = Pipe(), out = Pipe(), err = Pipe()
            p.standardInput = stdin
            p.standardOutput = out
            p.standardError = err
            var lines: [String] = []
            let ended = DispatchSemaphore(value: 0)
            let start = Date()
            AIEngine.readOutput(of: p, stdout: out, stderr: err, grace: grace,
                                onLine: { lines.append($0) }, onExit: { _, _ in ended.signal() })
            guard (try? p.run()) != nil else { return ([], 99) }
            DispatchQueue.global().async { AIEngine.send(input, to: stdin.fileHandleForWriting) }
            guard ended.wait(timeout: .now() + 10) == .success else { return ([], 99) }
            return (lines, Date().timeIntervalSince(start))
        }
        let late = readAll("(sleep 0.3; echo late) & echo early")
        check("ai output: lines written after the tool exits still arrive", late.lines == ["early", "late"] && late.seconds < 1.5)
        let held = readAll("(sleep 2) & echo early", grace: 0.3)
        check("ai output: a helper holding the output open doesn't keep it waiting", held.lines == ["early"] && held.seconds < 1.5)
        // A question longer than a pipe holds (about 200 KB).
        let long = (0..<20_000).map { "line \($0)" }.joined(separator: "\n") + "\n"
        let echoed = readAll("cat", input: long)
        check("ai input: a long question reaches the tool whole", echoed.lines.count == 20_000 && echoed.lines.last == "line 19999")
        check("ai input: a tool that quits without reading a long question doesn't end StudyNotch",
              readAll("exit 1", input: long).seconds < 5)

        // Courses instead of presets
        check("a new install has no sample courses, only General", AppConfig.default.courses == [AppConfig.generalCourse])
        var listed = AppConfig.default
        listed.presets = ["MATH 237", "ACTSCI 221", AppConfig.generalCourse, "MATH 237"].map { Preset(id: $0 + "x", course: $0, task: "", minutes: 50) }
        check("courses are unique and ordered", listed.courses == ["MATH 237", "ACTSCI 221", "General"])
        // Folders linked to a course, and what the Add tab does with picked files
        var linking = AppConfig.default
        linking.presets.append(Preset(id: "Algebra", course: "Algebra", task: "", minutes: 50))
        check("link: a folder is linked once, to a course that exists",
              linking.link("/x/Algebra", to: "Algebra") && !linking.link("/x/Algebra", to: "Algebra")
              && !linking.link("/x/y", to: "Nope") && linking.folders(for: "Algebra") == ["/x/Algebra"])
        check("link: an older settings file has no folders, and they survive saving",
              (try? JSONDecoder().decode(Preset.self, from: Data(#"{"course":"A","task":"","minutes":5}"#.utf8)))?.folders == []
              && ((try? JSONEncoder().encode(linking)).flatMap { try? JSONDecoder().decode(AppConfig.self, from: $0) })?.folders(for: "Algebra") == ["/x/Algebra"])
        check("course names: empty, taken and the built-in one are refused",
              !linking.canName("  ") && !linking.canName("algebra") && !linking.canName("General") && linking.canName("Calculus")
              && linking.canName("ALGEBRA", renaming: "Algebra") && !linking.canName("Algebra", renaming: "Algebra"))
        var slashed = linking
        slashed.presets.append(Preset(id: "A/B", course: "A/B", task: "", minutes: 50))
        check("course names: a name whose folder is another course's, or not a folder of its own, is refused",
              !slashed.canName("A-B") && !slashed.canName("a:b") && slashed.canName("A/C") && slashed.canName("A-B", renaming: "A/B")
              && !linking.canName("..") && !linking.canName(".") && !linking.canName("/")
              && CourseStore.shared.path("..").standardizedFileURL.path.hasPrefix(Paths.courses.standardizedFileURL.path + "/")
              && CourseStore.shared.path(".").standardizedFileURL.path.hasPrefix(Paths.courses.standardizedFileURL.path + "/"))
        linking.rename("Algebra", to: "Algebra II")
        check("rename: the course, its id and its folders move together",
              linking.courses == ["General", "Algebra II"] && linking.folders(for: "Algebra II") == ["/x/Algebra"]
              && linking.presets.last?.id == "Algebra II")
        linking.unlink("/x/Algebra", from: "Algebra II")
        check("unlink: the folder leaves the course", linking.folders(for: "Algebra II").isEmpty)

        let shelf = home.appendingPathComponent("Shelf/Linear Algebra", isDirectory: true)
        try? FileManager.default.createDirectory(at: shelf.appendingPathComponent("week 1/deep/deeper/deepest"), withIntermediateDirectories: true)
        for name in ["notes.pdf", "week 1/slides.PDF", "week 1/deep/deeper/far.pdf", "week 1/deep/deeper/deepest/too far.pdf", "readme.txt", ".hidden.pdf"] {
            FileManager.default.createFile(atPath: shelf.appendingPathComponent(name).path, contents: Data("x".utf8))
        }
        let loose = home.appendingPathComponent("Shelf/Formula sheet.pdf")
        FileManager.default.createFile(atPath: loose.path, contents: Data("x".utf8))
        check("linked folder: its PDFs three folders down, no hidden files, nothing else",
              CourseStore.pdfs(in: shelf).map(\.lastPathComponent) == ["notes.pdf", "far.pdf", "slides.PDF"]
              && CourseStore.pdfs(in: home.appendingPathComponent("gone")).isEmpty)
        check("linked folder: a PDF's read text is kept in our cache, never in the student's folder",
              CourseStore.textCache(for: shelf.appendingPathComponent("notes.pdf"), courses: Paths.courses, cache: Paths.textCache).path.hasPrefix(Paths.textCache.path + "/")
              && CourseStore.textCache(for: Paths.courses.appendingPathComponent("A/materials/n.pdf"), courses: Paths.courses, cache: Paths.textCache).path
                .hasSuffix("/A/materials/_text/n.pdf.json")
              && CourseStore.textCache(for: shelf.appendingPathComponent("notes.pdf"), courses: Paths.courses, cache: Paths.textCache)
                == CourseStore.textCache(for: shelf.appendingPathComponent("notes.pdf"), courses: Paths.courses, cache: Paths.textCache))
        check("list: a folder shows its PDF count, a missing one shows none",
              CourseStore.items([shelf, loose, home.appendingPathComponent("gone")]).map(\.count) == [3, nil, nil]
              && CourseItemRow.detail(CourseItem(url: shelf, kind: .folder, count: 3)) == "3 PDFs"
              && CourseItemRow.detail(CourseItem(url: shelf, kind: .folder, count: nil)) == "Not found")

        // The course as the AI's project: every PDF as text, in the course's own folder
        var takenNames = Set<String>()
        check("project: each PDF gets a text copy; two with one name don't collide",
              CourseStore.textName(for: URL(fileURLWithPath: "/a/Notes.pdf"), taken: &takenNames) == "Notes.txt"
              && CourseStore.textName(for: URL(fileURLWithPath: "/b/notes.pdf"), taken: &takenNames) == "notes (2).txt"
              && CourseStore.textFile(name: "Notes.pdf", pages: [" one ", "two"]) == "=== Notes.pdf, page 1 ===\none\n\n=== Notes.pdf, page 2 ===\ntwo\n")
        let projectShelf = home.appendingPathComponent("Shelf/Project", isDirectory: true)
        try? FileManager.default.createDirectory(at: projectShelf, withIntermediateDirectories: true)
        makePDF(at: projectShelf.appendingPathComponent("Syllabus.pdf"), pages: ["The midterm is in week seven.", "Office hours are on Tuesday."])
        FileManager.default.createFile(atPath: projectShelf.appendingPathComponent("diary.txt").path, contents: Data("private".utf8))
        makePDF(at: CourseStore.shared.dir("PROJ 1").appendingPathComponent("materials/Own.pdf"), pages: ["An own page."])
        let project = CourseStore.shared.syncText("PROJ 1", folders: [projectShelf.path])
        let mirror = CourseStore.shared.dir("PROJ 1").appendingPathComponent("text")
        let mirrored = ((try? FileManager.default.contentsOfDirectory(atPath: mirror.path)) ?? []).sorted()
        check("project: the course's folder holds the text of its own PDFs and the linked folder's",
              project?.count == 2 && project?.folders == [mirror.path, CourseStore.shared.dir("PROJ 1").appendingPathComponent("materials").path]
              && mirrored == ["Own.txt", "Syllabus.txt"]
              && ((try? String(contentsOf: mirror.appendingPathComponent("Syllabus.txt"), encoding: .utf8)) ?? "").contains("=== Syllabus.pdf, page 2 ===\nOffice hours"))
        check("project: nothing is written into the linked folder, and its other files aren't copied",
              ((try? FileManager.default.contentsOfDirectory(atPath: projectShelf.path)) ?? []).sorted() == ["Syllabus.pdf", "diary.txt"]
              && !mirrored.contains { $0.contains("diary") })
        check("project: a PDF that leaves the course takes its text copy with it; no PDFs, no project",
              CourseStore.shared.syncText("PROJ 1", folders: [])?.count == 1
              && ((try? FileManager.default.contentsOfDirectory(atPath: mirror.path)) ?? []) == ["Own.txt"]
              && CourseStore.shared.syncText("PROJ 2", folders: []) == nil)
        // Two PDFs with one name: when the first leaves, the second takes over its text file's name.
        let twinShelf = home.appendingPathComponent("Shelf/Twins", isDirectory: true)
        try? FileManager.default.createDirectory(at: twinShelf, withIntermediateDirectories: true)
        let ownTwin = CourseStore.shared.dir("PROJ 3").appendingPathComponent("materials/Same.pdf")
        makePDF(at: twinShelf.appendingPathComponent("Same.pdf"), pages: ["The linked words."])
        makePDF(at: ownTwin, pages: ["The own words."])
        try? FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)],
                                               ofItemAtPath: twinShelf.appendingPathComponent("Same.pdf").path)
        let twinText = CourseStore.shared.dir("PROJ 3").appendingPathComponent("text")
        func twin(_ name: String) -> String { (try? String(contentsOf: twinText.appendingPathComponent(name), encoding: .utf8)) ?? "" }
        CourseStore.shared.syncText("PROJ 3", folders: [twinShelf.path])
        let twinsBefore = twin("Same.txt").contains("own words") && twin("Same (2).txt").contains("linked words")
        // A mark in the text copy, under the date it had: it stays for as long as the copy isn't written again.
        let copyDate = (try? FileManager.default.attributesOfItem(atPath: twinText.appendingPathComponent("Same.txt").path))?[.modificationDate] as? Date
        try? "kept".write(to: twinText.appendingPathComponent("Same.txt"), atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.modificationDate: copyDate ?? Date()], ofItemAtPath: twinText.appendingPathComponent("Same.txt").path)
        CourseStore.shared.syncText("PROJ 3", folders: [twinShelf.path])
        let untouched = twin("Same.txt") == "kept"
        try? FileManager.default.removeItem(at: ownTwin)
        CourseStore.shared.syncText("PROJ 3", folders: [twinShelf.path])
        check("project: a text copy always holds its own PDF's words, also after another PDF had its name",
              twinsBefore && twin("Same.txt").contains("linked words") && !twin("Same.txt").contains("own words")
              && !FileManager.default.fileExists(atPath: twinText.appendingPathComponent("Same (2).txt").path))
        check("project: a PDF that didn't change isn't written again", untouched)
        // Reading ahead runs in the background and can come after the course was renamed or removed.
        CourseStore.shared.warm("PROJ 9", folders: [projectShelf.path])
        check("project: reading ahead for a course whose folder is gone doesn't bring the folder back",
              !FileManager.default.fileExists(atPath: CourseStore.shared.path("PROJ 9").path)
              && CourseStore.shared.ownMaterials("PROJ 9").isEmpty
              && !FileManager.default.fileExists(atPath: CourseStore.shared.path("PROJ 9").path))
        let withFiles = Prompts.user(course: "PROJ 1", note: "", located: nil, quote: "q", hasImage: false, sourceApp: "", sourceTitle: "",
                                     history: [], question: "Why?", files: CourseFiles(text: "/c/text", pdfs: "/c/materials", count: 2))
        check("project: the question says where the course's files are, only when there are some",
              withFiles.contains("<course_files>") && withFiles.contains("/c/text") && withFiles.contains("2 PDFs")
              && !Prompts.user(course: "PROJ 1", note: "", located: nil, quote: "q", hasImage: false, sourceApp: "", sourceTitle: "",
                               history: [], question: "Why?").contains("course_files")
              && Prompts.system(language: "en").contains("<course_files>")
              && AddPage.projectLine(.claudeCLI) == "Claude can open these when it answers." && AddPage.projectLine(nil).hasPrefix("Connect an AI"))
        let remembered = CourseStore.memoryLine(date: Date(), question: "I don’t get this", quote: "If f is\ndifferentiable",
                                                answer: "It means a tangent plane fits.\n\n**Source: Lecture 9.pdf p.2**")
        check("memory: one line per answer, with the question, the picked text and where the answer came from",
              remembered.hasPrefix("- ") && remembered.hasSuffix(" · I don’t get this · “If f is differentiable” · Lecture 9.pdf p.2")
              && !CourseStore.memoryLine(date: Date(), question: "Example", quote: nil, answer: "No source line").contains("“"))
        CourseStore.shared.remember(course: "PROJ 1", line: "- 2026-11-24 · A")
        CourseStore.shared.remember(course: "PROJ 1", line: "- 2026-11-25 · B")
        check("memory: kept in the course's own folder, oldest first", CourseStore.shared.memory("PROJ 1") == ["- 2026-11-24 · A", "- 2026-11-25 · B"])
        let shared = Prompts.user(course: "PROJ 1", note: "", located: nil, quote: "q", hasImage: false, sourceApp: "", sourceTitle: "",
                                  history: [], question: "Why?", files: CourseFiles(text: "/c/text", pdfs: "/c/materials", count: 15),
                                  kinds: [(.quizzes, ["Quiz 1.pdf"]), (.exams, (1...14).map { "Exam \($0).pdf" })],
                                  memory: CourseStore.shared.memory("PROJ 1"))
        check("project: every question in a course carries the course's memory and its files by kind",
              shared.contains("<course_memory>") && shared.contains("- 2026-11-25 · B") && shared.contains("- Quizzes: Quiz 1.pdf")
              && shared.contains("Exam 12.pdf, and 2 more") && !shared.contains("Exam 13.pdf")
              && !withFiles.contains("<course_memory>") && !withFiles.contains("The files by kind"))

        // Nothing leaves these tests in the real Trash.
        var trashed: [String] = []
        CourseStore.trasher = { url in
            trashed.append(url.lastPathComponent)
            return (try? FileManager.default.removeItem(at: url)) != nil
        }
        let adding = AppModel(preview: true)
        adding.openNewCourse()
        adding.stage([shelf, loose, shelf.appendingPathComponent("readme.txt"), shelf])
        check("new course: picked PDFs and folders wait; the folder offers its name",
              adding.staged.count == 2 && adding.newCourseName == "Linear Algebra" && adding.hasCourseDraft && adding.holdsOpen)
        adding.outsideClick()
        check("new course: picking up a file in another app doesn't fold the Add tab", adding.mode == .add && adding.staged.count == 2)
        adding.collapse()
        check("new course: closed without Add, the picked ones are gone and nothing was made",
              adding.staged.isEmpty && adding.newCourseName.isEmpty && adding.config.courses == ["General"]
              && !FileManager.default.fileExists(atPath: CourseStore.shared.path("Linear Algebra").path))
        adding.openNewCourse()
        adding.stage([shelf, loose])
        adding.addCourse()
        let made = adding.config.folders(for: "Linear Algebra")
        check("new course: Add links the folder where it is and copies the PDF in",
              adding.config.courses == ["General", "Linear Algebra"] && made == [shelf.standardizedFileURL.path]
              && CourseStore.shared.ownMaterials("Linear Algebra").map(\.lastPathComponent) == ["Formula sheet.pdf"]
              && CourseStore.shared.materials("Linear Algebra", folders: made).count == 4
              && adding.mode == .home && adding.staged.isEmpty && ConfigStore.load().folders(for: "Linear Algebra") == made)
        check("new course: a copied PDF goes straight into the folder for its kind",
              FileManager.default.fileExists(atPath: CourseStore.shared.path("Linear Algebra")
                .appendingPathComponent("materials/Exam prep/Formula sheet.pdf").path))
        check("new course: a name already used keeps what was picked", {
            adding.openNewCourse(); adding.stage([loose]); adding.newCourseName = "linear algebra"; adding.addCourse()
            return adding.mode == .add && adding.staged.count == 1 && adding.config.courses.count == 2
        }())
        adding.collapse()

        adding.editCourse("Linear Algebra")
        check("edit: the course's page opens with its name", adding.mode == .add && adding.editingCourse == "Linear Algebra" && adding.editName == "Linear Algebra")
        let extra = home.appendingPathComponent("Shelf/Extra", isDirectory: true)
        try? FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        adding.addDropped([extra, home.appendingPathComponent("Shelf/song.mp3")])
        check("edit: a dropped folder is linked at once", adding.config.folders(for: "Linear Algebra").count == 2)
        adding.remove(CourseItem(url: extra, kind: .folder, count: 0))
        check("edit: ✕ on a folder unlinks it and leaves the folder alone",
              adding.config.folders(for: "Linear Algebra") == made && FileManager.default.fileExists(atPath: extra.path))
        let copied = CourseStore.shared.ownMaterials("Linear Algebra")[0]
        adding.remove(CourseItem(url: copied, kind: .pdf, count: nil))
        check("edit: ✕ on a copied PDF moves it to the Trash; a PDF in a linked folder can't be trashed from here",
              trashed == ["Formula sheet.pdf"] && CourseStore.shared.ownMaterials("Linear Algebra").isEmpty
              && !CourseStore.shared.trashMaterial(shelf.appendingPathComponent("notes.pdf"), course: "Linear Algebra")
              && FileManager.default.fileExists(atPath: shelf.appendingPathComponent("notes.pdf").path))

        // Sorting a course's files by kind (the user's request, 2026-11-25)
        let named: [(String, MaterialKind)] = [
            ("Lecture 9.pdf", .lectureNotes), ("MATH237_Lec03_slides.pdf", .lectureNotes), ("Week 5.pdf", .lectureNotes),
            ("Course notes (Wolczuk).pdf", .courseNotes), ("Chapter 4.pdf", .courseNotes), ("ch2.pdf", .courseNotes),
            ("Quiz 3.pdf", .quizzes), ("quiz3_solutions.pdf", .quizzes), ("Quizzes F25.pdf", .quizzes),
            ("Midterm 2024.pdf", .exams), ("Final Exam Solutions.pdf", .exams), ("MT1.pdf", .exams), ("Test 2.pdf", .exams),
            ("Practice Midterm.pdf", .examPrep), ("Midterm review.pdf", .examPrep), ("Formula sheet.pdf", .examPrep),
            ("Sample final.pdf", .examPrep), ("Assignment 3.pdf", .assignments), ("A2.pdf", .assignments),
            ("HW5 solutions.pdf", .assignments), ("Problem Set 1.pdf", .assignments),
            ("Course Outline F25.pdf", .outline), ("syllabus.pdf", .outline),
            ("Examples of limits.pdf", .other), ("Hypothesis testing.pdf", .other), ("Sampling distributions.pdf", .other),
            ("Taylor formula.pdf", .other),
        ]
        let misread = named.filter { MaterialKind.of(name: $0.0) != $0.1 }.map(\.0)
        check("sorting: a file's kind from its name (examples aren't exams, testing isn't a test)\(misread.isEmpty ? "" : ": \(misread)")",
              misread.isEmpty)
        check("sorting: with no sign in the name, a linked file's folder decides, then the top of its first page",
              MaterialKind.of(name: "Q1.pdf", folder: "Quizzes") == .quizzes
              && MaterialKind.of(name: "scan 0412.pdf", firstPage: "MATH 237 Fall 2025\nMidterm Examination\nName:") == .exams
              && MaterialKind.of(name: "scan 0413.pdf", firstPage: "We use a test statistic before the midterm.") == .other
              && MaterialKind.of(name: "scan 0414.pdf", firstPage: "Lecture 12: The chain rule") == .lectureNotes)
        let sortOwn = CourseStore.shared.dir("SORT 1").appendingPathComponent("materials")
        makePDF(at: sortOwn.appendingPathComponent("Quiz 1.pdf"), pages: ["Quiz 1. Find the limit."])
        makePDF(at: sortOwn.appendingPathComponent("scan.pdf"), pages: ["Assignment 2\nDue Friday."])
        let movedCount = CourseStore.shared.sortOwn("SORT 1")
        let sortedQuiz = sortOwn.appendingPathComponent("Quizzes/Quiz 1.pdf")
        check("sorting: copies that aren't sorted yet move into their kind's folder, with their read text",
              movedCount == 2 && FileManager.default.fileExists(atPath: sortedQuiz.path)
              && FileManager.default.fileExists(atPath: sortOwn.appendingPathComponent("Assignments/scan.pdf").path)
              && FileManager.default.fileExists(atPath: sortOwn.appendingPathComponent("Quizzes/_text/Quiz 1.pdf.json").path)
              && !FileManager.default.fileExists(atPath: sortOwn.appendingPathComponent("Quiz 1.pdf").path)
              && CourseStore.shared.sortOwn("SORT 1") == 0)
        let byHand = CourseStore.shared.move(sortedQuiz, to: .examPrep, course: "SORT 1")
        check("sorting: a copy put under another kind by hand moves there; a PDF in a linked folder never moves",
              byHand?.path == sortOwn.appendingPathComponent("Exam prep/Quiz 1.pdf").path
              && byHand.map { CourseStore.shared.kind(of: $0) } == .examPrep
              && CourseStore.shared.move(shelf.appendingPathComponent("notes.pdf"), to: .exams, course: "SORT 1") == nil
              && FileManager.default.fileExists(atPath: shelf.appendingPathComponent("notes.pdf").path))
        check("sorting: the course's list shows each copy with its kind, in the kinds' order",
              CourseStore.shared.items("SORT 1", folders: []).map(\.group) == [.assignments, .examPrep]
              && CourseStore.shared.byKind("SORT 1").map(\.kind) == [.assignments, .examPrep])
        SessionLog.append(SessionRecord(course: "Linear Algebra", task: "", start: Date(), end: Date(), plannedMinutes: 50,
                                        focusSeconds: 60, distractSeconds: 0, questions: ["Why?"]))
        adding.editName = "MATH 136"
        adding.renameCourse()
        check("edit: renaming moves the folder, the links and past sessions",
              adding.config.courses == ["General", "MATH 136"] && adding.editingCourse == "MATH 136"
              && adding.config.folders(for: "MATH 136") == made
              && FileManager.default.fileExists(atPath: CourseStore.shared.path("MATH 136").path)
              && !FileManager.default.fileExists(atPath: CourseStore.shared.path("Linear Algebra").path)
              && SessionLog.lastStuck(course: "MATH 136") == ["Why?"])
        adding.collapse()
        adding.openForDrop()
        check("drag: something dragged over the folded island reopens the page that was just used", adding.mode == .add && adding.editingCourse == "MATH 136")
        adding.removingCourse = true
        adding.removeCourse()
        check("edit: removing a course trashes its own folder and leaves the linked one",
              adding.config.courses == ["General"] && trashed.last == "MATH 136" && adding.mode == .home
              && FileManager.default.fileExists(atPath: shelf.appendingPathComponent("notes.pdf").path))
        adding.collapse()
        adding.addDropped([shelf])
        check("drop: with no course to take it, a dropped folder starts a new one",
              adding.mode == .add && adding.editingCourse == nil && adding.staged.count == 1 && adding.newCourseName == "Linear Algebra")
        adding.collapse()
        check("words: what was added", AppModel.addedWords(files: 2, folders: 1) == "2 files and 1 folder"
              && AppModel.addedWords(files: 0, folders: 2) == "2 folders" && AppModel.addedWords(files: 0, folders: 0).isEmpty
              && AddPage.summary(files: 15, folders: 1) == "15 files · 1 folder linked" && AddPage.summary(files: 0, folders: 0) == "No files yet"
              && CourseFilesCard.destination(nil).contains("when you press Add") && CourseFilesCard.destination("A") == "They go into A")

        let oldStyle = #"{"presets":[{"course":"일반","task":"바로 25분","minutes":25},{"course":"MATH 237","task":"교과서 읽기","minutes":50}]}"#
        let migrated = try? JSONDecoder().decode(AppConfig.self, from: Data(oldStyle.utf8))
        check("an older config still lists its courses, General renamed", migrated?.courses == ["General", "MATH 237"] && migrated?.sessionMinutes == 50)
        let oldAI = #"{"ai":{"provider":"auto","model":"","language":"ko"}}"#
        let oldAIDecoded = try? JSONDecoder().decode(AppConfig.self, from: Data(oldAI.utf8))
        check("an old config with a language key still loads", oldAIDecoded?.ai.provider == "auto")
        check("answer language: Korean when chosen", Prompts.system(language: "ko").contains("Answer in Korean")
              && Prompts.system(language: "en").contains("Answer in English."))
        check("answer language: Korean words, Korean answer", Prompts.answerLanguage(typed: "이게 왜 연속이야?") == "ko"
              && Prompts.answerLanguage(typed: "f'(x) 뜻이 뭐야") == "ko")
        check("answer language: English words, English answer", Prompts.answerLanguage(typed: "why is it continuous?") == "en")
        check("answer language: a button alone is English", Prompts.answerLanguage(typed: "") == "en")
        check("counted: one and many", counted(1, "question") == "1 question" && counted(2, "file") == "2 files" && counted(0, "session") == "0 sessions")

        // What "Send" sends
        check("send: nothing picked, nothing typed", Prompts.compose(preset: nil, extra: "  ") == nil)
        let onlyPreset = Prompts.compose(preset: Prompts.dontGet, extra: "")
        check("send: preset alone", onlyPreset?.prompt == Prompts.dontGet.prompt && onlyPreset?.display == "I don’t get this")
        let onlyText = Prompts.compose(preset: nil, extra: " why is it continuous? ")
        check("send: typed alone", onlyText?.prompt == "why is it continuous?" && onlyText?.display == "why is it continuous?")
        let both = Prompts.compose(preset: Prompts.example, extra: "in two variables")
        check("send: preset plus typed", both?.prompt.contains(Prompts.example.prompt) == true && both?.prompt.contains("in two variables") == true
              && both?.display == "Example · in two variables")

        // Claude that ships inside the Claude desktop app
        let fakeHome = home.appendingPathComponent("fakehome")
        let bundled = fakeHome.appendingPathComponent("Library/Application Support/Claude/claude-code/2.1.9/abc123/claude.app/Contents/MacOS")
        let older = fakeHome.appendingPathComponent("Library/Application Support/Claude/claude-code/2.1.10/def456/claude.app/Contents/MacOS")
        for folder in [bundled, older] {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: folder.appendingPathComponent("claude").path, contents: Data("#!/bin/sh\n".utf8),
                                           attributes: [.posixPermissions: 0o755])
        }
        check("desktop Claude: newest version is found", CLILocator.desktopClaude(home: fakeHome.path)?.contains("/2.1.10/def456/") == true)
        check("desktop Claude: none when the app is absent", CLILocator.desktopClaude(home: home.appendingPathComponent("nobody").path) == nil)

        // Where the right-click button and the popup go
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let onTop = RightClickWatcher.buttonFrame(menu: NSRect(x: 600, y: 400, width: 260, height: 300), screen: screen)
        check("ask button sits on top of the menu", onTop.minY == 704 && onTop.minX == 600 && onTop.width == 260)
        let under = RightClickWatcher.buttonFrame(menu: NSRect(x: 600, y: 760, width: 180, height: 310), screen: screen)
        check("ask button goes under a menu at the top edge", under.maxY == 756 && under.width == 220)
        let corner = AskPopupController.cardOrigin(for: CGPoint(x: 1900, y: 100), visible: screen)
        check("popup stays on screen", corner.x + AskPopupController.cardWidth <= 1920 && corner.y >= 440)

        // Screens without a notch, and which screen gets the island (Coucou's rules)
        let monitor = NotchGeometry.make(screenWidth: 1920, safeTop: 0, leftWidth: nil, rightWidth: nil, menuBar: 30)
        check("no notch: small bar, not menu bar tall", monitor == NotchGeometry(notchWidth: 80, notchHeight: 24, hasNotch: false))
        let thin = NotchGeometry.make(screenWidth: 1440, safeTop: 0, leftWidth: nil, rightWidth: nil, menuBar: 22)
        check("no notch: never taller than the menu bar", thin.notchHeight == 22)
        let hiddenBar = NotchGeometry.make(screenWidth: 1440, safeTop: 0, leftWidth: nil, rightWidth: nil, menuBar: 0)
        check("no notch: hidden menu bar keeps the usual height", hiddenBar.notchHeight == 24)
        let macbook = NotchGeometry.make(screenWidth: 1728, safeTop: 32, leftWidth: 771.5, rightWidth: 771.5, menuBar: 32)
        check("notch: measured from the screen", macbook == NotchGeometry(notchWidth: 185, notchHeight: 32, hasNotch: true))
        check("screen: notch screen by default", IslandController.screenIndex(for: "notch", hasNotch: [false, true], containsMouse: [true, false]) == 1)
        check("screen: menu bar screen when nothing has a notch", IslandController.screenIndex(for: "notch", hasNotch: [false, false], containsMouse: [false, true]) == 0)
        check("screen: follows the pointer", IslandController.screenIndex(for: "mouse", hasNotch: [false, true], containsMouse: [true, false]) == 0)
        check("screen: pointer nowhere falls back to the notch", IslandController.screenIndex(for: "mouse", hasNotch: [false, true], containsMouse: [false, false]) == 1)
        check("screen: menu bar screen on request", IslandController.screenIndex(for: "main", hasNotch: [false, true], containsMouse: [false, true]) == 0)
        check("screen: none without screens", IslandController.screenIndex(for: "notch", hasNotch: [], containsMouse: []) == nil)
        check("default screen is the notch one", AppConfig.default.display == "notch")

        // Mascot
        check("mascot: thinking beats hover", MascotMood.of(busy: true, hover: true) == .thinking)
        check("mascot: smiles under the pointer", MascotMood.of(busy: false, hover: true) == .happy)
        check("mascot: rests otherwise", MascotMood.of(busy: false, hover: false) == .rest)
        // Squat's faces: white eyes whose shape and place change with the mood, and how two moods mix.
        let rest = MascotLook.of(.rest)
        let moods: [MascotMood] = [.rest, .happy, .thinking, .focus, .drift, .sleep, .proud, .sad, .angry]
        check("squat: the eyes are white in every mood", moods.allSatisfy { MascotLook.of($0).eye == MascotLook.white })
        check("squat: asleep on a break, smiling when glad or done", MascotLook.of(.sleep).shape == 2
              && MascotLook.of(.happy).shape == 1 && MascotLook.of(.proud).shape == 1 && rest.shape == 0)
        check("squat: focus narrows the eyes, drift widens them", MascotLook.of(.focus).open < 0.5 && MascotLook.of(.drift).open > 1)
        check("squat: sad and cross lids slope opposite ways, both with longer eyes",
              MascotLook.of(.sad).lid.y < 0 && MascotLook.of(.angry).lid.y > 0
              && MascotLook.of(.sad).eyeSize == MascotLook.longEyes && rest.eyeSize.y < MascotLook.longEyes.y)
        let half = MascotLook.mix(rest, MascotLook.of(.happy), 0.5, swap: 0.25)
        check("squat: a change eases the numbers and swaps the shape once", MascotLook.mix(rest, .of(.focus), 0.5).open < 1
              && half.shape == 1 && MascotLook.mix(rest, .of(.happy), 0.2, swap: 0.25).shape == 0)
        check("squat: smiling and sleeping eyes stay put, ovals follow the pointer",
              MascotMood.rest.eyesFollow && MascotMood.focus.eyesFollow && !MascotMood.happy.eyesFollow && !MascotMood.sleep.eyesFollow)
        let right = PointerLook.vector(from: .zero, to: CGPoint(x: 400, y: 0))
        check("eyes: far pointer, full look", abs(right.dx - 1) < 0.001 && right.dy == 0)
        let near = PointerLook.vector(from: .zero, to: CGPoint(x: 0, y: 40))
        check("eyes: near pointer, small look", abs(near.dy - 0.25) < 0.001 && near.dx == 0)
        check("eyes: pointer on it, straight ahead", PointerLook.vector(from: .zero, to: .zero) == .zero)
        check("squat: a blink shuts halfway and opens again", MascotView.blink(sinceStart: MascotView.blinkLength / 2) > 0.95
              && MascotView.blink(sinceStart: 0) == 0 && MascotView.blink(sinceStart: MascotView.blinkLength) == 0)
        if let picture = MascotRenderer.shared?.image(rest, pixels: 64, keep: false),
           let data = picture.dataProvider?.data, let bytes = CFDataGetBytePtr(data) {
            let alpha = { (x: Int, y: Int) in bytes[(y * picture.bytesPerRow) + x * 4 + 3] }
            check("squat: drawn in 3D with a clear background", alpha(1, 1) == 0 && alpha(32, 36) == 255)
        } else {
            check("squat: Metal draws it", false)
        }

        // The island, Coucou's way
        let mac = NotchGeometry(notchWidth: 185, notchHeight: 32, hasNotch: true)
        check("island: hidden is the notch itself", AppModel.size(for: .idle, geo: mac) == CGSize(width: 185, height: 32))
        check("island: peeking adds an 80-point ear on each side", AppModel.size(for: .compact, geo: mac) == CGSize(width: 345, height: 32))
        check("island: opened is 640 wide", [IslandMode.home, .record, .add, .nudge, .summary, .setup, .greeting]
              .allSatisfy { AppModel.size(for: $0, geo: mac).width == 640 })
        let bar = NotchGeometry.fallback
        check("island: no notch peeks from the small bar", AppModel.size(for: .compact, geo: bar) == CGSize(width: 240, height: 24))
        check("mascot: hidden behind a real notch", !AppModel.mascotSpot(for: .idle, geo: mac).visible)
        check("mascot: centred in the small bar", AppModel.mascotSpot(for: .idle, geo: bar) == MascotSpot(x: 40, y: 12, height: 18, visible: true))
        let ear = AppModel.mascotSpot(for: .compact, geo: mac)
        // The eyes and the body turn must both go toward the pointer; once they cancelled out.
        let lookingRight = MascotView.aimed(MascotLook.of(.rest), at: CGVector(dx: 1, dy: 0), eyes: true)
        let lookingUp = MascotView.aimed(MascotLook.of(.rest), at: CGVector(dx: 0, dy: -1), eyes: true)
        check("mascot: the eyes slide toward the pointer and the body turns the same way",
              lookingRight.look.x > 1 && lookingRight.turn < -0.15 && lookingUp.look.y > 1 && lookingUp.turn == 0
              && MascotView.aimed(MascotLook.of(.happy), at: CGVector(dx: 1, dy: 0), eyes: false).look == MascotLook.of(.happy).look)
        check("mascot: in the left ear when peeking", ear.x == 40 && ear.y == 16 && ear.height <= 24)
        let card = AppModel.mascotSpot(for: .home, geo: mac)
        check("mascot: large, left of the text, inside the card", card.height >= 50 && card.x + card.height * MascotView.aspect / 2 < 98
              && card.y > 42 && card.y < 160 - 10)
        check("mascot: same place on every tab", [IslandMode.record, .add, .nudge, .summary].allSatisfy { AppModel.mascotSpot(for: $0, geo: mac) == card })
        check("island: tabs fold by themselves, nudge and greeting have their own rules",
              IslandMode.home.closesByItself && IslandMode.record.closesByItself && !IslandMode.nudge.closesByItself
              && !IslandMode.greeting.closesByItself && !IslandMode.compact.closesByItself)
        check("mood: answer first", MascotMood.of(busy: true, hover: true, drift: true, resting: false, inSession: true, finished: false) == .thinking)
        check("mood: wandering off shows", MascotMood.of(busy: false, hover: true, drift: true, resting: false, inSession: true, finished: false) == .drift)
        check("mood: focus in a session, sleep in a break", MascotMood.of(busy: false, hover: false, drift: false, resting: false, inSession: true, finished: false) == .focus
              && MascotMood.of(busy: false, hover: false, drift: false, resting: true, inSession: true, finished: false) == .sleep)
        check("mood: proud at the end", MascotMood.of(busy: false, hover: false, drift: false, resting: false, inSession: false, finished: true) == .proud)
        check("mascot lines: never empty", (0..<6).allSatisfy { !MascotLines.pick(session: nil, drift: false, todayMinutes: 0, index: $0).isEmpty })

        // Study record
        let base = cal(2026, 11, 18, 15)
        let records = [
            SessionRecord(course: "A", task: "", start: base, end: base, plannedMinutes: 50, focusSeconds: 40 * 60, distractSeconds: 0, questions: ["q1", "q2"]),
            SessionRecord(course: "B", task: "", start: base, end: base.addingTimeInterval(-3600), plannedMinutes: 25, focusSeconds: 20 * 60 + 59, distractSeconds: 0, questions: []),
            SessionRecord(course: "A", task: "", start: base, end: base.addingTimeInterval(-86400 * 2), plannedMinutes: 50, focusSeconds: 30 * 60, distractSeconds: 0, questions: ["q"]),
            SessionRecord(course: "A", task: "", start: base, end: base.addingTimeInterval(-86400 * 9), plannedMinutes: 50, focusSeconds: 99 * 60, distractSeconds: 0, questions: []),
        ]
        check("record: today adds focused minutes", StudyStats.today(records, now: base) == DayStats(minutes: 60, sessions: 2, questions: 2))
        let days = StudyStats.week(records, now: base)
        check("record: seven days ending today", days.count == 7 && days.last?.minutes == 60 && days[4].minutes == 30
              && days.reduce(0) { $0 + $1.minutes } == 90)

        // Prompt
        let prompt = Prompts.user(course: course, note: "Notation: grad f", located: hit, quote: "f is differentiable",
                                  hasImage: false, sourceApp: "Preview", sourceTitle: "Lecture 9.pdf",
                                  history: [(q: "I don’t get this", a: "It means a tangent plane approximates f")], question: "Example")
        check("prompt carries course, excerpt, quote, history", prompt.contains("TEST 101") && prompt.contains("page=\"2\"")
              && prompt.contains("f is differentiable") && prompt.contains("tangent plane") && prompt.contains("<question>\nExample"))

        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        return failures == 0
    }

    // MARK: - One real question through whatever AI is connected

    /// `StudyNotch --asktest [image]`: sends one short question the way the app does and prints
    /// what came back. This uses the user's AI account, so it is run by hand, never by --selftest.
    static func askTest(imagePath: String?) -> Bool {
        _ = useTemporaryHome()
        CLILocator.shared.scan()
        // Which AI to try: STUDYNOTCH_AI=claude-cli|codex-cli|gemini-cli|api-key (Claude when unset).
        let wanted = ProcessInfo.processInfo.environment["STUDYNOTCH_AI"] ?? AIKind.claudeCLI.rawValue
        guard let kind = AIKind(rawValue: wanted), AIEngine.shared.installed(kind) else {
            print("\(wanted) is not on this Mac")
            return false
        }
        let quote = imagePath == nil ? "If f is differentiable at (a,b), then f is continuous at (a,b)." : nil
        let question = imagePath == nil ? Prompts.summary.prompt : "List the button labels in this picture from left to right, separated by commas."
        let prompt = Prompts.user(course: "", note: "", located: nil, quote: quote, hasImage: imagePath != nil,
                                  sourceApp: "", sourceTitle: "", history: [], question: question)
        let request = AIRequest(system: Prompts.system(language: "en"), prompt: prompt, imagePath: imagePath, model: "")
        let run = runReal(request, kind: kind)
        print("via: \(kind.rawValue)  desktopClaude: \(CLILocator.shared.claudeFromDesktopApp)")
        print("first text after: \(run.firstText.map { String(format: "%.1fs", $0) } ?? "-")  total: \(String(format: "%.1fs", run.total))  streamed chunks: \(run.deltas)")
        if let failure = run.failure {
            print("FAILED: \(failure)")
            return false
        }
        print("answer: \(run.text)")
        return !run.text.isEmpty
    }

    /// Sends a request for real and waits for the whole answer.
    private static func runReal(_ request: AIRequest, kind: AIKind)
        -> (text: String, deltas: Int, firstText: TimeInterval?, failure: String?, statuses: [String], total: TimeInterval) {
        var text = ""
        var deltas = 0
        var finished = false
        var failure: String?
        var statuses: [String] = []
        let began = Date()
        var firstText: TimeInterval?
        AIEngine.shared.run(request, kind: kind) { event in
            switch event {
            case .delta(let chunk):
                text += chunk
                deltas += 1
                if firstText == nil { firstText = Date().timeIntervalSince(began) }
            case .replace(let whole):
                text = whole
                if firstText == nil, !whole.isEmpty { firstText = Date().timeIntervalSince(began) }
            case .status(let words):
                statuses.append(words)
            case .done:
                finished = true
            case .failed(let message):
                failure = message
                finished = true
            }
        }
        while !finished, Date().timeIntervalSince(began) < 240 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        if !finished, failure == nil { failure = "No answer in 240 seconds." }
        return (text, deltas, firstText, failure, statuses, Date().timeIntervalSince(began))
    }

    /// `StudyNotch --asktest-course`: a made-up course, with one PDF copied into it and one in a
    /// linked folder. The answer to the question is on pages that are NOT in the excerpt sent with
    /// it, so a right answer proves the AI opened the course's files by itself, as its project.
    /// Uses the user's AI account (STUDYNOTCH_AI picks which), so it is run by hand.
    /// `--asktest-claude-app`: the real question flow (`AppModel.ask`) with Claude and the Mac's
    /// sign-in, in a throw-away home: a question and a follow-up in course "STUDYNOTCH TEST". Checks
    /// that the answers came, that Claude's session file holds both questions under the session's
    /// name, and that the Claude app says it took the session (its own log). Uses the user's Claude
    /// account, and leaves one "STUDYNOTCH TEST" session in the Claude app.
    /// A real question with Claude through the app's own flow, in a course that already has a
    /// memory and sorted files: the answer has to use both. Not kept in the Claude app.
    @MainActor
    static func askMemoryTest() -> Bool {
        _ = useTemporaryHome()
        _ = NSApplication.shared
        var failures = 0
        func check(_ name: String, _ ok: Bool) {
            if !ok { failures += 1 }
            print("\(ok ? "PASS" : "FAIL")  \(name)")
            fflush(stdout)
        }
        func spin(_ seconds: Double, until done: () -> Bool) {
            let end = Date().addingTimeInterval(seconds)
            while !done() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
        }
        CLILocator.shared.scan()
        guard AIEngine.shared.installed(.claudeCLI) else { print("Claude Code is not on this Mac"); return false }
        AIEngine.shared.refreshStatus()
        spin(40) { AIEngine.shared.isSignedIn(.claudeCLI) != nil }
        guard AIEngine.shared.isSignedIn(.claudeCLI) == true else { print("Claude isn't signed in on this Mac"); return false }

        let course = "STUDYNOTCH MEMORY"
        let own = CourseStore.shared.dir(course).appendingPathComponent("materials")
        makePDF(at: own.appendingPathComponent("Lecture 7.pdf"), pages: [
            "Lecture 7. Lagrange multipliers. To optimise f subject to g = c, solve grad f = lambda grad g together with g = c."])
        makePDF(at: own.appendingPathComponent("Quiz 4.pdf"), pages: [
            "Quiz 4. Question 1 (5 marks). Use Lagrange multipliers to maximise f(x,y) = xy subject to x + y = 10. Show the system you solve."])
        CourseStore.shared.sortOwn(course)
        CourseStore.shared.remember(course: course, line: "- 2026-11-20 · I don’t get this · “the KAPPA-31 condition” · Lecture 7.pdf p.1")

        let m = AppModel()
        m.config.ai = AISettings(provider: AIKind.claudeCLI.rawValue, keepInClaude: false)
        m.session = ActiveSession(preset: Preset(id: course, course: course, task: "", minutes: 25),
                                  start: Date(), deadline: Date().addingTimeInterval(1500))
        m.thread = AskThread(quote: "To optimise f subject to g = c, solve grad f = lambda grad g together with g = c.",
                             imagePath: nil, sourceApp: "Preview", sourceTitle: "Lecture 7.pdf")
        let started = Date()
        m.ask(prompt: "Answer in two short lines. Line 1: what did I ask about earlier in this course? Quote its made-up name. "
                      + "Line 2: how is this tested in this course's quizzes? Name the quiz file.", display: "Memory test")
        spin(240) { m.thread?.busy == false }
        let answer = m.thread?.answer ?? ""
        check("the answer came (\(Int(Date().timeIntervalSince(started)))s)", !answer.isEmpty && m.thread?.error == nil)
        check("it knew what was asked earlier in the course (its memory)", answer.contains("KAPPA-31"))
        check("it found how the course tests it (the quiz, from the files by kind)", answer.contains("Quiz 4"))
        spin(5) { CourseStore.shared.memory(course).count == 2 }
        check("the course remembers this question too", CourseStore.shared.memory(course).last?.contains("Memory test") == true)
        check("nothing was kept in the Claude app", m.thread?.claudeSession == nil)
        print("answer: \(answer.prefix(300))")
        print(failures == 0 ? "all passed" : "\(failures) FAILED")
        return failures == 0
    }

    @MainActor
    static func askClaudeAppTest() -> Bool {
        _ = useTemporaryHome()
        _ = NSApplication.shared
        var failures = 0
        func check(_ name: String, _ ok: Bool) {
            if !ok { failures += 1 }
            print("\(ok ? "PASS" : "FAIL")  \(name)")
            fflush(stdout)
        }
        func spin(_ seconds: Double, until done: () -> Bool) {
            let end = Date().addingTimeInterval(seconds)
            while !done() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
        }
        CLILocator.shared.scan()
        guard AIEngine.shared.installed(.claudeCLI) else { print("Claude Code is not on this Mac"); return false }
        AIEngine.shared.refreshStatus()
        spin(40) { AIEngine.shared.isSignedIn(.claudeCLI) != nil }
        guard AIEngine.shared.isSignedIn(.claudeCLI) == true else { print("Claude isn't signed in on this Mac"); return false }

        let m = AppModel()
        m.config.ai = AISettings(provider: AIKind.claudeCLI.rawValue)
        let course = "STUDYNOTCH TEST"
        m.session = ActiveSession(preset: Preset(id: course, course: course, task: "", minutes: 25),
                                  start: Date(), deadline: Date().addingTimeInterval(1500))
        m.thread = AskThread(quote: "Theorem 2. If f is differentiable at (a,b), then f is continuous at (a,b).",
                             imagePath: nil, sourceApp: "Preview", sourceTitle: "Lecture 9.pdf")
        let started = Date()
        m.ask(prompt: "Explain this in one short sentence.", display: "Explain this")
        spin(240) { m.thread?.busy == false }
        let first = m.thread
        check("the first answer came (\(Int(Date().timeIntervalSince(started)))s)", !(first?.answer ?? "").isEmpty && first?.error == nil)
        guard let id = first?.claudeSession, first?.inClaude == true else {
            check("it is kept as a Claude session", false)
            return false
        }
        print("session \(id)")

        // Claude keeps it under ~/.claude/projects/<the course folder, spelled as a name>/<id>.jsonl.
        let projects = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        func transcript() -> String {
            let dirs = (try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
            for dir in dirs {
                let file = dir.appendingPathComponent("\(id).jsonl")
                if let text = try? String(contentsOf: file, encoding: .utf8) { return text }
            }
            return ""
        }
        let saved = transcript()
        check("Claude saved the session, named after the question", saved.contains("Explain this in one short sentence")
              && saved.contains(ClaudeSession.name(question: "Explain this", quote: first?.quote)))
        let folder = CourseStore.shared.path(course).path
        check("it worked in the course's folder", saved.contains(folder) || saved.contains("/private" + folder))

        // The Claude app writes to its log when it takes a session from the link.
        let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Claude/main.log")
        var took = false
        spin(20) {
            let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            took = text.contains("Imported CLI session \(id)") || text.contains("CLI session \(id) already imported")
            return took
        }
        check("the Claude app took the session from its link", took)

        m.ask(prompt: "Now say the same thing in at most six words.", display: "Shorter")
        spin(240) { m.thread?.busy == false }
        let second = m.thread
        check("the follow-up was answered in the same session", !(second?.answer ?? "").isEmpty && second?.error == nil
              && second?.claudeSession == id && second?.inClaude == true)
        let after = transcript()
        check("the session file holds both questions", after.contains("Explain this in one short sentence")
              && after.contains("at most six words"))
        print("first answer: \(first?.answer.prefix(160) ?? "")")
        print("follow-up answer: \(second?.answer.prefix(160) ?? "")")
        print(failures == 0 ? "all passed" : "\(failures) FAILED")
        return failures == 0
    }

    static func askCourseTest() -> Bool {
        let home = useTemporaryHome()
        CLILocator.shared.scan()
        let wanted = ProcessInfo.processInfo.environment["STUDYNOTCH_AI"] ?? AIKind.claudeCLI.rawValue
        guard let kind = AIKind(rawValue: wanted), AIEngine.shared.installed(kind) else {
            print("\(wanted) is not on this Mac")
            return false
        }
        let course = "TEST 101"
        let quote = "If f is differentiable at (a,b), then f is continuous at (a,b)."
        let own = CourseStore.shared.dir(course).appendingPathComponent("materials/Lecture 9.pdf")
        makePDF(at: own, pages: ["Theorem 2. " + quote,
                                 "Proof. Write the increment of f with its tangent plane and let the point tend to (a,b).",
                                 "Example. The function f(x,y) = |x| + |y| is continuous at the origin but not differentiable there.",
                                 "Course information. The instructor's office is room QX-4417. Office hours are on Tuesday."])
        let shelf = home.appendingPathComponent("Shelf/TEST 101", isDirectory: true)
        try? FileManager.default.createDirectory(at: shelf, withIntermediateDirectories: true)
        makePDF(at: shelf.appendingPathComponent("Syllabus.pdf"),
                pages: ["Syllabus. Assignments are due on Thursday.", "The code word for the final exam is ZEBRA-9081."])
        let linked = [shelf.path]
        let files = CourseStore.shared.syncText(course, folders: linked)
        let located = CourseStore.shared.locate(quote, course: course, hint: nil, folders: linked)
        // STUDYNOTCH_PLAIN=1 asks an everyday question the excerpt already covers: it should be
        // answered at once, without opening any file.
        let plain = ProcessInfo.processInfo.environment["STUDYNOTCH_PLAIN"] == "1"
        let question = plain ? Prompts.dontGet.prompt
            : "Answer two things from this course's files, one short line each: which room is the instructor's office, and what is the code word for the final exam?"
        let prompt = Prompts.user(course: course, note: "", located: located, quote: quote, hasImage: false,
                                  sourceApp: "Preview", sourceTitle: "Lecture 9.pdf", history: [], question: question, files: files)
        let excerptHasThem = prompt.contains("QX-4417") || prompt.contains("ZEBRA-9081")
        let request = AIRequest(system: Prompts.system(language: "en"), prompt: prompt, imagePath: nil, model: "", folders: files?.folders ?? [])
        let run = runReal(request, kind: kind)
        print("via: \(kind.rawValue)  project: \(files.map { "\($0.count) PDFs as text + copies" } ?? "none")  excerpt: \(located.map { "\($0.file) p.\($0.page)" } ?? "none")")
        print("the answers were already in what was sent: \(excerptHasThem)")
        print("it said it was: \(run.statuses.first ?? "-") (\(run.statuses.count)x)  total: \(String(format: "%.1fs", run.total))")
        if let failure = run.failure {
            print("FAILED: \(failure)")
            return false
        }
        print("answer: \(run.text)")
        if plain {
            print("\(run.statuses.isEmpty ? "PASS" : "FAIL")  answered from the excerpt without opening files")
            return run.statuses.isEmpty && run.text.contains("Source: Lecture 9.pdf p.1")
        }
        let own4 = run.text.contains("QX-4417"), linked2 = run.text.contains("ZEBRA-9081")
        print("\(own4 ? "PASS" : "FAIL")  found a fact on page 4 of the copied PDF")
        print("\(linked2 ? "PASS" : "FAIL")  found a fact in the linked folder's PDF")
        return !excerptHasThem && own4 && linked2
    }

    /// `StudyNotch --eyes-sweep`: where the painted eyes land (in % of the picture, from its
    /// centre) as the look and the turn change. The eyes are drawn red here so the gloss can't
    /// be mistaken for them.
    static func eyesSweep() {
        guard let renderer = MascotRenderer.shared else { print("no Metal"); return }
        func centre(_ l: MascotLook) -> (x: Double, y: Double, n: Int) {
            var look = l
            look.eye = [1, 0, 0]
            guard let image = renderer.image(look, pixels: 200, keep: false),
                  let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return (0, 0, 0) }
            var sx = 0.0, sy = 0.0, n = 0
            for y in 0..<image.height {
                for x in 0..<image.width {
                    let i = y * image.bytesPerRow + x * 4
                    let r = Double(bytes[i]), g = Double(bytes[i + 1]), a = Double(bytes[i + 3])
                    if a > 200, r > 150, g < 90 { sx += Double(x); sy += Double(y); n += 1 }
                }
            }
            guard n > 0 else { return (0, 0, 0) }
            return ((sx / Double(n) - Double(image.width) / 2) / Double(image.width) * 100,
                    (sy / Double(n) - Double(image.height) / 2) / Double(image.height) * 100, n)
        }
        let rest = MascotLook.of(.rest)
        for (name, aim) in [("pointer left", CGVector(dx: -1, dy: 0)), ("pointer right", CGVector(dx: 1, dy: 0)),
                            ("pointer above", CGVector(dx: 0, dy: -1)), ("pointer below", CGVector(dx: 0, dy: 1))] {
            let c = centre(MascotView.aimed(rest, at: aim, eyes: true))
            print(String(format: "%-32@ eyes at x %+6.2f%%  y %+6.2f%%  (%d px)", name, c.x, c.y, c.n))
        }
        if let folder = CommandLine.arguments.drop(while: { $0 != "--eyes-sweep" }).dropFirst().first {
            for (name, aim) in [("left", CGVector(dx: -1, dy: 0)), ("centre", CGVector.zero), ("right", CGVector(dx: 1, dy: 0)),
                                ("up", CGVector(dx: 0, dy: -1)), ("down", CGVector(dx: 0, dy: 1)), ("up-right", CGVector(dx: 0.7, dy: -0.7))] {
                if let image = renderer.image(MascotView.aimed(rest, at: aim, eyes: true), pixels: 216, keep: false) {
                    let rep = NSBitmapImageRep(cgImage: image)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder).appendingPathComponent("aim-\(name).png"))
                }
            }
        }
        for (name, change) in [("rest", { (_: inout MascotLook) in }),
                               ("look x -1.5", { (l: inout MascotLook) in l.look.x = -1.5 }),
                               ("look x +1.5", { (l: inout MascotLook) in l.look.x = 1.5 }),
                               ("look y +1.3", { (l: inout MascotLook) in l.look.y = 1.3 }),
                               ("look y -1.3", { (l: inout MascotLook) in l.look.y = -1.3 }),
                               ("turn -0.3", { (l: inout MascotLook) in l.turn = -0.3 }),
                               ("turn +0.3", { (l: inout MascotLook) in l.turn = 0.3 }),
                               ("right now (x +1.5, turn +0.3)", { (l: inout MascotLook) in l.look.x = 1.5; l.turn = 0.3 }),
                               ("left now (x -1.5, turn -0.3)", { (l: inout MascotLook) in l.look.x = -1.5; l.turn = -0.3 })] {
            var l = rest
            change(&l)
            let c = centre(l)
            print(String(format: "%-32@ eyes at x %+6.2f%%  y %+6.2f%%  (%d px)", name, c.x, c.y, c.n))
        }
    }

    // MARK: - Pictures of every island state

    /// `forSite` writes each state on a transparent background, cropped to the island itself,
    /// so the website can place the real UI on its own mock screen.
    static func render(to folder: String, forSite: Bool = false) {
        _ = useTemporaryHome()
        _ = NSApplication.shared
        let out = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let notch = NotchGeometry(notchWidth: 185, notchHeight: 32, hasNotch: true)
        let preset = Preset(id: "MATH 237", course: "MATH 237", task: "", minutes: 50)
        let quote = "If f is differentiable at (a,b) then f is continuous at (a,b)."
        func session() -> ActiveSession {
            var s = ActiveSession(preset: preset, start: Date().addingTimeInterval(-18 * 60),
                                  deadline: Date().addingTimeInterval(32 * 60 + 10))
            s.focusSeconds = 17 * 60
            s.distractSeconds = 60
            s.questions = ["I don’t get this: Theorem 2"]
            return s
        }
        func thread() -> AskThread {
            AskThread(quote: quote, imagePath: nil, sourceApp: "Preview", sourceTitle: "Lecture 9.pdf")
        }
        let answerText = "Being differentiable at (a,b) means f is well approximated by its tangent plane near (a,b). The tangent plane has no breaks, so as you approach that point, the values of f approach f(a,b) too. That is exactly continuity. The reverse does not hold: f can be continuous, even have both partial derivatives, and still not be differentiable.\n\nSource: Lecture 9.pdf p.4"
        let popups: [(String, (AppModel) -> Void)] = [
            ("10-popup-compose", { m in m.session = session(); m.thread = thread(); m.selectedPreset = Prompts.dontGet; m.popupVisible = true }),
            ("11-popup-waiting", { m in
                m.session = session()
                var t = thread()
                t.question = "I don’t get this"
                t.busy = true
                t.status = "Found it in Lecture 9.pdf p.4, writing"
                m.thread = t
                m.popupVisible = true
            }),
            ("12-popup-answer", { m in
                m.session = session()
                var t = thread()
                t.question = "I don’t get this"
                t.answer = answerText
                m.thread = t
                m.popupVisible = true
            }),
            ("12b-popup-in-claude", { m in
                m.session = session()
                var t = thread()
                t.question = "I don’t get this"
                t.answer = answerText
                t.claudeSession = "example"
                t.claudeCourse = "MATH 237"
                t.inClaude = true
                m.thread = t
                m.popupVisible = true
            }),
            ("13-popup-no-ai", { m in
                var t = thread()
                t.question = "I don’t get this"
                t.error = "AI is not connected yet. Install the Claude app and sign in, or enter an API key."
                t.errorAction = .setupAI
                m.thread = t
                m.popupVisible = true
            }),
        ]

        let cal = Calendar.current
        let week: [DayTotal] = [35, 80, 0, 50, 95, 20, 42].enumerated().map { i, m in
            DayTotal(day: cal.date(byAdding: .day, value: i - 6, to: cal.startOfDay(for: Date()))!, minutes: m)
        }
        let states: [(String, (AppModel) -> Void)] = [
            ("01-idle-no-notch", { m in m.geo = .fallback; m.mode = .idle }),
            ("02-peek", { m in m.today = DayStats(minutes: 42, sessions: 1, questions: 2); m.hoverLift = true; m.mode = .compact }),
            ("02b-peek-no-notch", { m in m.geo = .fallback; m.today = DayStats(minutes: 42, sessions: 1, questions: 2); m.mode = .compact }),
            ("03-compact", { m in m.session = session(); m.glyph = .focus; m.mode = .compact }),
            ("03b-compact-no-notch", { m in m.geo = .fallback; m.session = session(); m.glyph = .focus; m.mode = .compact }),
            ("03c-compact-hover", { m in m.session = session(); m.glyph = .focus; m.hoverLift = true; m.mode = .compact }),
            ("04-home-courses", { m in m.materialCounts = ["MATH 237": 3]; m.focusedCourse = "MATH 237"; m.mode = .home }),
            ("05-home-session", { m in m.session = session(); m.glyph = .focus; m.mode = .home }),
            ("05b-home-rest", { m in
                var s = session()
                s.restUntil = Date().addingTimeInterval(4 * 60 + 20)
                m.session = s
                m.glyph = .rest
                m.mode = .home
            }),
            ("05c-home-pat", { m in m.session = session(); m.glyph = .focus; m.mascotLine = "17 min of focus"; m.mode = .home }),
            ("05d-home-closing", { m in m.materialCounts = ["MATH 237": 3]; m.outsideSince = Date().addingTimeInterval(-9); m.mode = .home }),
            ("06-nudge", { m in
                m.session = session()
                m.glyph = .drift
                m.nudge = NudgeInfo(target: "youtube.com", seconds: 125, shownAt: Date())
                m.mode = .nudge
            }),
            ("07-summary", { m in
                m.summary = SessionSummary(preset: preset, focusMinutes: 43, distractMinutes: 4, questions: ["I don’t get this: Theorem 2", "Example: chain rule"])
                m.mode = .summary
            }),
            ("08-setup", { m in
                // A new Mac: Claude is connected, ChatGPT needs a sign-in, Gemini isn't there.
                m.previewChoices = [.claudeCLI: .connected, .codexCLI: .signIn, .geminiCLI: .get]
                m.previewActive = .claudeCLI
                m.previewAccount = "student@example.com · Max"
                m.setupStep = .ai
                m.mode = .setup
            }),
            ("08f-setup-tested", { m in
                // After "Test connection": one real question went out and this came back.
                m.previewChoices = [.claudeCLI: .connected, .codexCLI: .ready, .geminiCLI: .get]
                m.previewActive = .claudeCLI
                m.previewAccount = "student@example.com · Max"
                m.test = .passed(AppModel.testLine(kind: .claudeCLI, seconds: 2.3, reply: "Connected to StudyNotch"))
                m.setupStep = .ai
                m.mode = .setup
            }),
            ("08b-setup-none", { m in
                m.previewChoices = [.claudeCLI: .get, .codexCLI: .get, .geminiCLI: .get]
                m.previewActive = nil
                m.setupStep = .ai
                m.mode = .setup
            }),
            ("08c-setup-waiting", { m in
                m.previewChoices = [.claudeCLI: .ready, .codexCLI: .connected, .geminiCLI: .waiting]
                m.previewActive = .codexCLI
                m.waitingFor = .geminiCLI
                m.setupStep = .ai
                m.mode = .setup
            }),
            ("08e-setup-confirm", { m in
                // Signed in on this Mac, not connected yet: the card asks first.
                m.previewChoices = [.claudeCLI: .ready, .codexCLI: .ready, .geminiCLI: .get]
                m.previewActive = nil
                m.previewAccount = "student@example.com · Max"
                m.confirming = .claudeCLI
                m.setupStep = .ai
                m.mode = .setup
            }),
            ("08d-setup-permissions", { m in
                m.previewChoices = [.claudeCLI: .connected, .codexCLI: .ready, .geminiCLI: .ready]
                m.previewActive = .claudeCLI
                m.setupStep = .permissions
                m.mode = .setup
            }),
            ("09-record", { m in m.week = week; m.today = DayStats(minutes: 42, sessions: 1, questions: 2); m.mode = .record }),
            ("09b-add", { m in m.mode = .add }),
            ("09d-add-picked", { m in
                // A folder and a PDF picked for a course that isn't added yet.
                m.newCourseName = "ACTSCI 221"
                m.staged = [URL(fileURLWithPath: "/Users/student/Documents/ACTSCI 221"), URL(fileURLWithPath: "/Users/student/Downloads/Formula sheet.pdf")]
                m.courseItems = [CourseItem(url: m.staged[0], kind: .folder, count: 12), CourseItem(url: m.staged[1], kind: .pdf, count: nil)]
                m.mode = .add
            }),
            ("09e-edit-course", { m in
                m.materialCounts = ["MATH 237": 15]
                m.previewChoices = [.claudeCLI: .connected]
                m.previewActive = .claudeCLI
                m.config.link("/Users/student/Documents/MATH 237", to: "MATH 237")
                m.editingCourse = "MATH 237"
                m.editName = "MATH 237"
                m.courseItems = [CourseItem(url: URL(fileURLWithPath: "/Users/student/Documents/MATH 237"), kind: .folder, count: 12),
                                 CourseItem(url: URL(fileURLWithPath: "/c/Lecture 9.pdf"), kind: .pdf, count: nil, group: .lectureNotes),
                                 CourseItem(url: URL(fileURLWithPath: "/c/Course notes (Wolczuk).pdf"), kind: .pdf, count: nil, group: .courseNotes),
                                 CourseItem(url: URL(fileURLWithPath: "/c/Assignment 3.pdf"), kind: .pdf, count: nil, group: .assignments)]
                m.mode = .add
            }),
            ("09f-edit-remove", { m in
                m.materialCounts = ["MATH 237": 3]
                m.editingCourse = "MATH 237"
                m.editName = "MATH 237"
                m.removingCourse = true
                m.courseItems = [CourseItem(url: URL(fileURLWithPath: "/c/Lecture 9.pdf"), kind: .pdf, count: nil, group: .lectureNotes)]
                m.mode = .add
            }),
            ("09c-greeting", { m in m.mode = .greeting }),
        ]

        /// Draws one SwiftUI view off screen and writes the part of it that matters.
        func snapshot<V: View>(_ name: String, canvas: CGSize, view: V, crop: (CGSize) -> NSRect) {
            let container = NSView(frame: NSRect(origin: .zero, size: canvas))
            container.wantsLayer = true
            container.layer?.backgroundColor = forSite ? NSColor.clear.cgColor : NSColor(calibratedWhite: 0.32, alpha: 1).cgColor
            let host = NSHostingView(rootView: view)
            host.sizingOptions = []
            host.frame = container.bounds
            container.addSubview(host)
            let window = NSWindow(contentRect: container.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            if forSite {
                window.isOpaque = false
                window.backgroundColor = .clear
            }
            window.contentView = container
            window.orderBack(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.9))
            container.layoutSubtreeIfNeeded()
            let rect = crop(canvas)
            if let rep = container.bitmapImageRepForCachingDisplay(in: rect) {
                container.cacheDisplay(in: rect, to: rep)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try? data.write(to: out.appendingPathComponent(name + ".png"))
                }
            }
            window.orderOut(nil)
        }

        for (name, configure) in states {
            let model = AppModel(preview: true)
            model.geo = notch
            // The pictures show a student's courses; a real install starts with General only.
            model.config.presets += [preset, Preset(id: "STAT 230", course: "STAT 230", task: "", minutes: 50)]
            configure(model)
            snapshot(name, canvas: IslandController.canvas, view: IslandRootView(model: model)) { canvas in
                if forSite, model.islandSize.width > 10 {
                    let w = model.islandSize.width.rounded(.up), h = model.islandSize.height.rounded(.up)
                    return NSRect(x: ((canvas.width - w) / 2).rounded(.down), y: canvas.height - h, width: w, height: h)
                }
                return NSRect(x: 0, y: canvas.height - 430, width: canvas.width, height: 430)
            }
            print("rendered \(name)  island=\(Int(model.islandSize.width))x\(Int(model.islandSize.height))")
        }

        // The mascot on its own, large, for the design notes and the website.
        let moods: [(String, MascotMood)] = [("rest", .rest), ("happy", .happy), ("thinking", .thinking), ("focus", .focus),
                                             ("drift", .drift), ("sleep", .sleep), ("proud", .proud), ("sad", .sad), ("angry", .angry)]
        for (name, mood) in moods {
            let size = CGSize(width: 180, height: 180)
            // Always on the island's black, where the mascot lives.
            let view = ZStack {
                Color.black
                MascotView(mood: mood, height: 120, animated: false)
            }
            .frame(width: size.width, height: size.height)
            snapshot("20-mascot-" + name, canvas: size, view: view) { canvas in NSRect(origin: .zero, size: canvas) }
            print("rendered 20-mascot-\(name)")
        }

        for (name, configure) in popups {
            let model = AppModel(preview: true)
            model.geo = notch
            configure(model)
            let inset = AskPopupController.inset
            snapshot(name, canvas: AskPopupController.canvas, view: AskPopupView(model: model)) { canvas in
                let h = max(model.popupSize.height, 60).rounded(.up)
                // Keep the shadow in the picture.
                return NSRect(x: 0, y: canvas.height - h - inset * 2, width: AskPopupController.cardWidth + inset * 2, height: h + inset * 2)
            }
            print("rendered \(name)  popup=\(Int(model.popupSize.width))x\(Int(model.popupSize.height))")
        }
    }
}
