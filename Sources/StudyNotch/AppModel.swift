import AppKit
import SwiftUI

/// What the notch island is showing. Questions and answers live in their own popup, not here.
/// Like Coucou: hidden on the notch (idle), peeking out when the pointer comes (compact), and
/// opened with a click. The opened island has tabs (home, record, add) and a few cards of its own.
enum IslandMode: Equatable {
    case idle, compact, home, record, add, nudge, summary, setup, greeting

    var isExpanded: Bool { self != .idle && self != .compact }

    /// Folds by itself a while after the pointer leaves (Coucou's 15 seconds).
    var closesByItself: Bool {
        switch self {
        case .home, .record, .add, .summary, .setup: return true
        default: return false
        }
    }
}

/// The tabs at the top left of an opened island.
enum IslandTab: CaseIterable {
    case home, record, add

    var mode: IslandMode {
        switch self {
        case .home: return .home
        case .record: return .record
        case .add: return .add
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .record: return "chart.bar.fill"
        case .add: return "plus"
        }
    }

    var label: String {
        switch self {
        case .home: return "Home"
        case .record: return "Record"
        case .add: return "Add courses and files"
        }
    }
}

/// Where the mascot sits in the island, in the island's own coordinates.
struct MascotSpot: Equatable {
    var x: CGFloat
    var y: CGFloat
    var height: CGFloat
    var visible: Bool
}

enum Glyph: Equatable {
    case none, focus, drift, thinking, rest
}

struct ActiveSession {
    var preset: Preset
    var start: Date
    var deadline: Date
    var focusSeconds = 0
    var distractSeconds = 0
    var questions: [String] = []
    /// "It’s for study" for this session only.
    var tempAllow = Set<String>()
    var restUntil: Date?
}

enum ErrorAction {
    case retry, setupAI, accessibility
}

struct AskThread {
    var quote: String?
    var imagePath: String?
    var sourceApp = ""
    var sourceTitle = ""
    var history: [(q: String, a: String)] = []
    /// What the student typed with the current question ("" for a button alone). Decides the answer language.
    var typed = ""
    /// What the popup shows as the question.
    var question = ""
    /// What is sent to the model.
    var prompt = ""
    var answer = ""
    var status: String?
    var error: String?
    var errorAction: ErrorAction?
    var busy = false
    /// The Claude Code session this window's questions are kept in, when they are kept in the
    /// Claude app (`ClaudeSession`), and the course it is filed under there.
    var claudeSession: String?
    var claudeCourse = ""
    /// The first answer arrived: the session is in the Claude app, and follow-ups continue it.
    var inClaude = false

    /// True once a question has been sent in this popup.
    var started: Bool { !question.isEmpty }
}

struct NudgeInfo {
    var target: String
    var seconds: Int
    var shownAt: Date
}

struct SessionSummary {
    var preset: Preset
    var focusMinutes: Int
    var distractMinutes: Int
    var questions: [String]
}

/// All state and every action. Views only read this and call its methods.
final class AppModel: ObservableObject {
    // Island
    @Published var mode: IslandMode = .idle
    /// The pointer is on the folded island: it swells a little, the way a drop of liquid would.
    @Published var hoverLift = false
    @Published var config: AppConfig = .default
    @Published var session: ActiveSession?
    @Published var nudge: NudgeInfo?
    @Published var summary: SessionSummary?
    @Published var notice: String?
    @Published var glyph: Glyph = .none
    @Published var geo = NotchGeometry.fallback
    @Published var now = Date()
    /// Bumps when permissions or the AI tools on this Mac change, so the setup card redraws.
    @Published var refresh = 0
    /// Which half of the setup card shows: choosing the AI, or the Mac's permissions.
    @Published var setupStep: SetupStep = .ai
    /// A sign-in or install window was opened for this one; the card checks every few seconds
    /// until it is ready, then picks it.
    @Published var waitingFor: AIKind?
    /// A tile was clicked for an AI that is already signed in on this Mac: the card asks
    /// "Connect …?" before any question goes to it.
    @Published var confirming: AIKind?
    /// The "Test connection" button's result: a real question to the connected AI.
    @Published var test: TestState = .idle
    /// PDF count per course, read when the course list opens.
    @Published var materialCounts: [String: Int] = [:]
    @Published var addingCourse = false
    @Published var newCourseName = ""
    /// The course being edited on the Add tab; nil is the new-course page.
    @Published var editingCourse: String?
    /// PDFs and folders picked for a course that hasn't been added yet. Nothing is copied or
    /// linked until "Add"; closing the page without it forgets them.
    @Published var staged: [URL] = []
    /// What the list on the Add tab shows: the picked ones, or the edited course's.
    @Published var courseItems: [CourseItem] = []
    /// "Remove course" asks first.
    @Published var removingCourse = false
    /// The name in the edit page's field.
    @Published var editName = ""
    /// An Open panel is up: clicks in it mustn't fold the island.
    @Published var choosing = false
    /// The course shown in the home card's left half. Picked from the pills on the right.
    @Published var focusedCourse: String?
    /// The pointer left an opened island at this time; the island folds 15 seconds later.
    @Published var outsideSince: Date?
    /// The pointer is on the mascot of an opened island.
    @Published var mascotHover = false
    /// Bumps when the mascot is patted, which makes it hop.
    @Published var mascotPat = 0
    /// A short line the mascot says after a pat.
    @Published var mascotLine: String?
    /// The last seven days of study, oldest first, and today's numbers.
    @Published var week: [DayTotal] = []
    @Published var today = DayStats()
    /// A file is being dragged over the island.
    @Published var dropTargeted = false

    // Question popup
    @Published var popupVisible = false
    /// Screen point (AppKit coordinates) the popup opens next to.
    @Published var popupAnchor = CGPoint.zero
    @Published var thread: AskThread?
    @Published var selectedPreset: AskPreset?
    @Published var askText = ""
    @Published var answerHeight: CGFloat = 40

    /// Read by the window controllers for hit-testing; not published, so they never cause a redraw loop.
    var islandSize: CGSize = .zero
    var popupSize: CGSize = .zero
    var onIslandKey: ((Bool) -> Void)?
    var onPopupKey: ((Bool) -> Void)?
    var onAskAPIKey: (() -> Void)?
    /// Shows the Mac's Open panel for folders (true) or PDFs (false) and hands back what was picked.
    var onChoose: ((Bool, @escaping ([URL]) -> Void) -> Void)?
    /// Opens the course window (its graph and files) for a course.
    var onOpenCourse: ((String) -> Void)?
    /// Opens a sign-in or install script in Terminal. `--uitest` records it instead.
    var openInTerminal: (URL) -> Void = { NSWorkspace.shared.open($0) }
    let previewMode: Bool

    let focus = FocusWatcher()
    let selection = SelectionWatcher()
    let shots = ScreenshotWatcher()

    private var timer: Timer?
    private var hovering = false
    private var hoverChangedAt = Date()
    private var mascotLineUntil: Date?
    private var greetingUntil: Date?
    private var noticeUntil: Date?
    private var driftSeconds = 0
    private var driftTarget = ""
    private var cooldown: [String: Date] = [:]
    private var lastVerdict: Verdict = .neutral
    private var runToken = 0
    private var tickCount = 0
    private var waitingSince: Date?
    private var itemsToken = 0
    /// Which Add page was open last (nil = new course), so a drag from Finder comes back to it.
    private var lastAdd: (course: String?, at: Date)?
    private var waitingAccount: AIAccount = .mac
    private var testToken = 0

    init(preview: Bool = false) {
        previewMode = preview
    }

