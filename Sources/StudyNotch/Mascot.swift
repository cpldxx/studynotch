import SwiftUI

/// StudyNotch's own mascot, Squat: a small round body of glossy black with two
/// white painted eyes that follow the pointer. It is drawn here from scratch. Like the character in
/// Coucou's island it lives in the island all the time: in the left ear when folded, large on the
/// left of an opened card, springing from one place to the other.
enum MascotMood: Equatable {
    /// Resting: Highlighter ovals. Blinks now and then and glances to one side.
    case rest
    /// The pointer is on it, or it has just been patted: a Highlighter smile.
    case happy
    /// An answer is being written: violet eyes looking up and to the right.
    case thinking
    /// A session is running and the student is on task: green eyes, half closed.
    case focus
    /// The student wandered off: amber eyes, wide, looking away.
    case drift
    /// A break: white eyes, asleep.
    case sleep
    /// A session just ended: a green smile.
    case proud
    /// Not tied to anything yet: sky eyes with the outer corners lowered.
    case sad
    /// Not tied to anything yet: red eyes with the inner corners lowered.
    case angry

    /// An answer on its way matters more than the pointer passing over.
    static func of(busy: Bool, hover: Bool) -> MascotMood {
        if busy { return .thinking }
        return hover ? .happy : .rest
    }

    /// The mood the island shows, from the most to the least urgent.
    static func of(busy: Bool, hover: Bool, drift: Bool, resting: Bool, inSession: Bool, finished: Bool) -> MascotMood {
        if busy { return .thinking }
        if drift { return .drift }
        if hover { return .happy }
        if finished { return .proud }
        if resting { return .sleep }
        return inSession ? .focus : .rest
    }

    /// Ovals can blink and glance; a smile or sleeping eyes can't.
    var glances: Bool { self == .rest || self == .focus }

    /// Ovals look at the pointer; a smile or sleeping eyes stay where they are.
    var eyesFollow: Bool { self != .happy && self != .proud && self != .sleep }

    /// The faint light behind it in an opened island: the state's colour, white when nothing is going on.
    var glow: Color {
        switch self {
        case .focus, .proud: return Ink.Glow.green
        case .drift: return Ink.Glow.amber
        case .thinking: return Ink.Glow.violet
        case .rest, .sleep, .happy, .sad, .angry: return .white
        }
    }

    var glowStrength: Double {
        switch self {
        case .focus, .proud, .drift, .thinking: return 0.45
        default: return 0.14
        }
    }
}

/// Where the pointer is as seen from the mascot, each axis -1...1 (y grows downwards).
/// The island controller writes it about twenty times a second.
final class PointerLook: ObservableObject {
    static let shared = PointerLook()
    @Published var vector = CGVector.zero

    /// Pure: the direction from `from` to `to` (both in view coordinates, y down), at full length
    /// once the pointer is `reach` points away, shorter when it is close.
    static func vector(from: CGPoint, to: CGPoint, reach: CGFloat = 160) -> CGVector {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.5 else { return .zero }
        let k = min(1, length / reach) / length
        return CGVector(dx: dx * k, dy: dy * k)
    }

    func update(_ next: CGVector) {
        if abs(next.dx - vector.dx) > 0.02 || abs(next.dy - vector.dy) > 0.02 { vector = next }
    }
}

/// The faint light behind the mascot in an opened island, in the state's colour.
struct MascotGlow: View {
    let mood: MascotMood
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(RadialGradient(gradient: Gradient(stops: [
                .init(color: mood.glow, location: 0),
                .init(color: .clear, location: 0.62),
            ]), center: .center, startRadius: 0, endRadius: size * 1.1))
            .frame(width: size * 2.2, height: size * 2.2)
            .blur(radius: 6)
            .opacity(mood.glowStrength)
            .animation(.easeInOut(duration: 0.4), value: mood)
            .allowsHitTesting(false)
    }
}

