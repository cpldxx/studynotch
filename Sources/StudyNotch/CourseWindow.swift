import AppKit
import PDFKit
import SwiftUI

/// What the course window shows. One window, for one course at a time.
final class CourseWindowState: ObservableObject {
    enum Tab: String, CaseIterable { case graph = "Graph", files = "Files" }

    @Published var course = ""
    @Published var tab: Tab = .graph
    @Published var graph: CourseGraph?
    @Published var files: [(kind: MaterialKind, pdfs: [URL])] = []
    @Published var linked: Set<String> = []
    @Published var loading = false
    @Published var selected: String?
    @Published var hovered: String?
    private var token = 0

    /// Reads the course's files and builds its graph off the main thread.
    func load(_ course: String, folders: [String]) {
        if course != self.course {
            selected = nil
            hovered = nil
            graph = nil
            files = []
        }
        self.course = course
        loading = true
        token += 1
        let mine = token
        DispatchQueue.global(qos: .userInitiated).async {
            CourseStore.shared.sortOwn(course)
            let files = CourseStore.shared.byKind(course, folders: folders)
            let graph = CourseStore.shared.graph(course, folders: folders)
            let linked = Set(folders.flatMap { CourseStore.pdfs(in: URL(fileURLWithPath: $0)).map(\.path) })
            DispatchQueue.main.async {
                guard mine == self.token else { return }
                self.files = files
                self.linked = linked
                self.graph = graph
                self.loading = false
            }
        }
    }
}

