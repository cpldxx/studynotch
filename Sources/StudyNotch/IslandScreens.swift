import SwiftUI
import AppKit
import UniformTypeIdentifiers

// The island's screens, laid out the way Coucou lays out its own (see the note at the top of
// IslandViews.swift): hidden on the notch, peeking with two ears, opened as a 640-point card with
// tabs in the strip beside the notch, and the mascot springing between its places on top.

// MARK: - Root

struct IslandRootView: View {
    @ObservedObject var model: AppModel
    @State private var size: CGSize = .zero
    @State private var corner: CGFloat = 12
    @State private var ear: CGFloat = 8
    @State private var laidOut = false

    var body: some View {
        let target = model.size(for: model.mode)
        // Folded over a real notch there is nothing to draw: the hardware is already black.
        let invisible = model.mode == .idle && model.geo.hasNotch
        ZStack(alignment: .top) {
            ZStack(alignment: .topLeading) {
                IslandShape(cornerRadius: corner, ear: ear)
                    .fill(Color.black.opacity(invisible ? 0 : 1))

                // Laid out at the final size and revealed by the growing shape.
                ZStack(alignment: .top) { content }
                    .frame(width: target.width, height: target.height, alignment: .top)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .mask(IslandShape(cornerRadius: corner, ear: ear))
                    .animation(.default, value: model.mode)

                MascotLayer(model: model)

                CountdownBar(model: model)
                    .frame(width: size.width, height: size.height, alignment: .bottom)
                    .allowsHitTesting(false)
            }
            .frame(width: size.width, height: size.height)
            .foregroundColor(Ink.text)
            .font(.system(size: 13))
            .onDrop(of: [UTType.fileURL], isTargeted: $model.dropTargeted) { providers in
                loadDropped(providers)
                return true
            }

            UnderLine(model: model)
                .padding(.top, size.height + 8)
        }
        .frame(width: IslandController.canvas.width, height: IslandController.canvas.height, alignment: .top)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.2), value: invisible)
        .onAppear { apply(target, animated: false) }
        .onChange(of: target) { next in apply(next, animated: true) }
        .onChange(of: model.dropTargeted) { over in if over { model.openForDrop() } }
    }

    private func apply(_ target: CGSize, animated: Bool) {
        // The window controller reads the same size to know where clicks land.
        model.islandSize = target
        let expanded = model.mode.isExpanded
        let update = {
            size = target
            corner = expanded ? 22 : min(12, target.height * 0.4)
            ear = expanded ? 0 : min(10, target.height * 0.3)
        }
        guard animated, laidOut else {
            laidOut = true
            update()
            return
        }
        let growing = target.width > size.width + 0.5 || target.height > size.height + 0.5
        withAnimation(growing ? Motion.open : Motion.close, update)
    }

    @ViewBuilder private var content: some View {
        switch model.mode {
        case .idle: FoldedTap(model: model).transition(.islandContent)
        case .compact: CompactView(model: model).transition(.islandContent)
        case .greeting: GreetingView(model: model).transition(.islandContent)
        default: OpenedView(model: model).transition(.islandContent)
        }
    }

    private func loadDropped(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { model.addDropped([url]) }
            }
        }
    }
}

extension AnyTransition {
    /// Coucou's cross-fade between the views of an opened island: the old one goes quickly,
    /// the new one comes a moment later with a small spring.
    static var page: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.97)).animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.16)),
            removal: .opacity.animation(.easeIn(duration: 0.16))
        )
    }
}

// MARK: - Mascot, countdown, line under the island

/// The one mascot of the island. It springs from place to place when the island changes
/// (Coucou's BotPlacement), glows with the state when the island is open, smiles under the
/// pointer, follows the pointer with its eyes and hops when patted.
struct MascotLayer: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var look = PointerLook.shared

    var body: some View {
        let spot = model.mascotSpot
        let mood = model.mascotMood
        let open = model.mode.isExpanded
        ZStack {
            if open {
                MascotGlow(mood: mood, size: spot.height)
                    .transition(.opacity)
            }
            MascotView(mood: mood, height: spot.height, animated: !model.previewMode,
                       look: look.vector, hop: model.mascotPat)
                .overlay(alignment: .topLeading) {
                    if open, let line = model.mascotLine {
                        SpeechBubble(text: line)
                            .fixedSize()
                            .offset(x: spot.height * 0.7, y: -spot.height * 0.32)
                            .transition(.scale(scale: 0.6, anchor: .bottomLeading).combined(with: .opacity))
                    }
                }
                .padding(6)
                .contentShape(Rectangle())
                .onHover { inside in
                    if open { model.mascotHover = inside }
                }
                .onTapGesture { model.patMascot() }
                .allowsHitTesting(open)
                .help(open ? "Pat" : "")
        }
        .opacity(spot.visible ? 1 : 0)
        .position(x: spot.x, y: spot.y)
        .animation(.spring(response: 0.5, dampingFraction: 0.72), value: spot)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.mascotLine)
    }
}

struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundColor(Ink.pen)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Ink.paper))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            .allowsHitTesting(false)
    }
}

/// The thin line at the bottom of an opened island in its last ten seconds before it folds by
/// itself (Coucou's countdown bar).
struct CountdownBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.outsideSince != nil, model.mode.closesByItself, !model.holdsOpen {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { timeline in
                let left = model.closeCountdown(at: timeline.date) ?? AppModel.autoClose
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: left < 10 ? CGFloat(left / 10) * 160 : 0, height: 2)
            }
            .padding(.bottom, 3)
        }
    }
}

