import AppKit
import SwiftUI

/// `StudyNotch --uitest`: starts the real app with a throw-away home folder, opens the real island
/// window and clicks through the AI connection card with mouse events sent to that window. Each
/// button is found by its words (`testTag`), where it really is in the window.
///
/// It sends two real questions (one to Claude, one to ChatGPT) through the accounts signed in on
/// this Mac, so it is run by hand, never by --selftest. The user's own settings and StudyNotch's
/// own sign-ins are not touched: everything is written under the throw-away folder, and sign-in
/// windows are recorded instead of opened.
enum UITest {
    static var active: Bool { CommandLine.arguments.contains("--uitest") || coursesOnly || eyesOnly || graphOnly }
    /// `--uitest-graph`: the course window, from the Graph button to a picked theorem's page.
    static var graphOnly: Bool { CommandLine.arguments.contains("--uitest-graph") }
    /// `--uitest-eyes`: measures, in the real window, how far the mascot's eyes move with the pointer.
    /// The pointer's direction is set by the test, so the real pointer is left alone.
    static var eyesOnly: Bool { CommandLine.arguments.contains("--uitest-eyes") }
    /// `--uitest-courses`: only the Add tab, which sends no question to any AI.
    static var coursesOnly: Bool { CommandLine.arguments.contains("--uitest-courses") }

    /// Before anything reads a path: a home of its own.
    static func prepare() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("studynotch-uitest-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.removeItem(at: home)
        Paths.root = home
        Paths.ensure()
        UserDefaults.standard.removeObject(forKey: "didOnboard")
        print("uitest home: \(home.path)")
    }

    private static var failures = 0
    private static var opened: [URL] = []

    private static func check(_ name: String, _ ok: Bool) {
        if !ok { failures += 1 }
        print("\(ok ? "PASS" : "FAIL")  \(name)")
        fflush(stdout)
    }

    @MainActor
    static func run(model: AppModel) {
        model.openInTerminal = { opened.append($0) }
        // Nothing from a test goes to the real Trash.
        CourseStore.trasher = { (try? FileManager.default.removeItem(at: $0)) != nil }
        Task { @MainActor in
            if eyesOnly {
                await driveEyes(model)
            } else if graphOnly {
                await driveGraph(model)
            } else {
                if !coursesOnly { await drive(model) }
                await driveCourses(model)
            }
            print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
            fflush(stdout)
            try? FileManager.default.removeItem(at: Paths.root)
            exit(failures == 0 ? 0 : 1)
        }
    }

    // MARK: - Finding and clicking

    /// The island's window (the question window is the same kind of panel; it is the smaller one).
    private static var window: NSWindow? {
        NSApp.windows.first { $0 is IslandPanel && $0.frame.size == IslandController.canvas }
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
    }

    /// A real mouse press and release in the island window (or `target`), in the middle of the
    /// button with these words.
    @MainActor
    private static func click(_ name: String, in target: NSWindow? = nil) async -> Bool {
        guard let window = target ?? window, let content = window.contentView, let frame = TestTags.frames[name] else {
            print("      no “\(name)” on screen; there is: \(TestTags.frames.keys.sorted().joined(separator: " | "))")
            return false
        }
        // SwiftUI measures from the top left of the window's content; AppKit from the bottom left.
        return await press(NSPoint(x: frame.midX, y: content.bounds.height - frame.midY), in: window)
    }

