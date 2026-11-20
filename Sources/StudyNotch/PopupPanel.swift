import AppKit
import SwiftUI
import Combine

/// The question popup: a small black card that opens next to where the user asked, takes a
/// preset or a typed question, and shows the answer in place. Claude itself is never shown.
struct AskPopupView: View {
    @ObservedObject var model: AppModel
    @FocusState private var typing: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.popupVisible, let thread = model.thread {
                card(thread)
                    .transition(.scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity))
            }
        }
        .padding(AskPopupController.inset)
        .frame(width: AskPopupController.canvas.width, height: AskPopupController.canvas.height, alignment: .topLeading)
        .animation(Motion.open, value: model.popupVisible)
        .environment(\.colorScheme, .dark)
    }

    private func card(_ thread: AskThread) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(thread)
            QuoteView(quote: thread.quote, imagePath: thread.imagePath)
            if thread.quote == nil, thread.imagePath == nil, !thread.started {
                emptyHint
            }
            if thread.started {
                conversation(thread)
            }
            if !thread.busy, thread.error == nil {
                composer(thread)
            }
        }
        .padding(16)
        .frame(width: AskPopupController.cardWidth, alignment: .leading)
        .foregroundColor(Ink.text)
        .font(.system(size: 13))
        .background(
            // The island's black with a faint light rising from below, like Coucou's chat card:
            // violet while the answer is written.
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black)
                .overlay(RadialGradient(gradient: Gradient(stops: [
                    .init(color: thread.busy ? Ink.Glow.writing : Color.white.opacity(0.06), location: 0),
                    .init(color: .clear, location: 0.7),
                ]), center: UnitPoint(x: 0.5, y: 1.25), startRadius: 0, endRadius: 320)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)))
                .animation(.easeInOut(duration: 0.5), value: thread.busy)
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { model.popupSize = proxy.size }
                .onChange(of: proxy.size) { size in model.popupSize = size }
        })
        .shadow(color: .black.opacity(0.42), radius: 18, y: 10)
        .onExitCommand { model.closePopup() }
    }

    private func header(_ thread: AskThread) -> some View {
        HStack(spacing: 8) {
            // The same mascot as the island: thinking while the answer is written.
            MascotView(mood: mood(thread), height: 22, animated: !model.previewMode, hop: model.mascotPat)
                .frame(width: 22, height: 22)
            Text("Ask").font(.system(size: 14, weight: .semibold))
            Text(context(thread))
                .font(.system(size: 12))
                .foregroundColor(Ink.icon)
                .lineLimit(1)
            Spacer(minLength: 4)
            providerPill(thread)
            CloseButton { model.closePopup() }
        }
    }

    private func mood(_ thread: AskThread) -> MascotMood {
        if thread.busy { return .thinking }
        if thread.error != nil { return .drift }
        return thread.answer.isEmpty ? .rest : .happy
    }

    /// Which AI answers, the way Coucou's chat shows its provider.
    private func providerPill(_ thread: AskThread) -> some View {
        // Pictures for the website show the usual case, Claude, unless they show the missing-AI card.
        let ai = model.previewMode ? (thread.errorAction == .setupAI ? nil : AIKind.claudeCLI) : model.activeAI
        return HStack(spacing: 5) {
            Circle().fill(ai != nil ? Ink.text : Ink.faint).frame(width: 6, height: 6)
            Text(ai?.label ?? "AI not connected").font(.system(size: 11.5, weight: .semibold))
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .help(ai == nil ? "AI is not connected" : "Answers come from \(ai!.label)")
    }

    private func context(_ thread: AskThread) -> String {
        var parts: [String] = []
        if let course = model.session?.preset.course { parts.append(course) }
        if !thread.sourceApp.isEmpty { parts.append(thread.sourceApp) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var emptyHint: some View {
        if model.accessibilityGranted {
            Text("No text is selected. You can just type a question, or capture the screen and ask.")
                .font(.system(size: 12.5))
                .foregroundColor(Ink.muted)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Reading the text you select needs the ‘Accessibility’ permission. For now you can type a question, or capture the screen and ask.")
                .font(.system(size: 12.5))
                .foregroundColor(Ink.muted)
                .fixedSize(horizontal: false, vertical: true)
            Chip("Allow in Settings") { model.requestAccessibility() }
        }
    }

    @ViewBuilder private func conversation(_ thread: AskThread) -> some View {
        // What was asked, as the user's bubble on the right.
        HStack {
            Spacer(minLength: 60)
            Text(thread.question)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.1)))
        }
        if let error = thread.error {
            Text(error).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            Flow {
                if thread.errorAction == .setupAI {
                    Chip("Choose AI", primary: true) {
                        model.closePopup()
                        model.openSetup(step: .ai)
                    }
                } else if thread.errorAction == .accessibility {
                    Chip("Allow in Settings", primary: true) {
                        model.closePopup()
                        model.requestAccessibility()
                        model.openAccessibilitySettings()
                    }
                } else {
                    Chip("Try again", primary: true) { model.retry() }
                }
                Chip("Close") { model.closePopup() }
            }
        } else {
            if !thread.answer.isEmpty {
                if model.previewMode {
                    Text(thread.answer).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                } else {
                    AnswerWebView(markdown: thread.answer, height: $model.answerHeight)
                        .frame(height: min(max(model.answerHeight, 22), 320))
                }
            }
            if let status = thread.status {
                HStack(spacing: 8) {
                    TypingDots()
                    Shimmer(text: status, animated: !model.previewMode)
                }
            }
            if !thread.busy, !thread.answer.isEmpty {
                HStack(spacing: 8) {
                    Text("Written by AI, so it can be wrong.")
                        .font(.system(size: 12))
                        .foregroundColor(Ink.muted)
                    Spacer(minLength: 0)
                    Chip("Save as review card", icon: "square.and.arrow.down") { model.saveCard() }
                }
                Divider().overlay(Ink.line)
            }
        }
    }

    private func composer(_ thread: AskThread) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(thread.started ? "Where are you stuck?" : "What would you like to know?")
                .font(.system(size: 12.5, weight: .semibold))
            Flow {
                ForEach(model.composerPresets) { preset in
                    Chip(preset.label, selected: model.selectedPreset == preset) { model.togglePreset(preset) }
                }
            }
            // Coucou's input: one capsule, the send button inside it on the right.
            HStack(spacing: 6) {
                TextField(thread.started ? "Ask a follow-up…" : "Or type your own question", text: $model.askText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($typing)
                    .onSubmit { model.send() }
                    .padding(.leading, 14)
                Chip("Send", primary: true, icon: "arrow.up") { model.send() }
                    .opacity(model.canSend ? 1 : 0.4)
                    .allowsHitTesting(model.canSend)
                    .animation(Motion.hover, value: model.canSend)
                    .padding(.trailing, 4)
            }
            .frame(height: 36)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            .overlay(Capsule().strokeBorder(typing ? Color.white.opacity(0.38) : Ink.line, lineWidth: 1))
            .animation(Motion.hover, value: typing)
        }
    }
}