/// Under a folded island: what the session is doing while the pointer is on it, or a short notice.
struct UnderLine: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let text = model.notice ?? (model.hoverLift && model.mode == .compact ? model.hoverLine : nil)
        ZStack {
            if let text {
                HStack(spacing: 6) {
                    Circle().fill(dot).frame(width: 6, height: 6)
                    Text(text)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(Ink.text)
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.92)))
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: text)
        .allowsHitTesting(false)
    }

    /// Neutral: what is going on shows in the mascot's eyes and in the words, not in this dot.
    private var dot: Color { Ink.icon }
}

// MARK: - Folded

/// Hidden on the notch, or the small bar on a screen without one. A click opens the island.
struct FoldedTap: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { model.openHome() }
    }
}

/// The notch with an 80-point ear on each side: the mascot in the left one, the time in the right.
struct CompactView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            // The mascot sits here (MascotLayer).
            Color.clear.frame(width: AppModel.earWidth)
            Spacer(minLength: 0)
            right.frame(width: AppModel.earWidth)
        }
        .frame(height: model.geo.notchHeight)
        .contentShape(Rectangle())
        .onTapGesture { model.openHome() }
    }

    @ViewBuilder private var right: some View {
        if let s = model.session {
            HStack(spacing: 5) {
                ProgressRing(progress: model.sessionProgress, color: s.restUntil == nil ? Ink.primary : Ink.icon)
                    .frame(width: 12, height: 12)
                Text(model.remainingShort)
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        } else {
            // Today's minutes, with the Record tab's bars so the number reads as "studied", not "left".
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill").font(.system(size: 8.5, weight: .semibold))
                Text("\(model.today.minutes)m")
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(Ink.icon)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Studied \(model.today.minutes) min today")
        }
    }
}

struct ProgressRing: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

/// On launch the island opens for a moment, says hello, and folds away (Coucou's greeting).
struct GreetingView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 3) {
            Spacer(minLength: 0)
            Text("Hi! Let’s study together today")
                .font(.system(size: 13.5, weight: .semibold))
            Text(model.today.minutes > 0 ? "\(model.today.minutes) min so far today" : "Point at the notch to bring me back")
                .font(.system(size: 11.5))
                .foregroundColor(Ink.icon)
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { model.openHome() }
    }
}

// MARK: - Opened: header and pages

struct OpenedView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            IslandHeader(model: model)
                .frame(height: 34)
                .padding(.top, 8)
            ZStack { page }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
    }

    @ViewBuilder private var page: some View {
        switch model.mode {
        case .record: RecordPage(model: model).transition(.page)
        case .add: AddPage(model: model).transition(.page)
        case .nudge: NudgePage(model: model).transition(.page)
        case .summary: SummaryPage(model: model).transition(.page)
        case .setup: SetupPage(model: model).transition(.page)
        default: HomePage(model: model).transition(.page)
        }
    }
}

/// Tabs on the left of the notch, icons on the right (Coucou's header).
struct IslandHeader: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(IslandTab.allCases, id: \.self) { tab in
                    TabButton(icon: tab.icon, label: tab.label, on: model.mode == tab.mode) { model.openTab(tab) }
                }
            }
            .padding(.leading, 14)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                if model.session != nil, model.mode != .home {
                    SessionPill(model: model)
                }
                HeaderIcon(symbol: model.config.sounds ? "speaker.wave.2" : "speaker.slash",
                           label: model.config.sounds ? "Mute sounds" : "Turn on sounds") { model.toggleSounds() }
                HeaderIcon(symbol: model.mode == .setup ? "gearshape.fill" : "gearshape",
                           label: "Connections and permissions", on: model.mode == .setup) {
                    if model.mode == .setup { model.closeSetup() } else { model.openSetup() }
                }
                HeaderIcon(symbol: "xmark", label: "Close") {
                    if model.mode == .setup { model.closeSetup() } else { model.collapse() }
                }
            }
            .padding(.trailing, 14)
        }
    }
}

struct TabButton: View {
    let icon: String
    let label: String
    let on: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(on ? Ink.text : (hovered ? Color(white: 0.7) : Ink.icon))
                .frame(width: 30, height: 22)
                .background(Capsule().fill(on ? Ink.tabOn : (hovered ? Color.white.opacity(0.07) : .clear)))
                .contentShape(Capsule())
        }
        .buttonStyle(Springy())
        .onHover { hovered = $0 }
        .testTag("Tab \(label)")
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct HeaderIcon: View {
    let symbol: String
    let label: String
    var on = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13.5))
                .foregroundColor(on || hovered ? Ink.text : Ink.icon)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(Springy())
        .onHover { hovered = $0 }
        .testTag("Header \(label)")
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The running session in the header of the other tabs: the time left, with a white dot. Goes home.
struct SessionPill: View {
    @ObservedObject var model: AppModel
    @State private var hovered = false