    /// A real mouse press and release at a point of a window (AppKit's coordinates).
    @MainActor
    private static func press(_ point: NSPoint, in window: NSWindow) async -> Bool {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                 context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)
            else { return false }
            window.sendEvent(event)
            await pause(0.08)
        }
        await pause(0.45)
        return true
    }

    @MainActor
    private static func wait(_ seconds: Double, until done: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if done() { return true }
            await pause(0.2)
        }
        return done()
    }

    // MARK: - The walk through the card

    @MainActor
    private static func drive(_ model: AppModel) async {
        _ = await wait(6) { model.mode == .setup && window != nil }
        check("first launch opens at the AI step, nothing connected", model.mode == .setup && model.setupStep == .ai && model.connectedAI == nil)

        _ = await wait(40) { AIKind.choices.allSatisfy { model.choiceState($0) != .checking } }
        let states = AIKind.choices.map { "\($0.label)=\(model.choiceState($0))" }.joined(separator: " ")
        print("      tiles: \(states)")
        check("the window has its buttons", TestTags.frames["Claude tile"] != nil && TestTags.frames["Check again"] != nil)

        for kind in [AIKind.claudeCLI, .codexCLI] where model.choiceState(kind) == .ready {
            let name = kind.label
            check("\(name): the account it would use is shown", model.account(kind)?.contains("@") == true)

            _ = await click("\(name) tile")
            check("\(name): a click on the tile asks first, connects nothing", model.confirming == kind && model.connectedAI == nil)

            _ = await click("Cancel")
            check("\(name): Cancel leaves it unconnected", model.confirming == nil && model.connectedAI == nil)

            _ = await click("\(name) tile")
            _ = await click("Connect")
            let saved = ConfigStore.load().ai
            check("\(name): Connect connects it with this Mac's account, and saves that",
                  model.connectedAI == kind && model.activeAI == kind && saved.provider == kind.rawValue && saved.account == "mac")
            check("\(name): its tile says Connected", model.choiceState(kind) == .connected)

            _ = await click("Test connection")
            check("\(name): Test connection starts a real question", model.test == .running)
            _ = await wait(95) { model.test != .running }
            if case .passed(let line) = model.test {
                check("\(name): a real answer came back", line.contains("StudyNotch"))
                print("      \(line)")
            } else {
                check("\(name): a real answer came back", false)
                print("      \(SetupPage.aiLine(model.test))")
            }

            opened.removeAll()
            _ = await click("Another account")
            _ = await wait(15) { !opened.isEmpty }
            let script = opened.first.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
            let own = AIEngine.environment(kind, .own)
            check("\(name): Another account opens its sign-in, kept apart from this Mac's",
                  model.waitingFor == kind && !own.isEmpty && own.allSatisfy { script.contains("export \($0.key)='\($0.value)'") }
                    && script.contains(kind.signInArguments().map { "'\($0)'" }.joined(separator: " ")))
            check("\(name): the connected account keeps answering while the new sign-in waits", model.activeAI == kind)
            check("\(name): its tile says Finish signing in", model.choiceState(kind) == .waiting)
            // Nobody signs in during the test: stop waiting, the way ten quiet minutes would.
            model.waitingFor = nil
            await pause(0.3)

            _ = await click("Disconnect")
            check("\(name): Disconnect stops it; nothing answers", model.connectedAI == nil && model.activeAI == nil && ConfigStore.load().ai.provider.isEmpty)
        }

        _ = await click("Step 2")
        check("the Permissions step opens", model.setupStep == .permissions)
        _ = await click("Back")
        check("Back returns to the AI step", model.setupStep == .ai)
    }

    // MARK: - The walk through the Add tab

    @MainActor
    private static func driveCourses(_ model: AppModel) async {
        let fm = FileManager.default
        let shelf = Paths.root.appendingPathComponent("Shelf", isDirectory: true)
        let folder = shelf.appendingPathComponent("STAT 230", isDirectory: true)
        let second = shelf.appendingPathComponent("Old exams", isDirectory: true)
        for directory in [folder, second] { try? fm.createDirectory(at: directory, withIntermediateDirectories: true) }
        for name in ["STAT 230/Lecture 1.pdf", "STAT 230/Lecture 2.pdf", "Old exams/2024.pdf", "Formula sheet.pdf"] {
            fm.createFile(atPath: shelf.appendingPathComponent(name).path, contents: Data("x".utf8))
        }
        let sheet = shelf.appendingPathComponent("Formula sheet.pdf")
        // The Mac's Open panel can't be clicked from here: it answers with these.
        model.onChoose = { folders, done in done(folders ? [second] : [sheet]) }

        if model.mode == .setup { model.closeSetup() }
        await pause(0.6)
        model.openHome()
        _ = await wait(4) { TestTags.frames["Tab Add courses and files"] != nil }

        _ = await click("Tab Add courses and files")
        check("Add tab: opens on a new course, with nothing picked", model.mode == .add && model.editingCourse == nil && model.staged.isEmpty)

        // A drop arrives here exactly as SwiftUI hands it over.
        model.addDropped([folder])
        _ = await wait(4) { TestTags.frames["Remove STAT 230"] != nil }
        check("new course: a dropped folder waits in the list and offers its name",
              model.staged == [folder] && model.newCourseName == "STAT 230" && model.courseItems.first?.count == 2)

        _ = await click("Add PDFs")
        _ = await wait(4) { TestTags.frames["Remove Formula sheet.pdf"] != nil }
        check("new course: Add PDFs picks a PDF too", model.staged.count == 2 && !model.choosing)

        _ = await click("Remove Formula sheet.pdf")
        check("new course: ✕ takes a picked one back out", model.staged == [folder])

        _ = await click("Header Close")
        check("new course: closed without Add, everything picked is gone and no course was made",
              model.staged.isEmpty && model.newCourseName.isEmpty && model.config.courses == ["General"] && !model.mode.isExpanded
              && !fm.fileExists(atPath: CourseStore.shared.path("STAT 230").path))

        model.openHome()
        _ = await wait(4) { TestTags.frames["Tab Add courses and files"] != nil }
        _ = await click("Tab Add courses and files")
        model.addDropped([folder, sheet])
        _ = await wait(4) { TestTags.frames["Remove Formula sheet.pdf"] != nil }
        _ = await click("Add")
        let linked = model.config.folders(for: "STAT 230")
        check("new course: Add makes the course, links the folder and copies the PDF",
              model.config.courses == ["General", "STAT 230"] && linked == [folder.standardizedFileURL.path]
              && CourseStore.shared.ownMaterials("STAT 230").map(\.lastPathComponent) == ["Formula sheet.pdf"]
              && model.mode == .home && fm.fileExists(atPath: folder.appendingPathComponent("Lecture 1.pdf").path))
        _ = await wait(4) { model.materialCounts["STAT 230"] == 3 }
        check("home: the course counts its own PDF and the folder's", model.materialCounts["STAT 230"] == 3)

        _ = await wait(3) { TestTags.frames["Edit course"] != nil }
        _ = await click("Edit course")
        check("edit: the Edit button opens the course's page", model.mode == .add && model.editingCourse == "STAT 230")

        _ = await click("Link folder")
        _ = await wait(4) { TestTags.frames["Remove Old exams"] != nil }
        check("edit: Link folder links a second folder", model.config.folders(for: "STAT 230").count == 2)

        _ = await click("Remove Old exams")
        check("edit: ✕ unlinks it; the folder and its PDF stay",
              model.config.folders(for: "STAT 230") == linked && fm.fileExists(atPath: second.appendingPathComponent("2024.pdf").path))

        _ = await click("Remove Formula sheet.pdf")
        check("edit: ✕ on the copied PDF removes it from the course; the original stays",
              CourseStore.shared.ownMaterials("STAT 230").isEmpty && fm.fileExists(atPath: sheet.path))

        model.editName = "STAT 231"
        await pause(0.3)
        _ = await click("Rename")
        check("edit: Rename renames the course and keeps its folder link",
              model.config.courses == ["General", "STAT 231"] && model.editingCourse == "STAT 231" && model.config.folders(for: "STAT 231") == linked)

        _ = await click("Remove course")
        check("edit: Remove course asks first", model.removingCourse && model.config.courses.count == 2)
        _ = await click("Cancel")
        check("edit: Cancel keeps the course", !model.removingCourse && model.config.courses.count == 2)
        _ = await click("Remove course")
        _ = await click("Remove")
        check("edit: Remove takes the course away; the linked folder is untouched",
              model.config.courses == ["General"] && model.mode == .home && ConfigStore.load().courses == ["General"]
              && fm.fileExists(atPath: folder.appendingPathComponent("Lecture 2.pdf").path))
    }

    // MARK: - The course window

    @MainActor
    private static func driveGraph(_ model: AppModel) async {
        let fm = FileManager.default
        let course = "MATH 237"
        let shelf = Paths.root.appendingPathComponent("Shelf/MATH 237", isDirectory: true)
        try? fm.createDirectory(at: shelf, withIntermediateDirectories: true)
        // A cover page first, so a theorem's page is page 2, not just the first.
        for note in DevTools.sampleNotes() {
            DevTools.makePDF(at: shelf.appendingPathComponent(note.file), pages: ["MATH 237 lecture notes"] + note.pages)
        }
        let quiz = Paths.root.appendingPathComponent("Shelf/Quiz 1.pdf")
        DevTools.makePDF(at: quiz, pages: ["Quiz 1. Classify the critical points with the Second Derivative Test."])
        if model.mode == .setup { model.closeSetup() }
        await pause(0.6)
        model.config.presets.append(Preset(id: course, course: course, task: "", minutes: 50))
        _ = model.config.link(shelf.standardizedFileURL.path, to: course)
        ConfigStore.save(model.config)
        CourseStore.shared.addMaterial(quiz, course: course)
        model.focusedCourse = course
        model.openHome()
        _ = await wait(4) { TestTags.frames["Course graph"] != nil }
        _ = await click("Course graph")

        var courseWindow: NSWindow? { NSApp.windows.first { $0.title == course && $0.isVisible } }
        var state: CourseWindowState? { (courseWindow?.contentView as? NSHostingView<CourseWindowView>)?.rootView.state }
        _ = await wait(15) { state?.graph != nil && state?.loading == false }
        check("graph: the Graph button on the course's card opens its window", courseWindow != nil)
        check("graph: the linked notes become dots and lines (\(state?.graph?.nodes.count ?? 0) dots, \(state?.graph?.edges.count ?? 0) lines)",
              state?.graph?.nodes.count == 27 && state?.graph?.edges.count == 36)
        check("graph: its files are grouped by kind", state?.files.map(\.kind) == [.lectureNotes, .quizzes])

        guard let w = courseWindow, let content = w.contentView, let graph = state?.graph,
              let node = graph.node("Lecture 7-8.pdf#Theorem 4.3") else {
            check("graph: the Second Derivative Test is a dot", false)
            return
        }
        await pause(0.5)
        // Where the pane draws it: the graph fills the window left of the 340pt side pane, under the 52pt header.
        let width = content.bounds.width - 340, height = content.bounds.height - 52
        let x = 24 + node.x * (width - 48), y = 52 + 12 + node.y * (height - 64)
        _ = await press(NSPoint(x: x, y: content.bounds.height - y), in: w)
        check("graph: clicking a dot picks it", state?.selected == node.id)
        _ = await wait(4) { PagePreview.lastShown == "\(node.path)#\(node.page)" }
        check("graph: beside it, the theorem's own page (\(node.file) p.\(node.page))",
              node.page == 2 && PagePreview.lastShown == "\(node.path)#\(node.page)")
        // A picture of the real window, to look at.
        if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: rep)
            let picture = FileManager.default.temporaryDirectory.appendingPathComponent("studynotch-uitest-graph.png")
            try? rep.representation(using: .png, properties: [:])?.write(to: picture)
            print("      window picture: \(picture.path)")
        }
        check("graph: what it uses and what uses it", graph.uses(node.id).map(\.key) == ["Definition 4.1", "Definition 4.2"]
              && graph.usedBy(node.id).map(\.key) == ["Example 4.4"])

        _ = await click("Course tab Files", in: w)
        check("graph: the Files tab lists the course's files", state?.tab == .files)
        w.close()
    }

    // MARK: - The eyes, measured in the real window

    private static var dumpIndex = 0

    /// Where the bright eye pixels are around the mascot, in points from its centre, and how many.
    @MainActor
    private static func eyes(_ model: AppModel) -> (x: CGFloat, y: CGFloat, count: Int)? {
        guard let window, let view = window.contentView else { return nil }
        let spot = model.mascotSpot
        let size = model.size(for: model.mode)
        let canvas = IslandController.canvas
        // The island is centred at the top of the canvas; the view's own y grows upwards.
        let centre = CGPoint(x: (canvas.width - size.width) / 2 + spot.x, y: view.isFlipped ? spot.y : canvas.height - spot.y)
        let half = spot.height / 2 + 2
        let rect = NSRect(x: centre.x - half, y: centre.y - half, width: half * 2, height: half * 2)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        view.cacheDisplay(in: rect, to: rep)
        if let dump = ProcessInfo.processInfo.environment["STUDYNOTCH_EYES_DUMP"], let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: dump).appendingPathComponent("eyes-\(dumpIndex).png"))
            dumpIndex += 1
        }
        var sx: CGFloat = 0, sy: CGFloat = 0, n = 0
        let w = rep.pixelsWide, h = rep.pixelsHigh
        for py in 0..<h {
            for px in 0..<w {
                guard let c = rep.colorAt(x: px, y: py)?.usingColorSpace(.sRGB) else { continue }
                // The painted eyes are near-white; the glossy body's highlights are smaller and greyer.
                if c.redComponent > 0.86, c.greenComponent > 0.86, c.blueComponent > 0.86, c.alphaComponent > 0.9 {
                    sx += CGFloat(px); sy += CGFloat(py); n += 1
                }
            }
        }
        guard n > 0 else { return (0, 0, 0) }
        let scale = CGFloat(w) / rect.width
        return (sx / CGFloat(n) / scale - half, sy / CGFloat(n) / scale - half, n)
    }

    @MainActor
    private static func driveEyes(_ model: AppModel) async {
        if model.mode == .setup { model.closeSetup() }
        await pause(0.6)
        for (name, open) in [("opened card", true), ("peeking ear", false)] {
            if open { model.openHome() } else { model.collapse(); model.pointer(inside: true) }
            await pause(1.2)
            print("      \(name): mascot \(Int(model.mascotSpot.height))pt, mood \(model.mascotMood)")
            var seen: [String: (x: CGFloat, y: CGFloat, count: Int)] = [:]
            for (label, v) in [("centre", CGVector.zero), ("left", CGVector(dx: -1, dy: 0)), ("right", CGVector(dx: 1, dy: 0)),
                               ("up", CGVector(dx: 0, dy: -1)), ("down", CGVector(dx: 0, dy: 1))] {
                PointerLook.shared.update(v)
                // Settle, and make sure a blink isn't caught halfway.
                await pause(0.6)
                if eyes(model).map({ $0.count }) ?? 0 < 20 { await pause(0.4) }
                if let e = eyes(model) {
                    seen[label] = e
                    print(String(format: "      %@ %-6@ eyes at x %+.2f, y %+.2f pt (%d px)", name, label, e.x, e.y, e.count))
                }
            }
            if let l = seen["left"], let r = seen["right"], let u = seen["up"], let d = seen["down"] {
                print(String(format: "      %@: left↔right %.2f pt, up↕down %.2f pt", name, r.x - l.x, d.y - u.y))
                // They once cancelled out with the body's turn and moved about 1pt in the card.
                let least = model.mascotSpot.height * 0.15
                check("\(name): the eyes go toward the pointer, left to right by at least 15% of the mascot",
                      r.x - l.x >= least && l.x < seen["centre"]!.x && r.x > seen["centre"]!.x)
                check("\(name): and up and down", d.y - u.y > 0)
            } else {
                check("\(name): the eyes could be measured", false)
            }
        }
    }
}

/// For `--uitest`: where each button is in its window, by its words. Empty in normal use.
enum TestTags {
    static var frames: [String: CGRect] = [:]
    /// Which view wrote each frame, so a button that leaves doesn't erase its replacement's.
    static var owners: [String: UUID] = [:]
}

private struct TagReader: View {
    let name: String
    @State private var id = UUID()

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { set(geometry.frame(in: .global)) }
                .onChange(of: geometry.frame(in: .global)) { set($0) }
                .onDisappear {
                    if TestTags.owners[name] == id {
                        TestTags.frames[name] = nil
                        TestTags.owners[name] = nil
                    }
                }
        }
    }

    private func set(_ frame: CGRect) {
        TestTags.frames[name] = frame
        TestTags.owners[name] = id
    }
}

extension View {
    /// Records where this is in the window while `--uitest` runs; nothing otherwise.
    @ViewBuilder
    func testTag(_ name: String) -> some View {
        if UITest.active {
            background(TagReader(name: name))
        } else {
            self
        }
    }
}