/// The course window: opened from "Graph" on a course's card.
final class CourseWindowController {
    private let model: AppModel
    private let state = CourseWindowState()
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show(_ course: String) {
        state.load(course, folders: model.config.folders(for: course))
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 700),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            // The course's name is in our own header, beside the window's buttons.
            w.titleVisibility = .hidden
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = .black
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 760, height: 480)
            // StudyNotch lives in the menu bar, so this window is often not the front one: a click on a
            // dot picks it at once instead of only bringing the window forward.
            w.contentView = FirstClickHostingView(rootView: CourseWindowView(state: state))
            w.center()
            window = w
        }
        window?.title = course
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct CourseWindowView: View {
    @ObservedObject var state: CourseWindowState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(state.course).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(Self.summary(state.graph, files: state.files.reduce(0) { $0 + $1.pdfs.count }, loading: state.loading))
                    .font(.system(size: 11.5)).foregroundColor(Ink.icon).lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    ForEach(CourseWindowState.Tab.allCases, id: \.self) { tab in
                        Button { state.tab = tab } label: {
                            Text(tab.rawValue).font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(state.tab == tab ? Ink.text : Ink.icon)
                                .padding(.horizontal, 12).frame(height: 26)
                                .background(Capsule().fill(state.tab == tab ? Ink.tabOn : Color.clear))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(Springy())
                        .testTag("Course tab \(tab.rawValue)")
                    }
                }
                .padding(3)
                .background(Capsule().fill(Ink.pill))
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
            .frame(height: 52)

            Group {
                switch state.tab {
                case .graph: GraphPane(state: state)
                case .files: FilesPane(state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
        .foregroundColor(Ink.text)
        .ignoresSafeArea()
    }

    /// Pure: "38 dots · 52 lines · 9 files".
    static func summary(_ graph: CourseGraph?, files: Int, loading: Bool) -> String {
        if loading && graph == nil { return "Reading the notes" }
        guard let graph else { return "" }
        return "\(counted(graph.nodes.count, "dot")) · \(counted(graph.edges.count, "line")) · \(counted(files, "file"))"
    }
}

// MARK: - Graph

struct GraphPane: View {
    @ObservedObject var state: CourseWindowState
    @State private var scale: CGFloat = 1
    @State private var pinch: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var drag: CGSize = .zero

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                if let graph = state.graph, !graph.nodes.isEmpty {
                    canvas(graph)
                } else if !state.loading {
                    Text(Self.emptyLine(files: state.files.contains { [.lectureNotes, .courseNotes, .other].contains($0.kind) }))
                        .font(.system(size: 13)).foregroundColor(Ink.icon)
                        .multilineTextAlignment(.center).frame(maxWidth: 420)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .clipped()
            SidePane(state: state)
                .frame(width: 340)
                .background(Ink.card)
        }
    }

    /// Pure: what an empty graph says.
    static func emptyLine(files: Bool) -> String {
        files ? "No numbered definitions, theorems or examples were found in this course’s notes. The graph reads headings like “Theorem 2.3” or “Definition (Limit)”."
              : "Add this course’s lecture or course notes to see how its definitions and theorems connect."
    }

    private func canvas(_ graph: CourseGraph) -> some View {
        GeometryReader { geo in
            let size = geo.size
            let focus = state.hovered ?? state.selected
            let near = Set(focus.map { id in graph.edges.compactMap { $0.from == id ? $0.to : ($0.to == id ? $0.from : nil) } + [id] } ?? [])
            let degrees = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, graph.degree($0.id)) })
            let busiest = Set(graph.nodes.sorted { degrees[$0.id]! > degrees[$1.id]! }.prefix(10).filter { degrees[$0.id]! >= 2 }.map(\.id))
            Canvas { ctx, _ in
                let points = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, place($0, in: size)) })
                for edge in graph.edges {
                    guard let a = points[edge.from], let b = points[edge.to] else { continue }
                    let lit = focus != nil && (edge.from == focus || edge.to == focus)
                    var line = Path()
                    line.move(to: a)
                    line.addLine(to: b)
                    ctx.stroke(line, with: .color(.white.opacity(lit ? 0.75 : (focus == nil ? 0.16 : 0.06))), lineWidth: lit ? 1.4 : 1)
                }
                for node in graph.nodes {
                    let p = points[node.id]!
                    let r = Self.radius(degrees[node.id] ?? 0, kind: node.kind)
                    let dim = focus != nil && !near.contains(node.id)
                    let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                    let ink = Color.white.opacity(dim ? 0.22 : 1)
                    switch node.kind {
                    case .definition:
                        ctx.fill(Path(ellipseIn: rect), with: .color(.black))
                        ctx.stroke(Path(ellipseIn: rect.insetBy(dx: 0.75, dy: 0.75)), with: .color(ink), lineWidth: 1.5)
                    case .theorem, .proposition:
                        ctx.fill(Path(ellipseIn: rect), with: .color(ink))
                    case .lemma, .corollary:
                        ctx.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(dim ? 0.15 : 0.62)))
                    case .example:
                        ctx.fill(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 1.5), with: .color(Color.white.opacity(dim ? 0.12 : 0.42)))
                    }
                    if node.id == state.selected {
                        ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(.white.opacity(0.8)), lineWidth: 1)
                    }
                    if near.contains(node.id) || (focus == nil && busiest.contains(node.id)) {
                        let label = ctx.resolve(Text(Self.shortLabel(node))
                            .font(.system(size: 11, weight: node.id == focus ? .semibold : .regular))
                            .foregroundColor(node.id == focus ? Ink.text : Ink.icon))
                        let at = CGPoint(x: p.x, y: p.y + r + 10)
                        let box = label.measure(in: CGSize(width: 260, height: 40))
                        // A dark backing, so lines running under a name don't cut through it.
                        ctx.fill(Path(roundedRect: CGRect(x: at.x - box.width / 2 - 4, y: at.y - box.height / 2 - 1,
                                                          width: box.width + 8, height: box.height + 2), cornerRadius: 4),
                                 with: .color(.black.opacity(0.72)))
                        ctx.draw(label, at: at, anchor: .center)
                    }
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let at): state.hovered = nearest(graph, to: at, in: size)
                case .ended: state.hovered = nil
                }
            }
            .gesture(DragGesture(minimumDistance: 4)
                .onChanged { drag = $0.translation }
                .onEnded { value in
                    offset.width += value.translation.width
                    offset.height += value.translation.height
                    drag = .zero
                })
            .simultaneousGesture(MagnificationGesture()
                .onChanged { pinch = $0 }
                .onEnded { value in
                    scale = min(4, max(0.5, scale * value))
                    pinch = 1
                })
            .onTapGesture(coordinateSpace: .local) { at in
                state.selected = nearest(graph, to: at, in: size)
            }
            .overlay(alignment: .bottomLeading) { legend.padding(16) }
        }
    }

    /// Where a dot goes: its layout spot inside the pane, clear of the legend at the bottom, then
    /// zoomed about the middle and moved by dragging.
    private func place(_ node: CourseGraph.Node, in size: CGSize) -> CGPoint {
        let s = scale * pinch
        let area = CGRect(x: 24, y: 12, width: max(1, size.width - 48), height: max(1, size.height - 64))
        let cx = area.midX, cy = area.midY
        return CGPoint(x: (area.minX + node.x * area.width - cx) * s + cx + offset.width + drag.width,
                       y: (area.minY + node.y * area.height - cy) * s + cy + offset.height + drag.height)
    }

    private func nearest(_ graph: CourseGraph, to point: CGPoint, in size: CGSize) -> String? {
        var best: (id: String, d: CGFloat)?
        for node in graph.nodes {
            let p = place(node, in: size)
            let d = hypot(p.x - point.x, p.y - point.y)
            if d < 14, d < (best?.d ?? .infinity) { best = (node.id, d) }
        }
        return best?.id
    }

    static func radius(_ degree: Int, kind: CourseGraph.Kind) -> CGFloat {
        let base: CGFloat = kind == .example ? 3 : 4
        return base + min(7, CGFloat(degree).squareRoot() * 1.6)
    }

    /// Pure: what a dot is called on the graph: "Thm 2.3", or its name when it has one.
    static func shortLabel(_ node: CourseGraph.Node) -> String {
        if !node.name.isEmpty { return node.name }
        let short = ["Definition": "Def", "Theorem": "Thm", "Lemma": "Lemma", "Proposition": "Prop",
                     "Corollary": "Cor", "Example": "Ex"][node.kind.rawValue] ?? node.kind.rawValue
        return "\(short) \(node.number)"
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem("Definition") { Circle().stroke(Color.white, lineWidth: 1.5).frame(width: 9, height: 9) }
            legendItem("Theorem") { Circle().fill(Color.white).frame(width: 9, height: 9) }
            legendItem("Lemma, corollary") { Circle().fill(Color.white.opacity(0.62)).frame(width: 9, height: 9) }
            legendItem("Example") { RoundedRectangle(cornerRadius: 1.5).fill(Color.white.opacity(0.42)).frame(width: 8, height: 8) }
            Text("A line: one uses the other").font(.system(size: 11)).foregroundColor(Ink.faint)
        }
    }

    private func legendItem<S: View>(_ title: String, @ViewBuilder shape: () -> S) -> some View {
        HStack(spacing: 5) {
            shape()
            Text(title).font(.system(size: 11)).foregroundColor(Ink.icon)
        }
    }
}