    var body: some View {
        let course = model.session?.preset.course ?? ""
        Button { model.openTab(.home) } label: {
            HStack(spacing: 5) {
                Circle().fill(Ink.primary).frame(width: 5, height: 5)
                Text(model.remainingClock)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundColor(hovered ? Ink.text : Ink.icon)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(hovered ? Ink.fill : Ink.pill))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(Springy())
        .onHover { hovered = $0 }
        .help("\(course) session")
    }
}

/// Coucou's card: #141518, rounded 20, a faint edge, and a faint wash of light rising from below.
/// The wash is the interface's one spoonful of colour: it takes the state's colour (Ink.Glow).
struct CardBackground: View {
    var wash: Color? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Ink.card)
            .overlay(
                RadialGradient(gradient: Gradient(stops: [
                    .init(color: wash ?? .clear, location: 0),
                    .init(color: .clear, location: 0.7),
                ]), center: UnitPoint(x: 0.5, y: 1.3), startRadius: 0, endRadius: 280)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            )
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Ink.cardEdge, lineWidth: 1))
            .animation(.easeInOut(duration: 0.4), value: wash)
    }
}

/// The small capsule buttons inside a card. Filled means the one thing to press.
struct CardButton: View {
    let title: String
    var filled = false
    var icon: String?
    let action: () -> Void

    init(_ title: String, filled: Bool = false, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.filled = filled
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 9.5, weight: .bold)) }
                Text(title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
            }
            .foregroundColor(filled ? .black : Ink.text)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(Capsule().fill(filled ? Ink.primary : Color.white.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(Springy())
        .testTag(title)
    }
}

/// The left text of every card starts here, clear of the mascot.
private let cardText: CGFloat = 98

// MARK: Home

struct HomePage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CourseCard(model: model).frame(width: 322)
            CoursePills(model: model)
        }
    }
}

/// The course picked on the right: start it, or run it.
struct CourseCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let course = model.shownCourse ?? AppConfig.generalCourse
        let running = model.session.flatMap { $0.preset.course == course ? $0 : nil }
        ZStack(alignment: .topLeading) {
            CardBackground(wash: wash(running))
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(course)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text(subtitle(course, running))
                        .font(.system(size: 11.5))
                        .foregroundColor(Ink.icon)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 2)
                }
                .padding(.top, 11)
                .padding(.trailing, 58)
                .help(stuckHelp(running))

                HStack(spacing: 6) {
                    Text(running != nil ? model.remainingClock : "\(model.config.sessionMinutes):00")
                        .font(.system(size: 21, weight: .semibold).monospacedDigit())
                    Spacer(minLength: 4)
                    controls(course, running)
                }
                .padding(.top, 5)
                .padding(.trailing, 10)

                third(course, running)
                    .padding(.top, 7)
            }
            .padding(.leading, cardText)

            if course != AppConfig.generalCourse {
                Button { model.editCourse(course) } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "folder").font(.system(size: 8.5, weight: .semibold))
                        Text("Edit").font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundColor(Ink.icon)
                    .padding(.horizontal, 7)
                    .frame(height: 19)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
                    .contentShape(Capsule())
                }
                .buttonStyle(Springy())
                .testTag("Edit course")
                .help("Folders and files for \(course)")
                .accessibilityLabel("Folders and files for \(course)")
                .padding(.top, 9)
                .padding(.trailing, 10)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// The faint light under the card while its course runs: the state's colour.
    private func wash(_ running: ActiveSession?) -> Color? {
        guard let running else { return nil }
        if running.restUntil != nil { return Ink.Glow.rest }
        return model.glyph == .drift ? Ink.Glow.drift : Ink.Glow.focus
    }

    private func subtitle(_ course: String, _ running: ActiveSession?) -> String {
        if let s = running {
            if s.restUntil != nil { return "On a break" }
            let stuck = model.stuckFromLastTime
            if !stuck.isEmpty, s.focusSeconds < 180 { return "\(stuck.count) stuck last time" }
            // The question count lives in the hover line; English is too long for both here.
            return "Focused \(s.focusSeconds / 60) min"
        }
        if course == AppConfig.generalCourse { return "Timer only" }
        let count = model.materialCounts[course] ?? 0
        return count > 0 ? counted(count, "file") : "No files yet"
    }

    private func stuckHelp(_ running: ActiveSession?) -> String {
        guard running != nil else { return "" }
        let stuck = model.stuckFromLastTime
        return stuck.isEmpty ? "" : "Stuck last time\n" + stuck.map { "· " + $0 }.joined(separator: "\n")
    }

    @ViewBuilder private func controls(_ course: String, _ running: ActiveSession?) -> some View {
        if let s = running {
            if s.restUntil != nil {
                CardButton("Resume", filled: true, icon: "play.fill") { model.endRest() }
            } else {
                CardButton("Ask", filled: true, icon: "highlighter") { model.manualAsk() }
                Button { model.captureAsk() } label: {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(Springy())
                .help("Capture and ask")
                .accessibilityLabel("Capture and ask")
            }
        } else if model.session != nil {
            CardButton("Switch to this course", filled: true) { model.switchSession(to: course) }
        } else {
            CardButton("Start", filled: true, icon: "play.fill") { model.start(course: course) }
        }
    }

    @ViewBuilder private func third(_ course: String, _ running: ActiveSession?) -> some View {
        if let s = running {
            HStack(spacing: 6) {
                if s.restUntil == nil {
                    CardButton("\(model.config.breakMinutes)-min break", icon: "cup.and.saucer.fill") { model.startRest() }
                }
                CardButton("End", icon: "stop.fill") { model.endSession() }
            }
        } else if let other = model.session {
            Text("\(other.preset.course) session in progress")
                .font(.system(size: 11.5))
                .foregroundColor(Ink.icon)
                .frame(height: 26)
        } else {
            HStack(spacing: 4) {
                ForEach([25, 50, 90], id: \.self) { minutes in
                    MinuteChoice(minutes: minutes, selected: model.config.sessionMinutes == minutes) {
                        model.setSessionMinutes(minutes)
                    }
                }
            }
            .frame(height: 26)
        }
    }
}