    func start() {
        Paths.ensure()
        config = ConfigStore.load()
        CLILocator.shared.scan()
        CLILocator.shared.askLoginShell()
        NotificationCenter.default.addObserver(forName: CLILocator.changed, object: nil, queue: .main) { [weak self] _ in
            self?.refresh += 1
            AIEngine.shared.refreshStatus()
        }
        NotificationCenter.default.addObserver(forName: AIEngine.statusChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refresh += 1
            self?.checkWaiting()
        }
        AIEngine.shared.refreshStatus()

        selection.start()

        // A plain screenshot outside a session stays a plain screenshot.
        shots.isEnabled = { [weak self] in self?.screenshotsOpenPopup ?? false }
        shots.onShot = { [weak self] path in self?.shotArrived(path) }
        shots.start()
        shots.cleanOldCaptures()

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        refreshStats()
        if !UserDefaults.standard.bool(forKey: "didOnboard") {
            // First launch: the first step is choosing the AI that answers.
            setupStep = .ai
            mode = .setup
        } else if activeAI == nil {
            // Nothing can answer (nothing installed, or every one signed out): straight to the AI step.
            openSetup(step: .ai)
        } else {
            // Like Coucou on launch: open for a moment, say hello, fold away.
            greetingUntil = Date().addingTimeInterval(3.6)
            mode = .greeting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in self?.mascotPat += 1 }
        }
        dlog("started; ai=\(AIEngine.shared.available().map(\.rawValue)) desktopClaude=\(CLILocator.shared.claudeFromDesktopApp) ax=\(AXIsProcessTrusted())")
    }

    // MARK: - Derived

    /// Folded: peeking while a session runs or the pointer is on it, hidden otherwise.
    var baseMode: IslandMode { session != nil || hovering ? .compact : .idle }

    var screenshotsOpenPopup: Bool {
        if let s = session { return s.restUntil == nil }
        return config.offerOutsideSession
    }

    /// The island's size in each mode (Coucou's sizes): the notch itself, the notch with an
    /// 80-point ear on each side, and a 640-point card.
    func size(for mode: IslandMode) -> CGSize {
        Self.size(for: mode, geo: geo)
    }

    static let openWidth: CGFloat = 640
    static let earWidth: CGFloat = 80

    static func size(for mode: IslandMode, geo: NotchGeometry) -> CGSize {
        switch mode {
        case .idle: return CGSize(width: geo.notchWidth, height: geo.notchHeight)
        case .compact: return CGSize(width: geo.notchWidth + earWidth * 2, height: geo.notchHeight)
        case .setup: return CGSize(width: openWidth, height: 236)
        case .greeting: return CGSize(width: openWidth, height: 150)
        case .add: return CGSize(width: openWidth, height: 204)
        case .home, .record, .nudge, .summary: return CGSize(width: openWidth, height: 160)
        }
    }

    /// Where the mascot goes in each mode. It springs between these places (Coucou's BotPlacement).
    static func mascotSpot(for mode: IslandMode, geo: NotchGeometry) -> MascotSpot {
        let size = size(for: mode, geo: geo)
        switch mode {
        case .idle:
            // Over a real notch there is nothing to show; on the small bar it sits in the middle.
            return geo.hasNotch
                ? MascotSpot(x: 46, y: geo.notchHeight / 2, height: 6, visible: false)
                : MascotSpot(x: size.width / 2, y: size.height / 2, height: max(12, min(18, geo.notchHeight - 6)), visible: true)
        case .compact:
            return MascotSpot(x: earWidth / 2, y: geo.notchHeight / 2, height: max(12, min(20, geo.notchHeight - 8)), visible: true)
        case .greeting:
            return MascotSpot(x: size.width / 2, y: 64, height: 60, visible: true)
        case .setup:
            return MascotSpot(x: 62, y: 96, height: 50, visible: true)
        case .home, .record, .add, .nudge, .summary:
            // The same place on every tab, so it doesn't jump when the taller Add tab opens.
            return MascotSpot(x: 64, y: 42 + (Self.size(for: .home, geo: geo).height - 52) / 2, height: 54, visible: true)
        }
    }

    var mascotSpot: MascotSpot { Self.mascotSpot(for: mode, geo: geo) }

    /// Minutes only: a number that changes every second pulls the eye away from the page.
    var remainingShort: String {
        guard let s = session else { return "" }
        if let rest = s.restUntil {
            return "Break \(max(1, Int((rest.timeIntervalSince(now) / 60).rounded(.up))))m"
        }
        let left = max(0, s.deadline.timeIntervalSince(now))
        return left < 60 ? "<1m" : "\(Int((left / 60).rounded(.up)))m"
    }

    /// 0...1, how much of the session has passed.
    var sessionProgress: Double {
        guard let s = session else { return 0 }
        let total = s.deadline.timeIntervalSince(s.start)
        guard total > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(s.start) / total))
    }

    var remainingClock: String {
        guard let s = session else { return "" }
        let end = s.restUntil ?? s.deadline
        let left = max(0, Int(end.timeIntervalSince(now)))
        return String(format: "%d:%02d", left / 60, left % 60)
    }

    var stuckFromLastTime: [String] {
        guard let s = session else { return [] }
        return SessionLog.lastStuck(course: s.preset.course)
    }

    var accessibilityGranted: Bool { AXIsProcessTrusted() }
    var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }
    var activeAI: AIKind? {
        if previewMode, previewChoices != nil { return previewActive }
        return AIEngine.shared.resolve(config.ai.provider, account: connectedAccount)
    }

    /// For `--render`: the tiles' states and the picked AI, instead of this Mac's.
    var previewChoices: [AIKind: AIChoiceState]?
    var previewActive: AIKind?
    var previewAccount: String?
    var previewOwn = false
    var previewFirstRun = true

    /// The quick questions offered in the popup: first ones before an answer, follow-ups after.
    var composerPresets: [AskPreset] {
        guard let t = thread else { return [] }
        if t.started, !t.answer.isEmpty { return Prompts.narrow + Prompts.followUps }
        return t.imagePath != nil ? Prompts.offerImage : Prompts.offerText
    }

    var canSend: Bool {
        guard let t = thread, !t.busy else { return false }
        return selectedPreset != nil || !askText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What the mascot's face says right now.
    var mascotMood: MascotMood {
        let hover = mode == .greeting || (mode.isExpanded ? (mascotHover || mascotLine != nil) : (mode == .idle && hoverLift))
        // Waiting for a sign-in in another window looks like waiting for an answer.
        let busy = thread?.busy == true || (mode == .setup && (waitingFor != nil || test == .running))
        return MascotMood.of(busy: busy, hover: hover,
                             drift: mode == .nudge || (session != nil && glyph == .drift),
                             resting: session?.restUntil != nil, inSession: session != nil,
                             finished: mode == .summary)
    }

    /// The course whose card is open on the home tab.
    var shownCourse: String? {
        if let f = focusedCourse, config.courses.contains(f) { return f }
        return session?.preset.course ?? config.courses.first
    }


    /// The line under a folded island while the pointer is on it (Coucou's hover line).
    var hoverLine: String {
        if let s = session {
            if s.restUntil != nil { return "\(s.preset.course) · on a break · click to open" }
            return "\(s.preset.course) · focused \(s.focusSeconds / 60) min · \(counted(s.questions.count, "question"))"
        }
        return today.minutes > 0 ? "Studied \(today.minutes) min today · click to open" : "Click to open"
    }

    /// Seconds left before an opened island folds by itself, or nil while it stays.
    func closeCountdown(at t: Date) -> Double? {
        guard mode.closesByItself, !holdsOpen, let since = outsideSince else { return nil }
        return max(0, Self.autoClose - t.timeIntervalSince(since))
    }

    static let autoClose: TimeInterval = 15

    /// Typing a course name, the very first setup, or waiting for a sign-in: never fold under the user's hands.
    var holdsOpen: Bool {
        (mode == .add && hasCourseDraft)
            || (mode == .setup && (!UserDefaults.standard.bool(forKey: "didOnboard") || waitingFor != nil
                                   || confirming != nil || test == .running))
    }

    /// Something on the Add tab would be lost by folding: picked files, a typed name, an open
    /// panel or a question waiting for an answer.
    var hasCourseDraft: Bool {
        if choosing || removingCourse || !staged.isEmpty { return true }
        if let course = editingCourse { return addingCourse && editName != course }
        return addingCourse && !newCourseName.isEmpty
    }

    /// The label on the button that sits on top of the right-click menu.
    var rightClickLabel: String {
        session != nil ? "Ask" : "Ask StudyNotch"
    }

    // MARK: - Pointer (called about 20 times a second by the island's window controller)

    func pointer(inside: Bool) {
        let t = Date()
        if inside != hovering {
            hovering = inside
            hoverChangedAt = t
            hoverLift = inside && !mode.isExpanded
            if inside {
                outsideSince = nil
                // Coucou: the pointer on the hidden island makes it peek out; a click opens it.
                if mode == .idle {
                    mode = .compact
                    play(.peek)
                }
            } else {
                mascotHover = false
                if mode.isExpanded { outsideSince = t }
            }
        }
        // Peeking without a session: back behind the notch a little after the pointer goes.
        if !inside, mode == .compact, session == nil, t.timeIntervalSince(hoverChangedAt) > 4 {
            mode = .idle
        }
    }

    /// A click anywhere outside the island folds it back into the notch.
    func outsideClick() {
        // `--uitest` clicks inside the island by itself; the person's own clicks elsewhere mustn't fold it.
        if UITest.active { return }
        switch mode {
        case .add:
            // The Add tab is where things are dragged in from other apps: a click out there
            // (picking up a file in Finder) must not fold it. It closes with ✕, a tab, or by itself.
            break
        case .home, .record, .summary, .greeting:
            collapse()
        case .setup:
            closeSetup()
        case .nudge:
            if let n = nudge { cooldown[n.target] = Date().addingTimeInterval(600) }
            collapse()
        case .idle, .compact:
            break
        }
    }

    func collapse() {
        if mode == .add { lastAdd = (editingCourse, Date()) }
        clearCourseDraft()
        onIslandKey?(false)
        hoverLift = hovering
        mascotHover = false
        mascotLine = nil
        outsideSince = nil
        // Folded with the pointer still on it: stay peeking, the way Coucou does.
        mode = session != nil || hovering ? .compact : .idle
    }

    // MARK: - Clock

    private func tick() {
        let t = Date()
        now = t
        tickCount += 1

        if let until = noticeUntil, t > until {
            notice = nil
            noticeUntil = nil
        }
        if let until = mascotLineUntil, t > until {
            mascotLine = nil
            mascotLineUntil = nil
        }
        if mode == .greeting, !hovering, let until = greetingUntil, t > until {
            greetingUntil = nil
            collapse()
        }
        if let left = closeCountdown(at: t), left <= 0, !hovering {
            if mode == .setup { closeSetup() } else { collapse() }
        }
        // A sign-in or install window is open: look again every three seconds, for ten minutes at most.
        if let since = waitingSince {
            if t.timeIntervalSince(since) > 600 {
                waitingFor = nil
                waitingSince = nil
            } else if tickCount % 3 == 0 {
                CLILocator.shared.scan()
                AIEngine.shared.refreshStatus()
            }
        }
        if mode == .nudge, !hovering, let n = nudge, t.timeIntervalSince(n.shownAt) > 8 {
            // Unanswered: fold away and stay quiet about this place for ten minutes.
            cooldown[n.target] = t.addingTimeInterval(600)
            mode = baseMode
        }

        guard var s = session else { return }
        if t >= s.deadline {
            finishSession(auto: true)
            return
        }
        if let rest = s.restUntil {
            if t >= rest {
                s.restUntil = nil
                session = s
                showNotice("Break over")
                play(.end)
                updateGlyph()
            }
            return
        }

        if tickCount % 2 == 0, let info = focus.snapshot() {
            let result = FocusWatcher.classify(info, presetAllow: s.preset.allow, config: config, tempAllow: s.tempAllow)
            if result.verdict == .distract, result.target != driftTarget {
                driftSeconds = 0
                driftTarget = result.target
            }
            lastVerdict = result.verdict
        }
        // Three minutes without touching the Mac counts as being away, not as either kind of time.
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        if idle < 180 {
            if lastVerdict == .distract {
                s.distractSeconds += 1
                driftSeconds += 1
            } else {
                s.focusSeconds += 1
                driftSeconds = 0
            }
        }
        session = s
        updateGlyph()
        maybeNudge()
    }

    private func updateGlyph() {
        let next: Glyph
        if thread?.busy == true {
            next = .thinking
        } else if let s = session {
            if s.restUntil != nil { next = .rest } else { next = lastVerdict == .distract ? .drift : .focus }
        } else {
            next = .none
        }
        if next != glyph { glyph = next }
    }

    func showNotice(_ text: String) {
        notice = text
        noticeUntil = Date().addingTimeInterval(2.5)
    }

    // MARK: - Courses and sessions

    /// A click on the folded island opens it on the home tab.
    func openHome() {
        guard !mode.isExpanded || mode == .greeting else { return }
        hoverLift = false
        focusedCourse = session?.preset.course ?? focusedCourse
        refreshMaterialCounts()
        refreshStats()
        play(.open)
        mode = .home
    }

    /// One of the tabs at the top left.
    func openTab(_ tab: IslandTab) {
        // "+" while a course is being edited goes to the new-course page.
        if tab == .add, mode == .add, editingCourse != nil {
            play(.blip)
            openNewCourse()
            return
        }
        guard mode != tab.mode else { return }
        if tab != .add {
            clearCourseDraft()
            onIslandKey?(false)
        }
        if tab == .record { refreshStats() }
        if tab == .home { refreshMaterialCounts() }
        play(.blip)
        mode = tab.mode
        if tab == .add { openNewCourse() }
    }

    /// A course pill was pressed: its card comes up on the left.
    func focus(course: String) {
        guard focusedCourse != course else { return }
        play(.blip)
        focusedCourse = course
    }

    func refreshStats() {
        let records = SessionLog.all()
        let t = Date()
        var stats = StudyStats.today(records, now: t)
        if let s = session {
            stats.minutes += s.focusSeconds / 60
            stats.questions += s.questions.count
        }
        today = stats
        var days = StudyStats.week(records, now: t)
        if let s = session, !days.isEmpty { days[days.count - 1].minutes += s.focusSeconds / 60 }
        week = days
    }

    /// The mascot was clicked: it hops and says something short.
    func patMascot() {
        mascotPat += 1
        play(.pat)
        mascotLine = MascotLines.pick(session: session, drift: glyph == .drift, todayMinutes: today.minutes,
                                      index: mascotPat)
        mascotLineUntil = Date().addingTimeInterval(2.2)
    }

    func toggleKeepInClaude() {
        config.ai.keepInClaude.toggle()
        ConfigStore.save(config)
    }

    func toggleSounds() {
        config.sounds.toggle()
        ConfigStore.save(config)
        play(.blip)
    }

    enum Sound {
        case peek, open, blip, pat, start, end

        /// Quiet macOS system sounds. Coucou's own sounds are not ours to use.
        var name: String {
            switch self {
            case .peek: return "Pop"
            case .open: return "Pop"
            case .blip: return "Tink"
            case .pat: return "Bottle"
            case .start: return "Hero"
            case .end: return "Glass"
            }
        }

        var volume: Float {
            switch self {
            case .peek: return 0.12
            case .open, .blip: return 0.2
            case .pat: return 0.25
            case .start, .end: return 0.35
            }
        }
    }

    func play(_ sound: Sound) {
        guard config.sounds, !previewMode, let s = (NSSound(named: sound.name)?.copy() as? NSSound) else { return }
        s.volume = sound.volume
        s.play()
    }

    private func refreshMaterialCounts() {
        let courses = config.courses.filter { $0 != AppConfig.generalCourse }.map { ($0, config.folders(for: $0)) }
        DispatchQueue.global(qos: .utility).async {
            var counts: [String: Int] = [:]
            for (course, folders) in courses { counts[course] = CourseStore.shared.materials(course, folders: folders).count }
            DispatchQueue.main.async { self.materialCounts = counts }
        }
    }

    func setSessionMinutes(_ minutes: Int) {
        guard config.sessionMinutes != minutes else { return }
        config.sessionMinutes = minutes
        ConfigStore.save(config)
        play(.blip)
    }

    /// Opens the course's own folder in Finder: its notes, log, cards and copied PDFs.
    func openCourseFolder(_ course: String) {
        NSWorkspace.shared.open(CourseStore.shared.dir(course))
    }

    /// "Graph" on a course's card: the course window, with how its notes connect.
    func openCourseWindow(_ course: String) {
        guard course != AppConfig.generalCourse, !previewMode else { return }
        play(.blip)
        onOpenCourse?(course)
    }

    /// Shows a linked folder or a copied PDF in Finder.
    func reveal(_ item: CourseItem) {
        guard FileManager.default.fileExists(atPath: item.url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // MARK: - The Add tab: a new course, or an existing one's files

    /// The name field was clicked: the island takes the keyboard.
    func beginAddingCourse() {
        addingCourse = true
        onIslandKey?(true)
    }

    /// Forgets everything on the Add tab that wasn't added.
    private func clearCourseDraft() {
        addingCourse = false
        newCourseName = ""
        editName = ""
        staged = []
        editingCourse = nil
        removingCourse = false
        courseItems = []
        itemsToken += 1
    }

    /// The new-course page, empty, with the name field ready.
    func openNewCourse() {
        clearCourseDraft()
        mode = .add
        beginAddingCourse()
    }

    /// The page for a course that already exists: its folders and PDFs, its name, removing it.
    func editCourse(_ course: String) {
        guard course != AppConfig.generalCourse, config.courses.contains(course) else { return }
        clearCourseDraft()
        onIslandKey?(false)
        hoverLift = false
        editingCourse = course
        editName = course
        mode = .add
        refreshItems()
        play(.blip)
    }

    /// Rebuilds the list on the Add tab (folders are counted off the main thread).
    func refreshItems() {
        guard !previewMode else { return }
        let course = editingCourse
        let picked = staged
        let folders = course.map { config.folders(for: $0) } ?? []
        itemsToken += 1
        let token = itemsToken
        DispatchQueue.global(qos: .userInitiated).async {
            let items = course.map { CourseStore.shared.items($0, folders: folders) } ?? CourseStore.items(picked)
            DispatchQueue.main.async {
                guard token == self.itemsToken else { return }
                self.courseItems = items
            }
        }
    }

    /// Pure: only PDFs and folders can belong to a course.
    static func usable(_ urls: [URL]) -> [URL] {
        urls.filter { CourseStore.isFolder($0) || $0.pathExtension.lowercased() == "pdf" }
    }

    /// Picked for the course that is being made. Nothing is copied or linked yet.
    func stage(_ urls: [URL]) {
        var known = Set(staged.map { $0.standardizedFileURL.path })
        let fresh = Self.usable(urls).filter { known.insert($0.standardizedFileURL.path).inserted }
        guard !fresh.isEmpty else { return }
        staged += fresh
        // A folder usually carries the course's name: offer it while the field is still empty.
        if newCourseName.trimmingCharacters(in: .whitespaces).isEmpty,
           let folder = fresh.first(where: { CourseStore.isFolder($0) }), config.canName(folder.lastPathComponent) {
            newCourseName = folder.lastPathComponent
        }
        play(.blip)
        refreshItems()
    }

    /// PDFs are copied into the course; folders are linked where they are. Returns how many of each.
    @discardableResult
    func add(_ urls: [URL], to course: String) -> (files: Int, folders: Int) {
        var files = 0, folders = 0
        for url in Self.usable(urls) {
            if CourseStore.isFolder(url) {
                if config.link(url.standardizedFileURL.path, to: course) { folders += 1 }
            } else if CourseStore.shared.addMaterial(url, course: course) {
                files += 1
            }
        }
        if folders > 0 { ConfigStore.save(config) }
        refreshMaterialCounts()
        refreshItems()
        let linked = config.folders(for: course)
        DispatchQueue.global(qos: .utility).async { CourseStore.shared.warm(course, folders: linked) }
        return (files, folders)
    }

    /// Pure: "2 files and 1 folder".
    static func addedWords(files: Int, folders: Int) -> String {
        [files > 0 ? counted(files, "file") : nil, folders > 0 ? counted(folders, "folder") : nil]
            .compactMap { $0 }.joined(separator: " and ")
    }

    func addCourse() {
        let name = newCourseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard config.canName(name) else {
            showNotice("There is already a course called \(name)")
            return
        }
        let picked = staged
        clearCourseDraft()
        onIslandKey?(false)
        config.presets.append(Preset(id: name, course: name, task: "", minutes: config.sessionMinutes))
        ConfigStore.save(config)
        _ = CourseStore.shared.dir(name)
        let added = add(picked, to: name)
        focusedCourse = name
        play(.blip)
        mode = .home
        let words = Self.addedWords(files: added.files, folders: added.folders)
        if !words.isEmpty { showNotice("Added \(name) with \(words)") }
    }

    /// The ✕ on a row: forget a picked one, unlink a folder, or move a copied PDF to the Trash.
    func remove(_ item: CourseItem) {
        guard let course = editingCourse else {
            staged.removeAll { $0.standardizedFileURL.path == item.url.standardizedFileURL.path }
            refreshItems()
            return
        }
        switch item.kind {
        case .folder:
            config.unlink(item.url.path, from: course)
            ConfigStore.save(config)
            showNotice("Unlinked \(item.url.lastPathComponent). The folder itself is untouched.")
        case .pdf:
            if CourseStore.shared.trashMaterial(item.url, course: course) {
                showNotice("Moved \(item.url.lastPathComponent) to the Trash")
            }
        }
        refreshMaterialCounts()
        refreshItems()
    }

    /// A copied PDF's kind, picked by hand: it moves into that kind's folder.
    func move(_ item: CourseItem, to kind: MaterialKind) {
        guard let course = editingCourse, item.kind == .pdf, item.group != kind else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let moved = CourseStore.shared.move(item.url, to: kind, course: course) != nil
            DispatchQueue.main.async {
                if moved { self.showNotice("Moved \(item.url.lastPathComponent) to \(kind.rawValue)") }
                self.refreshItems()
            }
        }
    }

    /// "Link folder" and "Add PDFs": the Mac's Open panel, then the same as a drop.
    func choose(folders: Bool) {
        guard !choosing, let onChoose else { return }
        choosing = true
        onChoose(folders) { [weak self] urls in
            guard let self else { return }
            self.choosing = false
            guard self.mode == .add, !urls.isEmpty else { return }
            self.take(urls)
        }
    }

    /// Things given to the Add page: picked for the new course, or added to the one being edited.
    private func take(_ urls: [URL]) {
        guard let course = editingCourse else { stage(urls); return }
        let added = add(urls, to: course)
        let words = Self.addedWords(files: added.files, folders: added.folders)
        if !words.isEmpty {
            showNotice("Added \(words) to \(course)")
            play(.blip)
        }
    }

    func renameCourse() {
        guard let old = editingCourse else { return }
        let new = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard new != old, !new.isEmpty else { return }
        guard config.canName(new, renaming: old) else {
            showNotice("There is already a course called \(new)")
            return
        }
        guard session?.preset.course != old else {
            showNotice("End the session before renaming")
            return
        }
        guard CourseStore.shared.rename(old, to: new) else {
            showNotice("A folder called \(new) is already there")
            return
        }
        config.rename(old, to: new)
        ConfigStore.save(config)
        SessionLog.rename(old, to: new)
        if focusedCourse == old { focusedCourse = new }
        addingCourse = false
        onIslandKey?(false)
        editingCourse = new
        editName = new
        refreshMaterialCounts()
        refreshItems()
        play(.blip)
        showNotice("Renamed to \(new)")
    }

    /// After "Remove" is confirmed: the course leaves the list and its own folder goes to the
    /// Trash. Linked folders are only unlinked.
    func removeCourse() {
        guard let course = editingCourse, course != AppConfig.generalCourse else { return }
        guard session?.preset.course != course else {
            removingCourse = false
            showNotice("End the session before removing")
            return
        }
        config.presets.removeAll { $0.course == course }
        ConfigStore.save(config)
        let trashed = CourseStore.shared.trash(course)
        if focusedCourse == course { focusedCourse = nil }
        clearCourseDraft()
        onIslandKey?(false)
        refreshMaterialCounts()
        play(.blip)
        mode = .home
        showNotice(trashed ? "Removed \(course). Its folder is in the Trash." : "Removed \(course)")
    }

    func start(course: String) {
        var preset = config.presets.first { $0.course == course }
            ?? Preset(id: course, course: course, task: "", minutes: config.sessionMinutes)
        preset.minutes = config.sessionMinutes
        start(preset)
    }

    func start(_ preset: Preset) {
        let t = Date()
        session = ActiveSession(preset: preset, start: t, deadline: t.addingTimeInterval(Double(preset.minutes) * 60))
        driftSeconds = 0
        driftTarget = ""
        cooldown = [:]
        lastVerdict = .neutral
        nudge = nil
        summary = nil
        hoverLift = false
        focusedCourse = preset.course
        // Opened without the pointer on it: it folds by itself like any other opened island.
        outsideSince = hovering ? nil : Date()
        updateGlyph()
        play(.start)
        if preset.course != AppConfig.generalCourse {
            let course = preset.course
            let linked = config.folders(for: course)
            DispatchQueue.global(qos: .utility).async { CourseStore.shared.warm(course, folders: linked) }
        }
        // With something left over from last time, stay open so it is seen; otherwise fold away.
        let stuck = SessionLog.lastStuck(course: preset.course)
        mode = stuck.isEmpty ? .compact : .home
        if !stuck.isEmpty {
            mascotLine = "You got stuck here last time"
            mascotLineUntil = Date().addingTimeInterval(4)
        }
        dlog("session start \(preset.minutes)m")
    }

    func endSession() {
        finishSession(auto: false)
    }

    /// "Switch to this course": the running session is saved and the other course starts right away.
    func switchSession(to course: String) {
        finishSession(auto: false, quietly: true)
        start(course: course)
    }

    private func finishSession(auto: Bool, quietly: Bool = false) {
        guard let s = session else { return }
        let record = SessionRecord(course: s.preset.course, task: s.preset.task, start: s.start, end: Date(),
                                   plannedMinutes: s.preset.minutes, focusSeconds: s.focusSeconds,
                                   distractSeconds: s.distractSeconds, questions: s.questions)
        SessionLog.append(record)
        summary = SessionSummary(preset: s.preset, focusMinutes: Int((Double(s.focusSeconds) / 60).rounded()),
                                 distractMinutes: Int((Double(s.distractSeconds) / 60).rounded()), questions: s.questions)
        session = nil
        nudge = nil
        hoverLift = false
        updateGlyph()
        refreshStats()
        guard !quietly else { return }
        outsideSince = hovering ? nil : Date()
        mode = .summary
        if auto { play(.end) }
        dlog("session end focus=\(s.focusSeconds)s distract=\(s.distractSeconds)s questions=\(s.questions.count)")
    }

    func startRest() {
        guard var s = session else { return }
        s.restUntil = Date().addingTimeInterval(Double(config.breakMinutes) * 60)
        // The break does not eat into the session.
        s.deadline = s.deadline.addingTimeInterval(Double(config.breakMinutes) * 60)
        session = s
        nudge = nil
        driftSeconds = 0
        lastVerdict = .neutral
        updateGlyph()
        hoverLift = false
        mode = .compact
    }

    func closeSummary() {
        collapse()
    }

    /// "Resume" during a break: back to work now; the unused break comes off the end.
    func endRest() {
        guard var s = session, let rest = s.restUntil else { return }
        s.deadline = s.deadline.addingTimeInterval(-max(0, rest.timeIntervalSinceNow))
        s.restUntil = nil
        session = s
        updateGlyph()
        play(.blip)
    }

    /// A file dragged onto the folded island opens the "Add" tab, the way Coucou opens its drop view.
    /// Something is being dragged over the folded island: open the Add tab under it. The page
    /// used a moment ago comes back; otherwise the running or picked course's, else a new course.
    func openForDrop() {
        guard !mode.isExpanded || mode == .greeting else { return }
        refreshMaterialCounts()
        play(.peek)
        hoverLift = false
        if let last = lastAdd, Date().timeIntervalSince(last.at) < 120 {
            if let course = last.course, config.courses.contains(course) { openDropPage(course) } else { openDropPage(nil) }
        } else {
            openDropPage(dropCourse)
        }
    }

    private func openDropPage(_ course: String?) {
        clearCourseDraft()
        editingCourse = course
        editName = course ?? ""
        mode = .add
        refreshItems()
    }

    // MARK: - Off-task card

    private func maybeNudge() {
        guard mode == .compact, lastVerdict == .distract, driftSeconds >= config.nudgeAfterSeconds else { return }
        if let until = cooldown[driftTarget], Date() < until { return }
        // Mid-sentence is the wrong moment. Wait until the hands stop.
        if CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) < 2 { return }
        nudge = NudgeInfo(target: driftTarget, seconds: driftSeconds, shownAt: Date())
        hoverLift = false
        mode = .nudge
    }

    func nudgeBack() {
        if let n = nudge { cooldown[n.target] = Date().addingTimeInterval(180) }
        driftSeconds = 0
        mode = baseMode
    }

    func nudgeRest() {
        startRest()
    }

    func nudgeIsStudy() {
        guard let n = nudge, var s = session else { return }
        s.tempAllow.insert(n.target)
        session = s
        let key = "\(s.preset.id)|\(n.target)"
        config.studyVotes[key, default: 0] += 1
        if config.studyVotes[key, default: 0] >= 3,
           let index = config.presets.firstIndex(where: { $0.id == s.preset.id }),
           !config.presets[index].allow.contains(n.target) {
            config.presets[index].allow.append(n.target)
            showNotice("Always allowed")
        }
        ConfigStore.save(config)
        lastVerdict = .neutral
        driftSeconds = 0
        updateGlyph()
        mode = baseMode
    }

    // MARK: - Question popup

    /// Opens the popup next to `point` with whatever the question is about.
    func openPopup(quote: String?, image: String?, at point: CGPoint?) {
        AIEngine.shared.cancel()
        runToken += 1
        let front = focus.snapshot(withURL: false)
        thread = AskThread(quote: quote, imagePath: image, sourceApp: front?.appName ?? "", sourceTitle: front?.title ?? "")
        selectedPreset = nil
        askText = ""
        answerHeight = 40
        popupAnchor = point ?? NSEvent.mouseLocation
        popupVisible = true
        updateGlyph()
    }

    func closePopup() {
        AIEngine.shared.cancel()
        runToken += 1
        thread = nil
        selectedPreset = nil
        askText = ""
        onPopupKey?(false)
        popupVisible = false
        updateGlyph()
    }

    /// The button on top of the right-click menu was pressed. The menu is closing; once it has,
    /// read what is selected and open the popup where the click was.
    func askFromRightClick(at point: CGPoint) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self else { return }
            self.selection.grabNow { text in
                self.openPopup(quote: text, image: nil, at: point)
            }
        }
    }

    /// "Ask" on the island: take whatever is selected right now.
    func manualAsk() {
        if mode.isExpanded { collapse() }
        selection.grabNow { [weak self] text in
            self?.openPopup(quote: text, image: nil, at: nil)
        }
    }

    /// "Capture and ask": fold away first so the island is not in the picture.
    func captureAsk() {
        collapse()
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        shots.captureRegion { [weak self] path in
            guard let self else { return }
            if let path {
                self.openPopup(quote: nil, image: path, at: nil)
            } else {
                self.showNotice("Capture cancelled")
            }
        }
    }

    private func shotArrived(_ path: String) {
        // While an answer is being written, a new screenshot does not interrupt it.
        if thread?.busy == true { return }
        openPopup(quote: nil, image: path, at: nil)
    }

    func togglePreset(_ preset: AskPreset) {
        selectedPreset = selectedPreset == preset ? nil : preset
    }

    /// "Send": the picked preset, what was typed, or both.
    func send() {
        guard thread != nil, thread?.busy != true,
              let composed = Prompts.compose(preset: selectedPreset, extra: askText) else { return }
        let words = askText.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedPreset = nil
        askText = ""
        onPopupKey?(false)
        ask(prompt: composed.prompt, display: composed.display, typed: words)
    }

    func retry() {
        guard let t = thread, !t.prompt.isEmpty else { return }
        ask(prompt: t.prompt, display: t.question)
    }

    /// `typed` is nil for a retry: the same question again, so nothing new was typed.
    func ask(prompt: String, display: String, typed: String? = nil) {
        guard var t = thread else { return }
        if let typed { t.typed = typed }
        AIEngine.shared.cancel()
        runToken += 1
        let token = runToken
        if !t.answer.isEmpty { t.history.append((q: t.question, a: t.answer)) }
        t.question = display
        t.prompt = prompt
        t.answer = ""
        t.error = nil
        t.errorAction = nil
        answerHeight = 40

        // Nothing to explain: no picked text, no screenshot, nothing typed, no earlier answer.
        // Don't send an empty question; say what is missing.
        let hasSource = !(t.quote ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || t.imagePath != nil || !t.history.isEmpty || !(typed ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasSource {
            t.busy = false
            t.status = nil
            if accessibilityGranted {
                t.error = "Couldn’t read the text you picked in this app. Take a screenshot of it instead, or type your question."
                t.errorAction = .retry
            } else {
                t.error = "StudyNotch can’t read the text you pick yet. Turn it on under Accessibility in System Settings, then pick the text again."
                t.errorAction = .accessibility
            }
            thread = t
            return
        }

        guard let kind = activeAI else {
            t.busy = false
            t.status = nil
            if let chosen = connectedAI {
                t.error = "\(chosen.label) isn’t signed in anymore. Sign in again, or connect another AI. StudyNotch never switches on its own."
            } else {
                t.error = "No AI is connected yet. Connect Claude, ChatGPT or Gemini first."
            }
            t.errorAction = .setupAI
            thread = t
            return
        }
        let course = session?.preset.course ?? ""
        let settings = config.ai
        let account = connectedAccount
        // Claude with the Mac's sign-in: the question is kept as a Claude Code session in the
        // course's folder, and the Claude app gets it after the first answer. A follow-up
        // continues the same session, so the earlier questions aren't sent again.
        var claude: ClaudeSession?
        if kind == .claudeCLI, account == .mac, settings.keepInClaude, !previewMode {
            let resume = t.inClaude && t.claudeSession != nil
            let id = resume ? t.claudeSession! : UUID().uuidString.lowercased()
            t.claudeSession = id
            t.claudeCourse = course.isEmpty ? AppConfig.generalCourse : course
            claude = ClaudeSession(id: id, folder: "", name: ClaudeSession.name(question: display, quote: t.quote), resume: resume)
        } else {
            t.claudeSession = nil
            t.inClaude = false
        }
        t.busy = true
        t.status = "Looking in your files"
        thread = t
        updateGlyph()

        let linked = config.folders(for: course)
        // A connection test that is still running gives way to a real question.
        testToken += 1
        if test == .running { test = .idle }
        let snapshot = t
        DispatchQueue.global(qos: .userInitiated).async {
            var located: Located?
            var note = ""
            var files: CourseFiles?
            var kinds: [(kind: MaterialKind, names: [String])] = []
            var memory: [String] = []
            if !course.isEmpty, course != AppConfig.generalCourse {
                // What every question in the course shares, like a project: its notes, its memory,
                // its files by kind.
                note = CourseStore.shared.note(course)
                memory = CourseStore.shared.memory(course)
                // The course is the AI's project: its PDFs, as text and as copies, in folders it may open.
                // The API key has no way to open files; it gets the matching page only.
                let project = CourseStore.shared.syncText(course, folders: linked)
                if kind != .apiKey {
                    files = project
                    if project != nil {
                        kinds = CourseStore.shared.byKind(course, folders: linked).map { ($0.kind, $0.pdfs.map(\.lastPathComponent)) }
                    }
                }
                if let quote = snapshot.quote {
                    located = CourseStore.shared.locate(quote, course: course, hint: snapshot.sourceTitle, folders: linked)
                }
            }
            if claude != nil {
                claude?.folder = CourseStore.shared.dir(snapshot.claudeCourse).path
            }
            let continuing = claude?.resume ?? false
            let text = Prompts.user(course: course, note: note, located: located, quote: snapshot.quote,
                                    hasImage: snapshot.imagePath != nil, sourceApp: snapshot.sourceApp,
                                    sourceTitle: snapshot.sourceTitle, history: continuing ? [] : snapshot.history,
                                    question: prompt, files: files, kinds: kinds, memory: memory)
            let language = Prompts.answerLanguage(typed: snapshot.typed)
            let request = AIRequest(system: Prompts.system(language: language), prompt: text,
                                    imagePath: snapshot.imagePath, model: AIEngine.model(settings.model, for: kind),
                                    folders: files?.folders ?? [], session: claude)
            DispatchQueue.main.async {
                guard token == self.runToken else { return }
                self.thread?.status = located.map { "Found it in \($0.file) p.\($0.page), writing" } ?? "Writing"
                dlog("ask via \(kind.rawValue) located=\(located != nil) image=\(snapshot.imagePath != nil)")
                AIEngine.shared.run(request, kind: kind, account: account) { event in
                    self.handle(event, token: token, course: course)
                }
            }
        }
    }

    private func handle(_ event: AIEvent, token: Int, course: String) {
        guard token == runToken, thread != nil else { return }
        switch event {
        case .delta(let text):
            thread?.answer += text
            thread?.status = nil
        case .replace(let text):
            thread?.answer = text
            thread?.status = nil
        case .status(let text):
            thread?.status = text
        case .done:
            thread?.busy = false
            thread?.status = nil
            guard let t = thread else { break }
            if t.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                thread?.error = "The answer came back empty. Try again."
                thread?.errorAction = .retry
                break
            }
            let label = t.quote.map { "\(t.question): \($0.prefix(60))" } ?? t.question
            session?.questions.append(label.replacingOccurrences(of: "\n", with: " "))
            let logCourse = course.isEmpty ? AppConfig.generalCourse : course
            DispatchQueue.global(qos: .utility).async {
                CourseStore.shared.appendLog(course: logCourse, quote: t.quote, question: t.question, answer: t.answer)
                if logCourse != AppConfig.generalCourse {
                    CourseStore.shared.remember(course: logCourse, line: CourseStore.memoryLine(date: Date(), question: t.question,
                                                                                               quote: t.quote, answer: t.answer))
                }
            }
            // The first answer: the conversation goes into the Claude app's list, behind other windows.
            if let id = t.claudeSession, !t.inClaude {
                thread?.inClaude = true
                ClaudeApp.keep(id)
            }
            dlog("ask done")
        case .failed(let message):
            thread?.busy = false
            thread?.status = nil
            thread?.error = message
            thread?.errorAction = .retry
            // A session that never got its first answer isn't handed over; trying again starts a new one.
            if thread?.inClaude == false { thread?.claudeSession = nil }
            dlog("ask failed")
        }
        updateGlyph()
    }

    /// The question window's conversation, in the Claude app, in front.
    func openInClaude() {
        guard let t = thread, t.inClaude, let id = t.claudeSession else { return }
        ClaudeApp.show(id)
    }

    func saveCard() {
        guard let t = thread, !t.answer.isEmpty else { return }
        let course = session?.preset.course ?? AppConfig.generalCourse
        CourseStore.shared.appendCard(course: course, front: t.quote ?? t.question, back: t.answer)
        showNotice("Saved as a review card")
    }

    // MARK: - Setup

    enum SetupStep { case ai, permissions }

    /// Opens the setup card at a step: the one asked for, else the AI step when nothing can
    /// answer, else permissions when one is missing.
    func openSetup(step: SetupStep? = nil) {
        refresh += 1
        CLILocator.shared.scan()
        AIEngine.shared.refreshStatus()
        setupStep = step ?? (activeAI == nil ? .ai : (accessibilityGranted ? .ai : .permissions))
        confirming = nil
        if test != .running { test = .idle }
        hoverLift = false
        addingCourse = false
        onIslandKey?(false)
        outsideSince = hovering ? nil : Date()
        mode = .setup
    }

    func closeSetup() {
        UserDefaults.standard.set(true, forKey: "didOnboard")
        confirming = nil
        waitingFor = nil
        waitingSince = nil
        collapse()
    }

    /// True on the very first launch, until "Get started".
    var firstRun: Bool { previewMode ? previewFirstRun : !UserDefaults.standard.bool(forKey: "didOnboard") }

    /// Pure: what a choice's tile says and does. `ready` is signed in (on this Mac, or with
    /// StudyNotch's own sign-in) but not connected: it answers nothing until the student says "Connect".
    enum AIChoiceState: Equatable { case connected, ready, signIn, checking, get, waiting }

    /// The AI the student connected (whether or not it can answer right now).
    var connectedAI: AIKind? {
        if previewMode, previewChoices != nil { return previewActive }
        return AIKind(rawValue: config.ai.provider)
    }

    /// Whose sign-in the connected AI uses: the Mac's, or one kept only for StudyNotch.
    var connectedAccount: AIAccount {
        if previewMode, previewChoices != nil { return previewOwn ? .own : .mac }
        return AIAccount(rawValue: config.ai.account) ?? .mac
    }

    /// The sign-in a tile stands for: the connected one's; otherwise StudyNotch's own when it has
    /// one, else the Mac's.
    func tileAccount(_ kind: AIKind) -> AIAccount {
        if connectedAI == kind { return connectedAccount }
        if previewMode, previewChoices != nil { return .mac }
        return kind.hasOwnAccount && AIEngine.shared.isSignedIn(kind, account: .own) == true ? .own : .mac
    }

    func choiceState(_ kind: AIKind) -> AIChoiceState {
        if previewMode, let p = previewChoices { return p[kind] ?? .get }
        let engine = AIEngine.shared
        if waitingFor == kind, !(engine.installed(kind) && engine.isSignedIn(kind, account: waitingAccount) == true) { return .waiting }
        return Self.choiceState(installed: engine.installed(kind), signedIn: engine.isSignedIn(kind, account: tileAccount(kind)),
                                connected: connectedAI == kind)
    }

    static func choiceState(installed: Bool, signedIn: Bool?, connected: Bool) -> AIChoiceState {
        guard installed else { return .get }
        switch signedIn {
        case .some(true): return connected ? .connected : .ready
        case .some(false): return .signIn
        case .none: return .checking
        }
    }

    /// Which account a tile would use ("name@school.edu · Max"), when its tool says.
    func account(_ kind: AIKind) -> String? {
        if previewMode { return kind == confirming || kind == previewActive ? previewAccount : nil }
        return AIEngine.shared.account(kind, tileAccount(kind))
    }

    /// The student said "Connect": from now on questions go to this one, and only this one.
    func connect(_ kind: AIKind, account: AIAccount? = nil) {
        let account = account ?? tileAccount(kind)
        confirming = nil
        test = .idle
        config.ai.provider = kind.rawValue
        config.ai.account = (kind.hasOwnAccount ? account : .mac).rawValue
        ConfigStore.save(config)
        refresh += 1
        play(.blip)
        mascotPat += 1
        dlog("ai connected: \(kind.rawValue) account=\(config.ai.account)")
    }

    /// Nothing answers until another one is connected. A sign-in kept only for StudyNotch is
    /// signed out with it; the Mac's own sign-ins are never touched.
    func disconnect() {
        confirming = nil
        test = .idle
        testToken += 1
        guard let kind = connectedAI else { return }
        let own = connectedAccount == .own
        dlog("ai disconnected: \(kind.rawValue)")
        config.ai.provider = ""
        config.ai.account = AIAccount.mac.rawValue
        ConfigStore.save(config)
        refresh += 1
        if own { AIEngine.shared.signOutOwn(kind) { [weak self] in self?.refresh += 1 } }
    }

    /// "Another account": the tool's own sign-in page, kept only for StudyNotch, so the Claude or
    /// ChatGPT app stays signed in as it was. The connection in use keeps answering until the new
    /// sign-in is done.
    func useAnotherAccount(_ kind: AIKind) {
        confirming = nil
        test = .idle
        if kind.hasOwnAccount {
            AIEngine.shared.signOutOwn(kind) { [weak self] in self?.signIn(kind) }
        } else if kind == .geminiCLI, let path = CLILocator.shared.path("agy") {
            // `agy` has one Google sign-in for the whole Mac: sign out inside it, then sign in again.
            let hint = "To use another Google account: type /logout and press Return. Then start agy again here and sign in with the other account."
            runInTerminal(name: "switch-agy", hint: hint, lines: [Self.shellQuoted(path)])
        }
    }

    /// The one being waited for is ready.
    private func checkWaiting() {
        guard let kind = waitingFor else { return }
        let engine = AIEngine.shared
        guard engine.installed(kind), engine.isSignedIn(kind, account: waitingAccount) == true else { return }
        let account = waitingAccount
        waitingFor = nil
        waitingSince = nil
        if account == .own || kind == .geminiCLI {
            // The student signed in from this tile, for StudyNotch: that is the connect.
            connect(kind, account: account)
        } else {
            // The Claude or ChatGPT app was just installed and signed in: still ask, with the account.
            confirming = kind
            play(.blip)
        }
    }

    private func wait(for kind: AIKind, account: AIAccount = .mac) {
        waitingFor = kind
        waitingAccount = account
        waitingSince = Date()
        outsideSince = nil
    }

    // MARK: - Connection test

    enum TestState: Equatable { case idle, running, passed(String), failed(String) }

    static let testSystem = "This is a connection test from a study app. Follow the instruction exactly and add nothing else."
    static let testPrompt = "Reply with exactly these three words: Connected to StudyNotch"

    /// Sends one real, tiny question to the connected AI, the same way a study question goes, and
    /// shows what came back. It uses the student's account, so it only runs when they press it.
    func testConnection() {
        guard let kind = activeAI, thread?.busy != true, test != .running else { return }
        let account = connectedAccount
        test = .running
        testToken += 1
        let token = testToken
        let began = Date()
        var reply = ""
        let request = AIRequest(system: Self.testSystem, prompt: Self.testPrompt, imagePath: nil,
                                model: AIEngine.model(config.ai.model, for: kind))
        AIEngine.shared.run(request, kind: kind, account: account) { [weak self] event in
            guard let self, token == self.testToken else { return }
            switch event {
            case .delta(let text): reply += text
            case .replace(let text): reply = text
            case .status: break
            case .done:
                let seconds = Date().timeIntervalSince(began)
                self.test = .passed(Self.testLine(kind: kind, seconds: seconds, reply: reply))
                dlog("ai test \(kind.rawValue) ok \(String(format: "%.1f", seconds))s")
                self.play(.blip)
            case .failed(let message):
                self.test = .failed("\(kind.label) didn’t answer: \(message)")
                dlog("ai test \(kind.rawValue) failed")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in
            guard let self, token == self.testToken, self.test == .running else { return }
            AIEngine.shared.cancel()
            self.test = .failed("\(kind.label) didn’t answer in 90 seconds.")
        }
    }

    /// Pure: what a passed test says. The reply is the AI's own words, cut short.
    static func testLine(kind: AIKind, seconds: Double, reply: String) -> String {
        let words = reply.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let short = words.count > 44 ? String(words.prefix(44)) + "…" : words
        return "Real answer from \(kind.label) in \(String(format: "%.1f", seconds)) s: “\(short)”"
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh += 1
    }

    /// System Settings › Privacy & Security › Accessibility.
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
        refresh += 1
    }

    /// A tile was clicked. Signed in already: ask "Connect …?" first, with the account. Signed
    /// out: its own sign-in, and it connects when that is done. Not on this Mac: get it. Nothing
    /// is connected without the student's say.
    func chooseAI(_ kind: AIKind) {
        if kind == .apiKey { onAskAPIKey?(); return }
        switch choiceState(kind) {
        case .connected, .checking, .waiting: confirming = nil
        case .ready: confirming = confirming == kind ? nil : kind
        case .signIn: confirming = nil; signIn(kind)
        case .get: confirming = nil; install(kind)
        }
    }

    /// Gets a tool that isn't on this Mac: Gemini's `agy` installs in a Terminal window and goes
    /// straight on to its sign-in; the Claude and ChatGPT apps open their download pages.
    func install(_ kind: AIKind) {
        if let lines = kind.installLines(brew: CLILocator.brew()) {
            let hint = "Installing Google's Antigravity CLI (agy) for Gemini. Then sign in with your Google account in the browser that opens; when agy shows its prompt, close this window."
            if runInTerminal(name: "install-\(kind.tool ?? "ai")", hint: hint, lines: lines) {
                wait(for: kind)
            }
        } else if let url = kind.getURL {
            NSWorkspace.shared.open(url)
            wait(for: kind)
        }
    }

    /// The tool's own sign-in, in a Terminal window; the browser opens on its sign-in page. Claude
    /// and ChatGPT sign in to a place kept only for StudyNotch, so any account can be used and the
    /// apps stay as they were. StudyNotch never sees the password.
    func signIn(_ kind: AIKind) {
        guard let tool = kind.tool, let path = CLILocator.shared.path(tool) else {
            if kind == .apiKey { onAskAPIKey?() } else { install(kind) }
            return
        }
        let account: AIAccount = kind.hasOwnAccount ? .own : .mac
        let environment = AIEngine.environment(kind, account)
        for folder in environment.values {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        }
        let lines = Self.signInLines(path: path, arguments: kind.signInArguments(), environment: environment)
        if runInTerminal(name: "sign-in-\(tool)", hint: kind.signInHint, lines: lines) {
            wait(for: kind, account: account)
        }
    }

    /// Pure: the sign-in command, after the lines that point it at StudyNotch's own sign-in.
    static func signInLines(path: String, arguments: [String], environment: [String: String]) -> [String] {
        environment.sorted { $0.key < $1.key }.map { "export \($0.key)=\(shellQuoted($0.value))" }
            + [([path] + arguments).map(shellQuoted).joined(separator: " ")]
    }

    static func shellQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Pure: a small zsh script that says what is happening, then runs the lines in our own empty
    /// folder (so no tool picks up a project's instructions).
    static func terminalScript(hint: String, folder: String, lines: [String]) -> String {
        (["#!/bin/zsh", "cd \(shellQuoted(folder)) || exit 1", "echo \(shellQuoted(hint))", "echo"] + lines).joined(separator: "\n") + "\n"
    }

    /// Writes ~/StudyNotch/.run/<name>.command and opens it in Terminal.
    @discardableResult
    private func runInTerminal(name: String, hint: String, lines: [String]) -> Bool {
        Paths.ensure()
        let script = Paths.runDir.appendingPathComponent("\(name).command")
        let body = Self.terminalScript(hint: hint, folder: Paths.runDir.path, lines: lines)
        do {
            try body.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            openInTerminal(script)
            return true
        } catch {
            dlog("terminal script failed: \(error.localizedDescription)")
            return false
        }
    }

    /// notch | main | mouse. The island controller moves the island when this changes.
    func setDisplay(_ value: String) {
        config.display = value
        ConfigStore.save(config)
    }

    func toggleOfferOutsideSession() {
        config.offerOutsideSession.toggle()
        ConfigStore.save(config)
    }

    func reloadConfig() {
        config = ConfigStore.load()
        showNotice("Settings reloaded")
    }

    /// Where a dropped PDF goes: the running session's course, else the course picked on the home tab.
    var dropCourse: String? {
        guard let course = session?.preset.course ?? shownCourse, course != AppConfig.generalCourse else { return nil }
        return course
    }

    /// PDFs or folders dropped on the island. On the new-course page they wait for "Add"; on a
    /// course's page (or with a course running or picked) they go into that course; with no course
    /// at all they start a new one.
    func addDropped(_ urls: [URL]) {
        guard !Self.usable(urls).isEmpty else {
            showNotice("Only PDFs and folders can be added")
            return
        }
        if mode == .add {
            take(urls)
        } else if let course = dropCourse {
            let added = add(urls, to: course)
            let words = Self.addedWords(files: added.files, folders: added.folders)
            if !words.isEmpty {
                showNotice("Added \(words) to \(course)")
                play(.blip)
            }
        } else {
            openNewCourse()
            stage(urls)
        }
    }
}
