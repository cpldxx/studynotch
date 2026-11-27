import AppKit

let arguments = CommandLine.arguments

if arguments.contains("--selftest") {
    exit(DevTools.selfTest() ? 0 : 1)
}

if arguments.contains("--eyes-sweep") {
    DevTools.eyesSweep()
    exit(0)
}

if arguments.contains("--answertest") {
    let ok = MainActor.assumeIsolated { DevTools.answerTest() }
    exit(ok ? 0 : 1)
}

if arguments.contains("--asktest-claude-app") {
    let ok = MainActor.assumeIsolated { DevTools.askClaudeAppTest() }
    exit(ok ? 0 : 1)
}

if arguments.contains("--asktest-profile") {
    let ok = MainActor.assumeIsolated { DevTools.askProfileTest() }
    exit(ok ? 0 : 1)
}

if arguments.contains("--asktest-memory") {
    let ok = MainActor.assumeIsolated { DevTools.askMemoryTest() }
    exit(ok ? 0 : 1)
}

if arguments.contains("--asktest-course") {
    exit(DevTools.askCourseTest() ? 0 : 1)
}

if let index = arguments.firstIndex(of: "--asktest") {
    let image = index + 1 < arguments.count ? arguments[index + 1] : nil
    exit(DevTools.askTest(imagePath: image) ? 0 : 1)
}

if let index = arguments.firstIndex(of: "--render-site"), index + 1 < arguments.count {
    DevTools.render(to: arguments[index + 1], forSite: true)
    exit(0)
}

if let index = arguments.firstIndex(of: "--render"), index + 1 < arguments.count {
    DevTools.render(to: arguments[index + 1])
    exit(0)
}

// `--uitest`: the real app in a throw-away home, clicked through by `UITest`.
if UITest.active { UITest.prepare() }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// No Dock icon and no app menu: it lives in the notch and the menu bar.
app.setActivationPolicy(.accessory)
app.run()