struct MinuteChoice: View {
    let minutes: Int
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text("\(minutes) min")
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .foregroundColor(selected || hovered ? Ink.text : Ink.icon)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(selected ? Ink.tabOn : Color.white.opacity(hovered ? 0.12 : 0.06)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(selected ? 0.22 : 0), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(Springy())
        .onHover { hovered = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Every course as a pill with its own small page and highlighter (Coucou's pill grid).
struct CoursePills: View {
    @ObservedObject var model: AppModel
    private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        let courses = model.config.courses
        ZStack {
            CardBackground()
            if courses.count + 1 > 6 {
                ScrollView(.vertical, showsIndicators: false) { grid(courses).padding(.vertical, 8) }
            } else {
                grid(courses)
            }
        }
    }

    private func grid(_ courses: [String]) -> some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(courses, id: \.self) { course in
                let running = model.session?.preset.course == course
                CoursePill(course: course,
                           label: running ? model.remainingClock : course,
                           focused: model.shownCourse == course, running: running) {
                    model.focus(course: course)
                }
            }
            AddPill { model.openTab(.add) }
        }
        .padding(.horizontal, 8)
    }
}

/// A course in the list. No colour of its own: the picked one is lighter, the running one shows its
/// time and a white dot.
struct CoursePill: View {
    let course: String
    let label: String
    let focused: Bool
    let running: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        let hot = hovered || focused
        Button(action: action) {
            ZStack {
                Capsule().fill(focused ? Ink.tabOn : (hovered ? Ink.fill : Ink.pill))
                Capsule().strokeBorder(Color.white.opacity(focused ? 0.22 : 0.08), lineWidth: 1)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if running {
                        Circle().fill(Ink.primary).frame(width: 5, height: 5).padding(.trailing, 10)
                    }
                }
                Text(label)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundColor(hot ? Ink.text : Ink.icon)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovered ? 1.04 : 1)
        .brightness(hovered ? 0.06 : 0)
        .onHover { inside in withAnimation(Motion.hover) { hovered = inside } }
        .animation(Motion.hover, value: focused)
        .help(course)
        .accessibilityLabel(course)
        .accessibilityAddTraits(focused ? .isSelected : [])
    }
}

struct AddPill: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 9.5, weight: .bold))
                Text("Course").font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(hovered ? Ink.text : Ink.icon)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(Capsule().fill(Color.white.opacity(hovered ? 0.08 : 0)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovered ? 1.04 : 1)
        .onHover { inside in withAnimation(Motion.hover) { hovered = inside } }
        .accessibilityLabel("Add a course")
    }
}

// MARK: Record

struct RecordPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            TodayCard(model: model).frame(width: 322)
            WeekCard(model: model)
        }
    }
}

func minutesText(_ m: Int) -> String {
    if m < 60 { return "\(m) min" }
    return m % 60 == 0 ? "\(m / 60) hr" : "\(m / 60) hr \(m % 60) min"
}

/// "1 question", "3 questions".
func counted(_ n: Int, _ noun: String) -> String {
    "\(n) \(noun)\(n == 1 ? "" : "s")"
}

struct TodayCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let today = model.today
        ZStack(alignment: .topLeading) {
            CardBackground(wash: today.minutes > 0 ? Color.white.opacity(0.12) : nil)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("Today").font(.system(size: 12.5, weight: .semibold))
                    Text(Self.date.string(from: model.now)).font(.system(size: 11.5)).foregroundColor(Ink.icon)
                }
                .padding(.top, 11)
                Text(minutesText(today.minutes))
                    .font(.system(size: 21, weight: .semibold).monospacedDigit())
                    .padding(.top, 5)
                Text("\(counted(today.sessions, "session")) · \(counted(today.questions, "question"))")
                    .font(.system(size: 11.5))
                    .foregroundColor(Ink.icon)
                    .padding(.top, 4)
                Text("\(minutesText(model.week.reduce(0) { $0 + $1.minutes })) in the last 7 days")
                    .font(.system(size: 11.5))
                    .foregroundColor(Ink.icon)
                    .padding(.top, 3)
            }
            .padding(.leading, cardText)
        }
        .frame(maxHeight: .infinity)
    }

    static let date: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()
}

/// Seven bars, today's in highlighter. The pointer on a bar shows its day.
struct WeekCard: View {
    @ObservedObject var model: AppModel
    @State private var hovered: Int?
    @State private var grown = false