/// Beside the graph: what is picked, what it uses and what uses it, and its page.
struct SidePane: View {
    @ObservedObject var state: CourseWindowState

    var body: some View {
        if let graph = state.graph, let id = state.selected, let node = graph.node(id) {
            VStack(alignment: .leading, spacing: 10) {
                Text(node.label).font(.system(size: 14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Text("\(node.file) p.\(node.page)").font(.system(size: 11.5)).foregroundColor(Ink.icon)
                links("Uses", graph.uses(id))
                links("Used by", graph.usedBy(id))
                PagePreview(path: node.path, page: node.page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                HStack(spacing: 12) {
                    QuietLink(title: "Open the PDF") { NSWorkspace.shared.open(URL(fileURLWithPath: node.path)) }
                    QuietLink(title: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)]) }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("How this course connects").font(.system(size: 14, weight: .semibold))
                Text("Each dot is a definition, theorem, lemma or example in this course’s notes. A line means one uses the other: it names it, like “by Theorem 2.3”, or uses the term a definition defines.")
                    .font(.system(size: 12.5)).foregroundColor(Ink.icon).fixedSize(horizontal: false, vertical: true)
                Text("Point at a dot to see its neighbours. Click it to see its page. Drag to move around, pinch to zoom.")
                    .font(.system(size: 12.5)).foregroundColor(Ink.icon).fixedSize(horizontal: false, vertical: true)
                Text("Read from the PDFs on this Mac. Nothing is sent to an AI.")
                    .font(.system(size: 11.5)).foregroundColor(Ink.faint).fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder private func links(_ title: String, _ nodes: [CourseGraph.Node]) -> some View {
        if !nodes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundColor(Ink.icon)
                ForEach(nodes.prefix(6)) { other in
                    Button { state.selected = other.id } label: {
                        Text(other.label).font(.system(size: 12)).foregroundColor(Ink.text).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if nodes.count > 6 {
                    Text("and \(nodes.count - 6) more").font(.system(size: 11.5)).foregroundColor(Ink.faint)
                }
            }
        }
    }
}

/// One page of a PDF, as a picture fitted to its box.
struct PagePreview: View {
    let path: String
    let page: Int

    /// The last page drawn, "path#page", for the click-through test.
    static var lastShown = ""
    private static var cache: [String: NSImage] = [:]

    var body: some View {
        if let image = Self.image(path, page) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Text("This page can’t be shown.").font(.system(size: 12)).foregroundColor(Ink.icon)
        }
    }

    static func image(_ path: String, _ page: Int) -> NSImage? {
        let key = "\(path)#\(page)"
        if let hit = cache[key] {
            lastShown = key
            return hit
        }
        guard let doc = PDFDocument(url: URL(fileURLWithPath: path)), let pdfPage = doc.page(at: page - 1) else { return nil }
        let box = pdfPage.bounds(for: .mediaBox)
        let scale = 1400 / max(box.width, box.height, 1)
        let image = pdfPage.thumbnail(of: CGSize(width: box.width * scale, height: box.height * scale), for: .mediaBox)
        if cache.count > 40 { cache.removeAll() }
        cache[key] = image
        lastShown = key
        return image
    }
}

// MARK: - Files

struct FilesPane: View {
    @ObservedObject var state: CourseWindowState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if state.files.isEmpty && !state.loading {
                    Text("No PDFs in this course yet. Add them with “Edit” on the course’s card.")
                        .font(.system(size: 13)).foregroundColor(Ink.icon)
                }
                ForEach(state.files, id: \.kind) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(group.kind.rawValue).font(.system(size: 12.5, weight: .semibold))
                            Text("\(group.pdfs.count)").font(.system(size: 11.5).monospacedDigit()).foregroundColor(Ink.icon)
                        }
                        ForEach(group.pdfs, id: \.path) { pdf in
                            Button { NSWorkspace.shared.open(pdf) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.text").font(.system(size: 11)).foregroundColor(Ink.icon)
                                    Text(pdf.lastPathComponent).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 8)
                                    Text(state.linked.contains(pdf.path) ? "In a linked folder" : "Copied into the course")
                                        .font(.system(size: 11)).foregroundColor(Ink.faint)
                                }
                                .padding(.horizontal, 10).frame(height: 26)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Open \(pdf.lastPathComponent)")
                        }
                    }
                }
            }
            .padding(.horizontal, 84)
            .padding(.vertical, 20)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }
}
