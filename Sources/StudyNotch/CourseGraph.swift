import Foundation

/// A course as a graph (the user's request, 2026-11-25: not a layered map like Repo Atlas, but a
/// graph of how things connect). Each dot is a definition, theorem, lemma, proposition, corollary
/// or example in the course's notes; a line means one uses the other, because it names it
/// ("by Theorem 2.3") or uses the term a definition defines. Built from the PDFs' text on the Mac,
/// with no AI, so it costs nothing and shows only what is written.
struct CourseGraph: Equatable {
    enum Kind: String, CaseIterable {
        case definition = "Definition", theorem = "Theorem", lemma = "Lemma"
        case proposition = "Proposition", corollary = "Corollary", example = "Example"

        /// The short forms a reference may use ("Thm 2.3", "Def. 1").
        static func from(_ word: String) -> Kind? {
            switch word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) {
            case "definition", "def": return .definition
            case "theorem", "thm": return .theorem
            case "lemma", "lem": return .lemma
            case "proposition", "prop": return .proposition
            case "corollary", "cor": return .corollary
            case "example", "ex": return .example
            default: return nil
            }
        }
    }

    struct Node: Identifiable, Equatable {
        /// The file and the key: "Lecture 5.pdf#Theorem 2.3".
        var id: String
        var kind: Kind
        /// "2.3", or empty for an unnumbered one with a name.
        var number: String
        /// "Mean Value Theorem", or empty.
        var name: String
        var file: String
        /// The PDF, to show its page.
        var path: String
        /// 1-based.
        var page: Int
        /// Where the layout put it, in 0...1 on both axes.
        var x: Double = 0.5
        var y: Double = 0.5

        var key: String { CourseGraph.key(kind, number: number, name: name) }
        var label: String {
            if number.isEmpty { return "\(kind.rawValue): \(name)" }
            return name.isEmpty ? "\(kind.rawValue) \(number)" : "\(kind.rawValue) \(number) (\(name))"
        }
    }

    /// `from` uses `to`.
    struct Edge: Hashable {
        var from: String
        var to: String
    }

    var nodes: [Node] = []
    var edges: [Edge] = []

    static func key(_ kind: Kind, number: String, name: String) -> String {
        number.isEmpty ? "\(kind.rawValue) (\(name.lowercased()))" : "\(kind.rawValue) \(number)"
    }

    func node(_ id: String) -> Node? { nodes.first { $0.id == id } }
    func uses(_ id: String) -> [Node] { edges.filter { $0.from == id }.compactMap { node($0.to) } }
    func usedBy(_ id: String) -> [Node] { edges.filter { $0.to == id }.compactMap { node($0.from) } }
    func degree(_ id: String) -> Int { edges.reduce(0) { $0 + ($1.from == id || $1.to == id ? 1 : 0) } }

    // MARK: - Reading it out of the notes (pure)

    /// A heading starts a line: the word, then a number or a name in brackets, then ".", ":", "("
    /// or the end of the line. "by\nTheorem 2.3 we have" (a reference broken onto a new line) is
    /// not a heading, because a word follows the number (and "3." of "3.3" isn't an end).
    private static let heading = try! NSRegularExpression(
        pattern: #"^[ \t]*(Definition|Theorem|Lemma|Proposition|Corollary|Example)s?[ \t]*(\d+(?:\.\d+)*)?[ \t]*(?:\(([^()\n]{2,60})\))?[ \t]*(?:[.:](?!\d)|$)"#,
        options: [.caseInsensitive, .anchorsMatchLines])

    private static let reference = try! NSRegularExpression(
        pattern: #"\b(Definition|Def|Theorem|Thm|Lemma|Lem|Proposition|Prop|Corollary|Cor|Example|Ex)\.?\s*(\d+(?:\.\d+)*)"#,
        options: [.caseInsensitive])

    /// Pure: whether the line before `location` is wrapped body text that runs on into it: at
    /// least 40 characters, ending in a small letter, a comma or an open bracket.
    static func continues(_ text: NSString, before location: Int) -> Bool {
        guard location > 1 else { return false }
        let lineEnd = location - 1
        let start = text.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: lineEnd)).location
        let from = start == NSNotFound ? 0 : start + 1
        let line = text.substring(with: NSRange(location: from, length: lineEnd - from)).trimmingCharacters(in: .whitespaces)
        guard line.count >= 40, let last = line.last else { return false }
        return last.isLowercase || last == "," || last == "("
    }

    /// Builds the graph from the notes' text: one entry per PDF, its pages in order.
    static func extract(_ files: [(file: String, path: String, pages: [String])], limit: Int = 400) -> CourseGraph {
        var nodes: [Node] = []
        var blocks: [String: String] = [:]
        for doc in files {
            // One text for the file, remembering where each page starts.
            var text = ""
            var starts: [Int] = []
            for page in doc.pages {
                starts.append((text as NSString).length)
                text += page + "\n"
            }
            let ns = text as NSString
            // The headings, first: a heading's text runs to the next real heading.
            var heads: [(at: Int, kind: Kind, number: String, name: String)] = []
            for match in heading.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard let kind = Kind.from(ns.substring(with: match.range(at: 1))) else { continue }
                let number = match.range(at: 2).location == NSNotFound ? "" : ns.substring(with: match.range(at: 2))
                let name = match.range(at: 3).location == NSNotFound ? ""
                    : ns.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
                // Needs a number or a name to be told apart.
                guard !number.isEmpty || !name.isEmpty else { continue }
                // A sentence that ends "... it rests on Theorem 2.5." can wrap so the reference starts
                // a line. Then the line before is long body text ending mid-sentence: not a heading.
                if name.isEmpty, Self.continues(ns, before: match.range.location) { continue }
                heads.append((match.range.location, kind, number, name))
            }
            var seen = Set<String>()
            for (i, head) in heads.enumerated() {
                // A repeated heading ("Theorem 2.3 (cont.)" on the next slide) counts once.
                let key = Self.key(head.kind, number: head.number, name: head.name)
                guard seen.insert(key).inserted else { continue }
                let page = (starts.lastIndex { $0 <= head.at } ?? 0) + 1
                let id = doc.file + "#" + key
                let end = i + 1 < heads.count ? heads[i + 1].at : ns.length
                blocks[id] = ns.substring(with: NSRange(location: head.at, length: min(1500, end - head.at)))
                nodes.append(Node(id: id, kind: head.kind, number: head.number, name: head.name, file: doc.file, path: doc.path, page: page))
            }
        }
        if nodes.count > limit { nodes = Array(nodes.prefix(limit)) }

        var edges = Set<Edge>()
        // References by number: the same file's first, else the only file that has it.
        var byKey: [String: [Node]] = [:]
        for node in nodes { byKey[node.key, default: []].append(node) }
        for node in nodes {
            guard let block = blocks[node.id] else { continue }
            let ns = block as NSString
            for match in reference.matches(in: block, range: NSRange(location: 0, length: ns.length)) {
                guard let kind = Kind.from(ns.substring(with: match.range(at: 1))) else { continue }
                let key = Self.key(kind, number: ns.substring(with: match.range(at: 2)), name: "")
                guard key != node.key, let candidates = byKey[key] else { continue }
                let target = candidates.first { $0.file == node.file } ?? (candidates.count == 1 ? candidates[0] : nil)
                if let target, target.id != node.id { edges.insert(Edge(from: node.id, to: target.id)) }
            }
        }
        // Terms: a definition with a name ("Definition 2.1 (Limit)") is used wherever its name
        // appears, unless the word is everywhere (then it says nothing).
        // Line breaks and runs of spaces don't split a term ("partial\nderivative").
        let lowered = nodes.map { node in
            (id: node.id, text: (blocks[node.id] ?? "").lowercased().components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }.joined(separator: " "))
        }
        for def in nodes where def.kind == .definition {
            let term = def.name.lowercased()
            let words = term.split(separator: " ")
            guard term.count >= 4, (1...4).contains(words.count),
                  let pattern = try? NSRegularExpression(pattern: "\\b" + NSRegularExpression.escapedPattern(for: term) + "\\b") else { continue }
            let users = lowered.filter { $0.id != def.id && pattern.firstMatch(in: $0.text, range: NSRange(location: 0, length: ($0.text as NSString).length)) != nil }
            guard users.count <= max(3, nodes.count * 2 / 5) else { continue }
            for user in users { edges.insert(Edge(from: user.id, to: def.id)) }
        }
        var graph = CourseGraph(nodes: nodes, edges: edges.sorted { ($0.from, $0.to) < ($1.from, $1.to) })
        graph.layOut()
        return graph
    }

    // MARK: - Layout (pure, the same every time)

    /// Spring layout (Fruchterman–Reingold): lines pull their dots together, all dots push each
    /// other apart, and a little pull to the middle keeps loose dots from drifting off.
    mutating func layOut(iterations: Int = 220) {
        let n = nodes.count
        guard n > 0 else { return }
        let index = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })
        let links = edges.compactMap { e -> (Int, Int)? in
            guard let a = index[e.from], let b = index[e.to], a != b else { return nil }
            return (a, b)
        }
        // Start on a golden-angle spiral, in the order the notes give them.
        var px = [Double](repeating: 0, count: n), py = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let r = 0.45 * sqrt((Double(i) + 0.5) / Double(n))
            let a = Double(i) * 2.399963
            px[i] = 0.5 + r * cos(a)
            py[i] = 0.5 + r * sin(a)
        }
        let k = 0.9 * sqrt(1.0 / Double(n))
        var heat = 0.1
        for _ in 0..<iterations {
            var dx = [Double](repeating: 0, count: n), dy = [Double](repeating: 0, count: n)
            for i in 0..<n {
                for j in (i + 1)..<max(i + 1, n) {
                    var vx = px[i] - px[j], vy = py[i] - py[j]
                    var d2 = vx * vx + vy * vy
                    if d2 < 1e-9 { vx = 0.001 * Double(i - j); vy = 0.001; d2 = vx * vx + vy * vy }
                    let f = k * k / d2
                    dx[i] += vx * f; dy[i] += vy * f
                    dx[j] -= vx * f; dy[j] -= vy * f
                }
            }
            for (a, b) in links {
                let vx = px[a] - px[b], vy = py[a] - py[b]
                let d = max(1e-6, sqrt(vx * vx + vy * vy))
                let f = d / k
                dx[a] -= vx * f; dy[a] -= vy * f
                dx[b] += vx * f; dy[b] += vy * f
            }
            for i in 0..<n {
                dx[i] -= (px[i] - 0.5) * 0.6 / k
                dy[i] -= (py[i] - 0.5) * 0.6 / k
                let d = max(1e-9, sqrt(dx[i] * dx[i] + dy[i] * dy[i]))
                let step = min(d, heat)
                px[i] += dx[i] / d * step
                py[i] += dy[i] / d * step
            }
            heat = max(0.002, heat * 0.975)
        }
        // Into 0.06...0.94 on both axes, keeping the shape.
        let minX = px.min()!, maxX = px.max()!, minY = py.min()!, maxY = py.max()!
        let span = max(maxX - minX, maxY - minY, 1e-6)
        for i in 0..<n {
            nodes[i].x = 0.06 + 0.88 * ((px[i] - minX) / span + (span - (maxX - minX)) / span / 2)
            nodes[i].y = 0.06 + 0.88 * ((py[i] - minY) / span + (span - (maxY - minY)) / span / 2)
        }
    }
}

extension CourseStore {
    /// The course's graph, from its lecture notes, course notes and the files of no kind.
    func graph(_ course: String, folders: [String]) -> CourseGraph {
        let notes = byKind(course, folders: folders).filter { [.lectureNotes, .courseNotes, .other].contains($0.kind) }
        let files = notes.flatMap(\.pdfs).map { pdf in (file: pdf.lastPathComponent, path: pdf.path, pages: pages(of: pdf)) }
        return CourseGraph.extract(files)
    }
}