    var body: some View {
        let days = model.week
        let top = max(30, days.map(\.minutes).max() ?? 0)
        ZStack(alignment: .top) {
            CardBackground()
            VStack(spacing: 6) {
                Text(caption(days))
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundColor(hovered != nil ? Ink.text : Ink.icon)
                    .frame(height: 15)
                    .padding(.top, 9)
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                        let isToday = i == days.count - 1
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(isToday ? Ink.primary : Color.white.opacity(hovered == i ? 0.5 : 0.2))
                                .frame(width: 14, height: max(3, 52 * CGFloat(day.minutes) / CGFloat(top) * (grown ? 1 : 0.05)))
                            Text(Self.weekday.string(from: day.day))
                                .font(.system(size: 11))
                                .foregroundColor(isToday ? Ink.text : Ink.faint)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside { hovered = i } else if hovered == i { hovered = nil }
                        }
                    }
                }
                .frame(height: 72, alignment: .bottom)
                .padding(.horizontal, 10)
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            if model.previewMode { grown = true } else { withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.15)) { grown = true } }
        }
    }

    private func caption(_ days: [DayTotal]) -> String {
        guard let i = hovered, days.indices.contains(i) else { return "Last 7 days" }
        return "\(Self.day.string(from: days[i].day)) · \(minutesText(days[i].minutes))"
    }

    static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEEEEE"
        return f
    }()

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE, MMM d"
        return f
    }()
}

// MARK: Add

/// Coucou's "+" tab: here, a new course on the left and the drop place for PDFs on the right.
struct AddPage: View {
    @ObservedObject var model: AppModel
    @FocusState private var naming: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let course = model.editingCourse { editCard(course) } else { newCard }
            }
            .frame(width: 322)
            CourseFilesCard(model: model)
        }
        .onExitCommand { model.collapse() }
        .onChange(of: model.addingCourse) { on in if !on { naming = false } }
    }

    // MARK: A new course

    private var newCard: some View {
        let ready = model.config.canName(model.newCourseName)
        return ZStack(alignment: .topLeading) {
            CardBackground()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("New course").font(.system(size: 12.5, weight: .semibold))
                    Text("Return to add").font(.system(size: 11.5)).foregroundColor(Ink.icon)
                }
                .padding(.top, 11)
                HStack(spacing: 6) {
                    nameField("e.g. STAT 230", text: $model.newCourseName) { if ready { model.addCourse() } }
                    CardButton("Add", filled: true) { model.addCourse() }
                        .opacity(ready ? 1 : 0.4)
                        .allowsHitTesting(ready)
                }
                .padding(.top, 8)
                .padding(.trailing, 10)
                sources.padding(.top, 8)
                Text(Self.newHint(picked: model.staged.count))
                    .font(.system(size: 11.5))
                    .foregroundColor(Ink.icon)
                    .lineLimit(1)
                    .frame(height: 26)
                    .padding(.top, 4)
            }
            .padding(.leading, cardText)
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            if model.addingCourse { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { naming = true } }
        }
    }

    /// Pure: the line under the buttons. Picked things are not kept until "Add".
    static func newHint(picked: Int) -> String {
        picked == 0 ? "Or drop them onto the island." : "Kept only if you press Add."
    }

    // MARK: A course that already exists

    private func editCard(_ course: String) -> some View {
        let changed = model.editName.trimmingCharacters(in: .whitespacesAndNewlines) != course
        let ready = changed && model.config.canName(model.editName, renaming: course)
        return ZStack(alignment: .topLeading) {
            CardBackground()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("Course").font(.system(size: 12.5, weight: .semibold))
                    Text(Self.summary(files: model.materialCounts[course] ?? 0, folders: model.config.folders(for: course).count))
                        .font(.system(size: 11.5)).foregroundColor(Ink.icon).lineLimit(1)
                }
                .padding(.top, 11)
                HStack(spacing: 6) {
                    nameField(course, text: $model.editName) { if ready { model.renameCourse() } }
                    CardButton("Rename") { model.renameCourse() }
                        .opacity(ready ? 1 : 0.4)
                        .allowsHitTesting(ready)
                }
                .padding(.top, 8)
                .padding(.trailing, 10)
                sources.padding(.top, 8)
                Group {
                    if model.removingCourse {
                        HStack(spacing: 8) {
                            Text("To the Trash?").font(.system(size: 11.5, weight: .medium))
                            Spacer(minLength: 4)
                            QuietLink(title: "Cancel") { model.removingCourse = false }
                            CardButton("Remove", filled: true) { model.removeCourse() }
                                .help("Removes \(course) and moves its own folder to the Trash. Linked folders stay where they are.")
                        }
                    } else {
                        HStack(spacing: 12) {
                            QuietLink(title: "Show in Finder") { model.openCourseFolder(course) }
                            QuietLink(title: "Remove course") { model.removingCourse = true }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(height: 26)
                .padding(.top, 4)
                .padding(.trailing, 10)
                Text(Self.projectLine(model.activeAI))
                    .font(.system(size: 11))
                    .foregroundColor(Ink.faint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .padding(.trailing, 10)
            }
            .padding(.leading, cardText)
        }
        .frame(maxHeight: .infinity)
    }

    /// Pure: what the connected AI does with the course's files. The course is its project.
    static func projectLine(_ ai: AIKind?) -> String {
        switch ai {
        case .none: return "Connect an AI to use these files."
        case .apiKey: return "The matching page goes with each question."
        case .some(let kind): return "\(kind.label) can open these when it answers."
        }
    }

    /// Pure: "5 files · 1 folder linked".
    static func summary(files: Int, folders: Int) -> String {
        let first = files > 0 ? counted(files, "file") : "No files yet"
        return folders > 0 ? first + " · " + counted(folders, "folder") + " linked" : first
    }

    // MARK: Shared pieces

    /// The two ways in besides dropping: the Mac's own Open panel.
    private var sources: some View {
        HStack(spacing: 6) {
            CardButton("Link folder", icon: "folder.badge.plus") { model.choose(folders: true) }
                .help("Link a folder on this Mac. Its PDFs are read where they are; nothing is copied.")
            CardButton("Add PDFs", icon: "doc.badge.plus") { model.choose(folders: false) }
                .help("Copy PDFs into the course’s own folder.")
        }
    }

    private func nameField(_ placeholder: String, text: Binding<String>, submit: @escaping () -> Void) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused($naming)
            .onSubmit(submit)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(naming ? Color.white.opacity(0.38) : Ink.line, lineWidth: 1))
            .onTapGesture {
                model.beginAddingCourse()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { naming = true }
            }
            .testTag("Course name")
    }
}