struct MascotView: View {
    var mood: MascotMood
    var height: CGFloat = 18
    /// Off for still pictures (`--render`), where nothing should be caught halfway through a blink.
    var animated: Bool = true
    /// Where the pointer is, each axis -1...1 (y down). The eyes follow it and the body turns a little.
    var look: CGVector = .zero
    /// Bump to make it hop once (a pat).
    var hop: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    /// What it showed before the latest change, and when the change began.
    @State private var from: MascotLook?
    @State private var shown: MascotMood?
    @State private var changedAt = Date.distantPast
    @State private var blinkAt = Date.distantPast
    @State private var glance: Float = 0
    @State private var glanceFrom: Float = 0
    @State private var glanceAt = Date.distantPast
    /// The pointer look, eased: from where it was to where it is now.
    @State private var aimFrom = CGVector.zero
    @State private var aimAt = Date.distantPast
    /// Frames are drawn only while something moves.
    @State private var ticking = false
    @State private var tickUntil = Date.distantPast
    @State private var squash: CGFloat = 0
    @State private var lift: CGFloat = 0

    /// Squat is drawn in a square.
    static let aspect: CGFloat = 1
    static let change = 0.4
    static let blinkLength = 0.18
    static let aimTime = 0.16

    var body: some View {
        let moving = animated && !reduceMotion
        Group {
            if moving {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !ticking)) { timeline in
                    picture(look(at: timeline.date), keep: !ticking && look == .zero)
                }
            } else {
                picture(look(at: Date()), keep: look == .zero)
            }
        }
        .frame(width: height * Self.aspect, height: height)
        .scaleEffect(x: 1 + squash * 0.12, y: 1 - squash * 0.16, anchor: .bottom)
        .offset(y: -lift)
        .onAppear { shown = mood }
        .onChange(of: mood) { next in
            guard moving else { shown = next; return }
            let now = Date()
            let before = look(at: now)
            from = before
            shown = next
            changedAt = now
            if before.shape != MascotLook.of(next).shape || before.shape == 0 { blinkAt = now }
            tick(Self.change + 0.05)
        }
        .task(id: moving) {
            // Blinks and glances at random times: alive, never a loop.
            guard moving else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 2.0...6.0) * 1e9))
                if Task.isCancelled { break }
                let now = Date()
                if mood.glances && Double.random(in: 0...1) < 0.45 {
                    glanceFrom = currentGlance(at: now)
                    glance = Double.random(in: 0...1) < 0.4 ? 0 : Float.random(in: -0.6...0.6)
                    glanceAt = now
                    if Double.random(in: 0...1) < 0.5 { blinkAt = now }
                    tick(Self.change)
                } else {
                    blinkAt = now
                    tick(Self.blinkLength + 0.05)
                }
            }
        }
        .onChange(of: look) { _ in
            guard moving else { return }
            aimFrom = currentAim(at: Date())
            aimAt = Date()
            tick(Self.aimTime)
        }
        .onChange(of: hop) { _ in
            guard moving else { return }
            // Crouch, jump, land: squash and stretch, a few frames each.
            withAnimation(.easeOut(duration: 0.08)) { squash = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) {
                    squash = -0.6
                    lift = height * 0.28
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
                    squash = 0
                    lift = 0
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var target: MascotLook { MascotLook.of(mood) }

    private func currentGlance(at date: Date) -> Float {
        let k = Float(min(1, max(0, date.timeIntervalSince(glanceAt) / Self.change)))
        let eased = k * k * (3 - 2 * k)
        return glanceFrom + (glance - glanceFrom) * eased
    }

    /// The pointer look at a moment, eased from the last one so the eyes glide rather than jump.
    private func currentAim(at date: Date) -> CGVector {
        let k = min(1, max(0, date.timeIntervalSince(aimAt) / Self.aimTime))
        let e = k * k * (3 - 2 * k)
        return CGVector(dx: aimFrom.dx + (look.dx - aimFrom.dx) * e, dy: aimFrom.dy + (look.dy - aimFrom.dy) * e)
    }

    /// Pure: a look aimed at the pointer (each axis -1...1, y down). The eyes slide toward it on the
    /// face and the body turns toward it, so the two add up. The shader's turn is positive to the
    /// left as seen from the camera; turning with the same sign as the slide made them cancel
    /// (measured with `--eyes-sweep`), and the eyes hardly moved.
    static func aimed(_ base: MascotLook, at aim: CGVector, eyes: Bool) -> MascotLook {
        var l = base
        if eyes {
            l.look.x += Float(aim.dx) * 1.25
            l.look.y -= Float(aim.dy) * 1.5
        }
        l.turn = -Float(aim.dx) * 0.2
        return l
    }

    /// What it looks like at a moment: easing from the last look, following the pointer, blinking, glancing.
    private func look(at date: Date) -> MascotLook {
        let aim = currentAim(at: date)
        var goal = Self.aimed(target, at: aim, eyes: mood.eyesFollow)
        if mood.glances && aim == .zero { goal.look.x += currentGlance(at: date) }
        var l = goal
        let since = date.timeIntervalSince(changedAt)
        if let from, since < Self.change {
            let k = Float(since / Self.change)
            l = MascotLook.mix(from, goal, k * k * (3 - 2 * k), swap: Float(Self.blinkLength / 2 / Self.change))
        }
        l.blink = Self.blink(sinceStart: date.timeIntervalSince(blinkAt))
        return l
    }

    /// A blink closes and opens again over `blinkLength`; 1 is shut.
    static func blink(sinceStart t: Double) -> Float {
        guard t >= 0, t < blinkLength else { return 0 }
        let u = t / blinkLength
        return Float(u < 0.5 ? u * 2 : 2 - u * 2)
    }

    private func tick(_ seconds: Double) {
        let until = Date().addingTimeInterval(seconds)
        if until > tickUntil { tickUntil = until }
        ticking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.05) {
            if Date() >= tickUntil { ticking = false }
        }
    }

    @ViewBuilder
    private func picture(_ look: MascotLook, keep: Bool) -> some View {
        let pixels = Int((height * Self.aspect * max(displayScale, 1)).rounded())
        if let image = MascotRenderer.shared?.image(look, pixels: pixels, keep: keep) {
            Image(decorative: image, scale: max(displayScale, 1))
                .resizable()
                .interpolation(.high)
        } else {
            // Without Metal: the same face, flat.
            Canvas { context, size in
                let w = size.width, h = size.height
                context.fill(Path(ellipseIn: CGRect(x: w * 0.06, y: h * 0.12, width: w * 0.88, height: h * 0.84)),
                             with: .color(Color(white: 0.08)))
                let color = Color(red: Double(look.eye.x), green: Double(look.eye.y), blue: Double(look.eye.z))
                for x in [w * 0.34, w * 0.66] {
                    context.fill(Path(ellipseIn: CGRect(x: x - w * 0.07, y: h * 0.38, width: w * 0.14, height: h * 0.24)),
                                 with: .color(color))
                }
            }
        }
    }
}

/// What the mascot says after a pat. Short, about the session, never a lecture.
enum MascotLines {
    static func pick(session: ActiveSession?, drift: Bool, todayMinutes: Int, index: Int) -> String {
        let lines: [String]
        if let s = session {
            if s.restUntil != nil {
                lines = ["Rest well", "Glass of water?"]
            } else if drift {
                lines = ["Shall we go back?", "Just a little more"]
            } else {
                let minutes = s.focusSeconds / 60
                lines = [minutes > 0 ? "\(minutes) min of focus" : "Well begun is half done",
                         "Stuck? Right-click it",
                         "Nice, keep going"]
            }
        } else {
            lines = [todayMinutes > 0 ? "\(todayMinutes) min today" : "Ready to study?",
                     "Pick a course to start",
                     "Nice to see you"]
        }
        return lines[abs(index) % lines.count]
    }
}