/// A transparent canvas with the card at its top-left. Outside the card, clicks pass through.
final class AskPopupController {
    static let canvas = CGSize(width: 500, height: 780)
    static let inset: CGFloat = 30
    static let cardWidth: CGFloat = 430

    private let model: AppModel
    private let panel: IslandPanel
    private var timer: Timer?
    private var bag = Set<AnyCancellable>()

    init(model: AppModel) {
        self.model = model
        panel = IslandPanel(contentRect: NSRect(origin: .zero, size: Self.canvas),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        // Drag the card anywhere by its background.
        panel.isMovableByWindowBackground = true
        panel.ignoresMouseEvents = true

        let host = FirstClickHostingView(rootView: AskPopupView(model: model))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: Self.canvas)
        panel.contentView = host

        model.onPopupKey = { [weak self] want in self?.setKey(want) }
        model.$popupVisible.removeDuplicates().sink { [weak self] visible in
            guard let self else { return }
            if visible { self.show(at: self.model.popupAnchor) } else { self.hide() }
        }.store(in: &bag)
        model.$popupAnchor.dropFirst().sink { [weak self] point in
            guard let self, self.panel.isVisible else { return }
            self.place(at: point)
        }.store(in: &bag)

        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Top-left corner of the card for a question asked at `point`, kept on screen. (AppKit coordinates.)
    static func cardOrigin(for point: CGPoint, visible: NSRect) -> CGPoint {
        guard visible != .zero else { return CGPoint(x: point.x + 14, y: point.y - 10) }
        let roomNeeded: CGFloat = 440
        let left = min(max(visible.minX + 8, point.x + 14), visible.maxX - cardWidth - 8)
        var top = point.y - 10
        top = max(top, visible.minY + roomNeeded)
        top = min(top, visible.maxY - 8)
        return CGPoint(x: left, y: top)
    }

    private func place(at point: CGPoint) {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let corner = Self.cardOrigin(for: point, visible: screen?.visibleFrame ?? .zero)
        let origin = CGPoint(x: corner.x - Self.inset, y: corner.y + Self.inset - Self.canvas.height)
        panel.setFrame(NSRect(origin: origin, size: Self.canvas), display: true)
    }

    private func show(at point: CGPoint) {
        place(at: point)
        panel.orderFrontRegardless()
    }

    private func hide() {
        // Let the card finish shrinking away before the window goes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !self.model.popupVisible else { return }
            self.panel.orderOut(nil)
        }
    }

    private func setKey(_ want: Bool) {
        if want {
            panel.makeKey()
        } else if panel.isKeyWindow {
            // Hand the keyboard back to the app that was being read.
            panel.orderOut(nil)
            if model.popupVisible { panel.orderFrontRegardless() }
        }
    }

    private func poll() {
        guard panel.isVisible else { return }
        let size = model.popupSize
        let frame = panel.frame
        let rect = CGRect(x: frame.minX + Self.inset, y: frame.maxY - Self.inset - size.height,
                          width: Self.cardWidth, height: size.height)
        let inside = model.popupVisible && size.height > 10 && rect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
    }
}

/// Three dots that swell one after another while an answer is on its way (Coucou's typing dots).
struct TypingDots: View {
    @State private var on = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Ink.text)
                    .frame(width: 5, height: 5)
                    .scaleEffect(on ? 1.2 : 0.6)
                    .animation(.easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.14), value: on)
            }
        }
        .onAppear { on = true }
        .accessibilityHidden(true)
    }
}

/// A status line with a light sweeping across it (Coucou's shimmering text).
struct Shimmer: View {
    let text: String
    var animated = true
    @State private var phase: CGFloat = -0.3

    var body: some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(LinearGradient(stops: [
                .init(color: Ink.faint, location: max(0, phase - 0.3)),
                .init(color: .white, location: min(1, max(0, phase))),
                .init(color: Ink.faint, location: min(1, phase + 0.3)),
            ], startPoint: .leading, endPoint: .trailing))
            .lineLimit(1)
            .onAppear {
                guard animated else { phase = 0.5; return }
                withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) { phase = 1.3 }
            }
    }
}