/// The right half of the Add tab: what the course has (or will have), and where things are dropped.
struct CourseFilesCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let items = model.courseItems
        ZStack {
            CardBackground(wash: model.dropTargeted ? Color.white.opacity(0.28) : nil)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(model.dropTargeted ? 0.6 : 0.16),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .padding(8)
            if items.isEmpty { empty } else { list(items) }
        }
        .frame(maxHeight: .infinity)
        .animation(Motion.hover, value: model.dropTargeted)
    }

    private var empty: some View {
        VStack(spacing: 5) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(model.dropTargeted ? Ink.text : Ink.icon)
                .scaleEffect(model.dropTargeted ? 1.15 : 1)
            Text("Drop PDFs or a folder here").font(.system(size: 12, weight: .semibold))
            Text(Self.destination(model.editingCourse))
                .font(.system(size: 11.5)).foregroundColor(Ink.icon).lineLimit(1)
        }
    }

    /// Pure: where a drop goes, under the drop zone's title.
    static func destination(_ course: String?) -> String {
        course.map { "They go into \($0)" } ?? "They join the course when you press Add"
    }

    private func list(_ items: [CourseItem]) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                ForEach(items) { item in
                    CourseItemRow(item: item, picked: model.editingCourse == nil,
                                  reveal: { model.reveal(item) }, remove: { model.remove(item) })
                }
            }
            .padding(.vertical, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

/// One linked folder or PDF in a course's list.
struct CourseItemRow: View {
    let item: CourseItem
    /// On the new-course page nothing has been copied or linked yet.
    let picked: Bool
    let reveal: () -> Void
    let remove: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: item.kind == .folder ? "folder" : "doc.text")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Ink.icon)
                .frame(width: 14)
            Text(item.url.lastPathComponent)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text(Self.detail(item)).font(.system(size: 11)).foregroundColor(Ink.faint).lineLimit(1)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundColor(hovered ? Ink.text : Ink.icon)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.white.opacity(hovered ? 0.12 : 0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(Springy())
            .help(Self.removeHelp(item, picked: picked))
            .accessibilityLabel(Self.removeHelp(item, picked: picked))
            .testTag("Remove \(item.url.lastPathComponent)")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(hovered ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(perform: reveal)
        .help("Show in Finder")
    }

    /// Pure: a folder says how many PDFs it holds, or that it can't be found.
    static func detail(_ item: CourseItem) -> String {
        guard item.kind == .folder else { return "" }
        return item.count.map { counted($0, "PDF") } ?? "Not found"
    }

    /// Pure: what the ✕ does to this row.
    static func removeHelp(_ item: CourseItem, picked: Bool) -> String {
        if picked { return "Don’t add \(item.url.lastPathComponent)" }
        return item.kind == .folder ? "Unlink \(item.url.lastPathComponent). The folder itself stays."
                                    : "Move \(item.url.lastPathComponent) to the Trash"
    }
}

// MARK: Nudge, summary, setup

struct NudgePage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: Ink.Glow.drift)
            VStack(alignment: .leading, spacing: 0) {
                Text(headline).font(.system(size: 13.5, weight: .semibold)).lineLimit(1).padding(.top, 14)
                Text(sub).font(.system(size: 11.5)).foregroundColor(Ink.icon).padding(.top, 3)
                HStack(spacing: 6) {
                    CardButton("Back to work", filled: true) { model.nudgeBack() }
                    CardButton("\(model.config.breakMinutes)-min break", icon: "cup.and.saucer.fill") { model.nudgeRest() }
                    CardButton("It’s for study") { model.nudgeIsStudy() }
                }
                .padding(.top, 13)
            }
            .padding(.leading, cardText)
        }
    }

    private var headline: String {
        guard let nudge = model.nudge else { return "" }
        return "\(max(1, nudge.seconds / 60)) min on \(nudge.target)"
    }

    private var sub: String {
        guard let s = model.session else { return "" }
        return "\(s.preset.course) session · \(model.remainingShort) left · nothing is blocked"
    }
}

struct SummaryPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            CardBackground(wash: Ink.Glow.done)
            if let summary = model.summary {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Text("Session done").font(.system(size: 13, weight: .semibold))
                        Text(summary.preset.course).font(.system(size: 11.5)).foregroundColor(Ink.icon)
                    }
                    .padding(.top, 12)
                    HStack(alignment: .bottom, spacing: 22) {
                        stat("\(summary.focusMinutes) min", "focused")
                        stat("\(summary.distractMinutes) min", "drifted")
                        stat("\(summary.questions.count)", summary.questions.count == 1 ? "question" : "questions")
                        Spacer(minLength: 8)
                        HStack(spacing: 6) {
                            CardButton("One more", filled: true, icon: "arrow.counterclockwise") { model.start(course: summary.preset.course) }
                            CardButton("Close") { model.closeSummary() }
                        }
                    }
                    .padding(.top, 9)
                    .padding(.trailing, 14)
                    if let last = summary.questions.last {
                        Text("Stuck on: \(last)")
                            .font(.system(size: 11.5))
                            .foregroundColor(Ink.icon)
                            .lineLimit(1)
                            .padding(.top, 8)
                            .padding(.trailing, 14)
                    }
                }
                .padding(.leading, cardText)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 21, weight: .semibold).monospacedDigit())
            Text(label).font(.system(size: 11.5)).foregroundColor(Ink.icon)
        }
    }
}

struct SetupPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        // Reading `refresh` makes this card redraw when a permission or tool changes.
        let _ = model.refresh
        let step = model.setupStep
        ZStack(alignment: .topLeading) {
            CardBackground()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 6) {
                    Text(title(step)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 6)
                    StepTab(number: 1, label: "AI", done: model.activeAI != nil, on: step == .ai) { model.setupStep = .ai }
                    StepTab(number: 2, label: "Permissions", done: model.accessibilityGranted, on: step == .permissions) {
                        model.setupStep = .permissions
                    }
                }
                .padding(.top, 9)
                Text(step == .ai ? Self.aiLine(model.test) : "Without Accessibility, the text you select can’t reach the AI.")
                    .font(.system(size: 11.5))
                    .foregroundColor(step == .ai && model.test != .idle && model.test != .running ? Ink.text : Ink.icon)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 2)
                if step == .ai { aiStep } else { permissionStep }
            }
            .padding(.leading, cardText)
            .padding(.trailing, 14)
            .animation(.easeInOut(duration: 0.2), value: step)
        }
    }

    /// Pure: the line under the title in step 1. A connection test's result takes its place.
    static func aiLine(_ test: AppModel.TestState) -> String {
        switch test {
        case .idle: return "Only the one you connect gets your questions, from your own account."
        case .running: return "Sending one real question to check the connection…"
        case .passed(let line), .failed(let line): return line
        }
    }

    private func title(_ step: AppModel.SetupStep) -> String {
        switch step {
        case .ai: return model.firstRun ? "First, connect the AI that answers you" : "AI connection"
        case .permissions: return model.firstRun ? "Then let StudyNotch read what you pick" : "Permissions"
        }
    }

    private var aiStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ForEach(AIKind.choices, id: \.self) { kind in
                    AITile(model: model, kind: kind)
                }
            }
            .padding(.top, 9)
            if let kind = model.confirming {
                // Signed in on this Mac is not the same as connected: say which account, and wait for a yes.
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Self.connectQuestion(kind))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(Ink.text)
                            .lineLimit(1)
                        Text(Self.connectAccount(kind, account: model.account(kind)))
                            .font(.system(size: 11.5))
                            .foregroundColor(Ink.icon)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 6)
                    QuietLink(title: "Cancel") { model.confirming = nil }
                    CardButton("Another account") { model.useAnotherAccount(kind) }
                        .help(Self.anotherAccountHelp(kind))
                    CardButton("Connect", filled: true) { model.connect(kind) }
                }
                .padding(.top, 9)
            } else if let on = model.connectedAI {
                HStack(spacing: 10) {
                    QuietLink(title: "Disconnect") { model.disconnect() }
                    if on != .apiKey {
                        QuietLink(title: "Another account") { model.useAnotherAccount(on) }
                            .help(Self.anotherAccountHelp(on))
                    } else {
                        QuietLink(title: "Change the key") { model.onAskAPIKey?() }
                    }
                    Spacer(minLength: 6)
                    CardButton(model.test == .running ? "Testing…" : "Test connection") { model.testConnection() }
                        .disabled(model.activeAI == nil || model.test == .running)
                        .opacity(model.activeAI == nil ? 0.5 : 1)
                        .help("Sends one real question to \(on.label) and shows its answer here.")
                    CardButton("Next", filled: model.activeAI != nil) { model.setupStep = .permissions }
                }
                .padding(.top, 9)
            } else {
                HStack(spacing: 6) {
                    QuietLink(title: "Use an API key instead") { model.chooseAI(.apiKey) }
                    Spacer(minLength: 6)
                    CardButton("Check again") { model.openSetup(step: .ai) }
                    CardButton("Skip for now") { model.setupStep = .permissions }
                }
                .padding(.top, 9)
            }
        }
    }

    /// Pure: what "Another account" does, for the tooltip.
    static func anotherAccountHelp(_ kind: AIKind) -> String {
        switch kind {
        case .claudeCLI: return "Opens Claude’s sign-in page. That sign-in is only for StudyNotch; the Claude app stays as it is."
        case .codexCLI: return "Opens ChatGPT’s sign-in page. That sign-in is only for StudyNotch; the ChatGPT app stays as it is."
        case .geminiCLI: return "Opens agy so you can sign out and sign in with another Google account."
        case .apiKey: return ""
        }
    }

    /// Pure: the question asked before an AI that is already signed in is connected.
    static func connectQuestion(_ kind: AIKind) -> String {
        "Connect \(kind.label) with this account?"
    }

    /// Pure: the account under the question: its email and plan when the tool says, else where it is signed in.
    static func connectAccount(_ kind: AIKind, account: String?) -> String {
        if let account { return account }
        return kind == .geminiCLI ? "The Google account signed in to agy" : "The one signed in on this Mac"
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                row(ok: model.accessibilityGranted, title: "Accessibility", detail: "Reads the text you select, and window titles.") {
                    if !model.accessibilityGranted {
                        CardButton("Allow in Settings", filled: true) { model.requestAccessibility(); model.openAccessibilitySettings() }
                    }
                }
                row(ok: model.screenRecordingGranted, title: "Screen Recording", detail: "Used only for ‘Capture and ask’.") {
                    if !model.screenRecordingGranted { CardButton("Allow in Settings") { model.requestScreenRecording() } }
                }
            }
            .padding(.top, 10)
            HStack(spacing: 6) {
                Text("Browser tab addresses: your Mac asks the first time a session reads one.")
                    .font(.system(size: 11))
                    .foregroundColor(Ink.faint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                CardButton("Back") { model.setupStep = .ai }
                CardButton(model.firstRun ? "Get started" : "Done", filled: model.accessibilityGranted) { model.closeSetup() }
            }
            .padding(.top, 10)
        }
    }

    private func row<Trailing: View>(ok: Bool, title: String, detail: String,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ok ? Ink.text : Ink.icon)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(title).font(.system(size: 12.5, weight: .semibold))
                    Text(ok ? "Ready" : "Needed").font(.system(size: 11.5, weight: .semibold)).foregroundColor(Ink.icon)
                }
                Text(detail).font(.system(size: 11.5)).foregroundColor(Ink.icon).lineLimit(1)
            }
            Spacer(minLength: 6)
            trailing()
        }
    }
}

/// One step of the setup card, at its top right: a number until it is done, then a check.
struct StepTab: View {
    let number: Int
    let label: String
    let done: Bool
    let on: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if done {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                } else {
                    Text("\(number)").font(.system(size: 10.5, weight: .bold).monospacedDigit())
                }
                Text(label).font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundColor(on ? Ink.text : (hovered ? Color(white: 0.7) : Ink.icon))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(on ? Ink.tabOn : (hovered ? Color.white.opacity(0.07) : .clear)))
            .contentShape(Capsule())
        }
        .buttonStyle(Springy())
        .onHover { hovered = $0 }
        .testTag("Step \(number)")
        .accessibilityLabel("Step \(number), \(label)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// One AI to connect: its name, whose account it uses, and what it needs. Clicking it does the
/// next thing: asks "Connect …?" when it is signed in on this Mac, opens its sign-in, or gets it.
struct AITile: View {
    @ObservedObject var model: AppModel
    let kind: AIKind
    @State private var hovered = false

    var body: some View {
        let state = model.choiceState(kind)
        let picked = state == .connected
        let asking = model.confirming == kind
        Button { model.chooseAI(kind) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(kind.label).font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 2)
                    Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(picked ? Ink.text : Ink.faint)
                }
                // Which account, as soon as the tool says: the student should never have to guess.
                Text(Self.accountLine(kind, account: model.account(kind), state: state))
                    .font(.system(size: 11)).foregroundColor(Ink.icon).lineLimit(1).truncationMode(.middle).padding(.top, 1)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Image(systemName: Self.icon(state)).font(.system(size: 10, weight: .bold))
                    Text(Self.words(state, kind: kind)).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                }
                .foregroundColor(state == .checking || state == .waiting ? Ink.icon : Ink.text)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 74)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(picked ? 0.1 : (hovered || asking ? 0.07 : 0.04))))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(picked ? 0.45 : (asking ? 0.25 : 0.07)), lineWidth: picked ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(Springy())
        .onHover { hovered = $0 }
        .testTag("\(kind.label) tile")
        .help(Self.words(state, kind: kind))
        .accessibilityLabel("\(kind.label), \(Self.words(state, kind: kind))")
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    /// Pure: the grey line under the name. The email (without the plan) once it is known.
    static func accountLine(_ kind: AIKind, account: String?, state: AppModel.AIChoiceState) -> String {
        guard state == .connected || state == .ready, let account else { return kind.source }
        return account.components(separatedBy: " · ").first ?? account
    }

    static func icon(_ state: AppModel.AIChoiceState) -> String {
        switch state {
        case .connected: return "checkmark"
        case .ready: return "person.crop.circle"
        case .signIn: return "key"
        case .get: return "arrow.down.circle"
        case .checking: return "ellipsis"
        case .waiting: return "hourglass"
        }
    }

    /// Pure: the words at the bottom of a tile.
    static func words(_ state: AppModel.AIChoiceState, kind: AIKind) -> String {
        switch state {
        case .connected: return "Connected"
        case .ready: return "Signed in on this Mac"
        case .signIn: return "Sign in"
        case .get: return kind.getLabel
        case .checking: return "Checking"
        case .waiting: return "Finish signing in"
        }
    }
}

/// A grey text button for the way less taken.
struct QuietLink: View {
    let title: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(hovered ? Ink.text : Ink.icon)
                .underline(hovered)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .testTag(title)
    }
}
