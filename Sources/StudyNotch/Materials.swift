import Foundation
import PDFKit

struct Located {
    var file: String
    var page: Int
    var context: String
}

/// The part of a course an AI may open by itself, read-only: the course as that AI's project.
struct CourseFiles: Equatable {
    /// Every PDF of the course as plain text, one file each, with a mark before every page.
    var text: String
    /// The PDFs copied into the course's own folder.
    var pdfs: String
    /// How many PDFs the course has.
    var count: Int
    /// The folders handed to the AI: it works in the first and may read the others.
    var folders: [String] { [text, pdfs] }
}

/// What a course's PDF is (the user's request, 2026-11-25: the app sorts a course's files by
/// itself). The course's own copies live in a folder of this name inside `materials`; PDFs in
/// linked folders stay where they are and are only grouped by it.
enum MaterialKind: String, CaseIterable, Codable {
    case outline = "Course outline"
    case lectureNotes = "Lecture notes"
    case courseNotes = "Course notes"
    case assignments = "Assignments"
    case quizzes = "Quizzes"
    case exams = "Exams"
    case examPrep = "Exam prep"
    case other = "Other"

    /// Pure: the words of a file name or a page, lowercased, with letters and digits apart
    /// ("Quiz3_sol.pdf" → quiz, 3, sol, pdf).
    static func words(_ text: String) -> [String] {
        var out: [String] = []
        var word = ""
        var digits = false
        for ch in text.lowercased() {
            let isLetter = ch.isLetter, isDigit = ch.isNumber
            guard isLetter || isDigit else {
                if !word.isEmpty { out.append(word) }
                word = ""
                continue
            }
            if !word.isEmpty, digits != isDigit {
                out.append(word)
                word = ""
            }
            word.append(ch)
            digits = isDigit
        }
        if !word.isEmpty { out.append(word) }
        return out
    }

    /// Pure: a PDF's kind from its file name, else the name of the folder it is in (a linked
    /// "Quizzes" folder), else the top of its first page.
    static func of(name: String, folder: String = "", firstPage: String = "") -> MaterialKind {
        let stem = (name as NSString).deletingPathExtension
        return fromName(words(stem)) ?? fromName(words(folder)) ?? fromPage(words(String(firstPage.prefix(300)))) ?? .other
    }

    /// A word is one of these, or one of them with -s or -es ("quizzes" is listed itself).
    /// Whole words only, so "examples" is not an exam and "testing" not a test.
    private static func has(_ words: [String], _ stems: [String]) -> Bool {
        words.contains { word in stems.contains { word == $0 || word == $0 + "s" || word == $0 + "es" } }
    }

    /// One of these words followed by a number ("a 2", "ch 4", "quiz 3").
    private static func numbered(_ words: [String], _ heads: [String]) -> Bool {
        zip(words, words.dropFirst()).contains { heads.contains($0) && $1.first?.isNumber == true }
    }

    private static let examWords = ["midterm", "final", "exam", "examination", "test", "mt"]
    private static let quizWords = ["quiz", "quizzes"]

    private static func fromName(_ w: [String]) -> MaterialKind? {
        if has(w, ["outline", "syllabus"]) { return .outline }
        // Practice material, and reviews or sheets made for a test, before the tests themselves.
        // "Sample" and "formula" alone are statistics and calculus words, not a test's.
        if has(w, ["practice", "mock", "prep", "preparation"])
            || (has(w, ["sheet"]) && has(w, ["formula", "cheat", "aid", "crib"]))
            || (has(w, ["review", "sample", "aid", "guide"]) && has(w, examWords + quizWords)) { return .examPrep }
        if has(w, examWords) { return .exams }
        if has(w, quizWords) { return .quizzes }
        if has(w, ["assignment", "homework", "hw", "pset"]) || numbered(w, ["a"])
            || zip(w, w.dropFirst()).contains(where: { $0 == "problem" && ($1 == "set" || $1 == "sets") }) { return .assignments }
        if has(w, ["lecture", "lec", "slide", "week"]) { return .lectureNotes }
        if has(w, ["note", "chapter", "textbook", "book", "handout", "module"]) || numbered(w, ["ch"]) { return .courseNotes }
        return nil
    }

    /// The top of a page is a weaker sign than a name: it needs a test's title words, or a number
    /// where a title has one ("Quiz 3"), so "a test statistic" or "before the midterm" isn't read
    /// as a test.
    private static func fromPage(_ w: [String]) -> MaterialKind? {
        let text = " " + w.joined(separator: " ") + " "
        if text.contains(" course outline ") || text.contains(" syllabus ") { return .outline }
        if text.contains(" practice ") && (has(w, examWords) || numbered(w, quizWords)) { return .examPrep }
        if text.contains(" midterm exam") || text.contains(" final exam") || numbered(w, ["test", "exam", "midterm"]) { return .exams }
        if numbered(w, quizWords) { return .quizzes }
        if numbered(w, ["assignment", "homework"]) { return .assignments }
        if numbered(w, ["lecture"]) { return .lectureNotes }
        return nil
    }
}

/// A PDF or a linked folder shown in a course's list.
struct CourseItem: Identifiable, Equatable {
    enum Kind { case folder, pdf }
    var url: URL
    var kind: Kind
    /// For a folder: how many PDFs are in it; nil when the folder can't be found.
    var count: Int?
    /// For one of the course's own PDFs: what it is (the folder it sits in).
    var group: MaterialKind?
    var id: String { url.path }
}

/// A course is a folder: ~/StudyNotch/Courses/<course>/{course.md, materials/<kind>/, log/, cards.md}.
/// It can also be linked to folders elsewhere on the Mac; their PDFs are read where they are.
final class CourseStore {
    static let shared = CourseStore()

    private struct Indexed {
        var stamp: Date
        var pages: [String]
        var normalized: [String]
    }

    private struct DiskCache: Codable {
        var stamp: Double
        var pages: [String]
    }

    private var cache: [String: Indexed] = [:]
    private let lock = NSLock()

    /// Moves something to the Mac's Trash. The tests swap it for a plain delete, so they leave
    /// nothing behind in the real Trash.
    static var trasher: (URL) -> Bool = { (try? FileManager.default.trashItem(at: $0, resultingItemURL: nil)) != nil }

    /// Pure: the name of a course's folder. "/" and ":" can't be in a file name; "." and ".."
    /// would be the Courses folder itself and the one above it, never a folder of the course's own.
    static func folderName(_ course: String) -> String {
        let safe = course.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return safe == "." || safe == ".." ? String(repeating: "-", count: safe.count) : safe
    }

    /// Where a course's folder is (whether or not it has been made yet).
    func path(_ course: String) -> URL {
        Paths.courses.appendingPathComponent(Self.folderName(course), isDirectory: true)
    }

    func dir(_ course: String) -> URL {
        let url = path(course)
        let fm = FileManager.default
        for sub in ["materials", "log"] {
            try? fm.createDirectory(at: url.appendingPathComponent(sub, isDirectory: true), withIntermediateDirectories: true)
        }
        let note = url.appendingPathComponent("course.md")
        if !fm.fileExists(atPath: note.path) {
            let template = "# \(course)\n\n- Textbook:\n- Where we are:\n- Notation:\n"
            try? template.write(to: note, atomically: true, encoding: .utf8)
        }
        return url
    }

    func note(_ course: String) -> String {
        let text = (try? String(contentsOf: dir(course).appendingPathComponent("course.md"), encoding: .utf8)) ?? ""
        return String(text.prefix(4000))
    }

    /// The PDFs copied into the course's own folder: sorted ones in its kind folders, and any
    /// not sorted yet at the top.
    func ownMaterials(_ course: String) -> [URL] {
        let folder = path(course).appendingPathComponent("materials", isDirectory: true)
        let fm = FileManager.default
        var out: [URL] = []
        for item in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [] {
            if item.pathExtension.lowercased() == "pdf" {
                out.append(item)
            } else if Self.isFolder(item), item.lastPathComponent != "_text" {
                let inside = (try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
                out += inside.filter { $0.pathExtension.lowercased() == "pdf" }
            }
        }
        return out.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Sorting a course's files by kind

    /// What a course's PDF is: for its own copies, the kind folder it sits in; otherwise read
    /// from its name and first page.
    func kind(of pdf: URL) -> MaterialKind {
        if let sorted = MaterialKind(rawValue: pdf.deletingLastPathComponent().lastPathComponent),
           pdf.standardizedFileURL.path.hasPrefix(Paths.courses.standardizedFileURL.path + "/") {
            return sorted
        }
        return MaterialKind.of(name: pdf.lastPathComponent, folder: pdf.deletingLastPathComponent().lastPathComponent,
                               firstPage: index(pdf)?.pages.first ?? "")
    }

    /// Pure: a free file name in `folder` ("Quiz 1 (2).pdf" when "Quiz 1.pdf" is taken).
    static func freeName(_ name: String, in folder: URL) -> URL {
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var target = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        return target
    }

    /// Moves one of the course's own PDFs into the folder for `kind`, with its read text.
    /// Returns where it is now, or nil when it isn't one of the course's own PDFs.
    @discardableResult
    func move(_ pdf: URL, to kind: MaterialKind, course: String) -> URL? {
        let own = path(course).appendingPathComponent("materials", isDirectory: true)
        guard pdf.standardizedFileURL.path.hasPrefix(own.standardizedFileURL.path + "/") else { return nil }
        let folder = own.appendingPathComponent(kind.rawValue, isDirectory: true)
        if pdf.deletingLastPathComponent().standardizedFileURL.path == folder.standardizedFileURL.path { return pdf }
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = Self.freeName(pdf.lastPathComponent, in: folder)
        let oldText = Self.textCache(for: pdf, courses: Paths.courses, cache: Paths.textCache)
        guard (try? fm.moveItem(at: pdf, to: target)) != nil else { return nil }
        let newText = Self.textCache(for: target, courses: Paths.courses, cache: Paths.textCache)
        try? fm.createDirectory(at: newText.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.moveItem(at: oldText, to: newText)
        lock.lock()
        cache[pdf.path] = nil
        lock.unlock()
        return target
    }

    /// Puts the course's own PDFs that aren't in a kind folder yet into one. Nothing happens to
    /// linked folders. Returns how many moved.
    @discardableResult
    func sortOwn(_ course: String) -> Int {
        let own = path(course).appendingPathComponent("materials", isDirectory: true)
        let loose = ((try? FileManager.default.contentsOfDirectory(at: own, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "pdf" }
        return loose.filter { move($0, to: kind(of: $0), course: course) != nil }.count
    }

    /// Every PDF of the course grouped by kind, in the kinds' order. Linked folders are only read.
    func byKind(_ course: String, folders: [String] = []) -> [(kind: MaterialKind, pdfs: [URL])] {
        let all = materials(course, folders: folders)
        var groups: [MaterialKind: [URL]] = [:]
        for pdf in all { groups[kind(of: pdf), default: []].append(pdf) }
        return MaterialKind.allCases.compactMap { kind in
            groups[kind].map { (kind, $0.sorted { $0.lastPathComponent < $1.lastPathComponent }) }
        }
    }

    /// Every PDF of the course: its own, then the ones in its linked folders.
    func materials(_ course: String, folders: [String] = []) -> [URL] {
        var seen = Set<String>()
        return (ownMaterials(course) + folders.flatMap { Self.pdfs(in: URL(fileURLWithPath: $0)) })
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    static func isFolder(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    /// The PDFs in a linked folder and the folders inside it (three levels down, 300 at most, no
    /// hidden files, nothing inside app bundles). Empty when the folder is gone.
    static func pdfs(in folder: URL, limit: Int = 300) -> [URL] {
        guard isFolder(folder),
              let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [URL] = []
        for case let url as URL in walker {
            // Level 1 is the folder's own contents; a PDF three folders down is at level 4.
            if walker.level > 4 { walker.skipDescendants(); continue }
            if url.pathExtension.lowercased() == "pdf" {
                out.append(url)
                if out.count >= limit { break }
            }
        }
        return out.sorted { $0.path < $1.path }
    }

    /// What a course's list shows: its linked folders first, then its own PDFs by kind.
    func items(_ course: String, folders: [String]) -> [CourseItem] {
        let own = ownMaterials(course).map { (pdf: $0, kind: kind(of: $0)) }
            .sorted { a, b in
                let ia = MaterialKind.allCases.firstIndex(of: a.kind)!, ib = MaterialKind.allCases.firstIndex(of: b.kind)!
                return ia != ib ? ia < ib : a.pdf.lastPathComponent < b.pdf.lastPathComponent
            }
        var list = Self.items(folders.map { URL(fileURLWithPath: $0) } + own.map(\.pdf))
        for i in list.indices where list[i].kind == .pdf {
            list[i].group = own.first { $0.pdf == list[i].url }?.kind
        }
        return list
    }

    /// Folders with their PDF counts (nil when missing), and PDFs, in the order given.
    static func items(_ urls: [URL]) -> [CourseItem] {
        urls.map { url in
            if url.pathExtension.lowercased() == "pdf", !isFolder(url) { return CourseItem(url: url, kind: .pdf, count: nil) }
            return CourseItem(url: url, kind: .folder, count: isFolder(url) ? pdfs(in: url).count : nil)
        }
    }

    /// Pure: where a PDF's read text is kept. Next to the PDF inside our own course folders; for a
    /// PDF in a linked folder, in our cache, so the student's folder is never written to.
    static func textCache(for pdf: URL, courses: URL, cache: URL) -> URL {
        let path = pdf.standardizedFileURL.path
        if path.hasPrefix(courses.standardizedFileURL.path + "/") {
            return pdf.deletingLastPathComponent().appendingPathComponent("_text", isDirectory: true)
                .appendingPathComponent(pdf.lastPathComponent + ".json")
        }
        // FNV-1a: the same file always gets the same name, on every launch.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in path.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return cache.appendingPathComponent(String(hash, radix: 16) + ".json")
    }

    /// Letters and digits only, lowercased: line breaks, hyphenation and spacing in a PDF no longer matter.
    static func normalize(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars where CharacterSet.alphanumerics.contains(scalar) {
            out.append(scalar)
        }
        return String(out)
    }

    private func index(_ url: URL) -> Indexed? {
        let stamp = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date) ?? .distantPast
        lock.lock()
        if let hit = cache[url.path], hit.stamp == stamp {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let cacheFile = Self.textCache(for: url, courses: Paths.courses, cache: Paths.textCache)
        let textDir = cacheFile.deletingLastPathComponent()
        var pages: [String]?
        if let data = try? Data(contentsOf: cacheFile),
           let disk = try? JSONDecoder().decode(DiskCache.self, from: data),
           disk.stamp == stamp.timeIntervalSince1970 {
            pages = disk.pages
        }
        if pages == nil {
            guard let doc = PDFDocument(url: url) else { return nil }
            var read: [String] = []
            read.reserveCapacity(doc.pageCount)
            for i in 0..<doc.pageCount {
                read.append(doc.page(at: i)?.string ?? "")
            }
            pages = read
            try? FileManager.default.createDirectory(at: textDir, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(DiskCache(stamp: stamp.timeIntervalSince1970, pages: read)) {
                try? data.write(to: cacheFile, options: .atomic)
            }
        }
        let result = Indexed(stamp: stamp, pages: pages ?? [], normalized: (pages ?? []).map(Self.normalize))
        lock.lock()
        cache[url.path] = result
        lock.unlock()
        return result
    }

    /// A PDF's pages as text (read once, then kept).
    func pages(of pdf: URL) -> [String] {
        index(pdf)?.pages ?? []
    }

    /// Reads every PDF of the course once so the first question does not wait for it, and brings
    /// the course's project folder up to date. It runs in the background, so the course may have
    /// been renamed or removed by the time it starts: it never makes the course's folder.
    func warm(_ course: String, folders: [String] = []) {
        sortOwn(course)
        syncText(course, folders: folders, make: false)
    }

    // MARK: - The course as an AI's project

    /// Pure: the name of a PDF's text copy. Two PDFs with one name (in different folders) get "(2)".
    static func textName(for pdf: URL, taken: inout Set<String>) -> String {
        let base = pdf.deletingPathExtension().lastPathComponent
        var name = base + ".txt"
        var n = 2
        while taken.contains(name.lowercased()) {
            name = "\(base) (\(n)).txt"
            n += 1
        }
        taken.insert(name.lowercased())
        return name
    }

    /// Pure: a PDF as plain text. The line before each page is what lets an AI say "p.4".
    static func textFile(name: String, pages: [String]) -> String {
        pages.enumerated().map { index, page in
            "=== \(name), page \(index + 1) ===\n" + page.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        }.joined(separator: "\n")
    }

    /// Keeps `<course>/text` in step with the course's PDFs, its own and the linked folders':
    /// one text file per PDF, rewritten when the PDF changed, removed when the PDF left the
    /// course. This folder, with the copied PDFs, is what the connected AI may open by itself.
    /// Linked folders are only read. Returns nil when the course has no PDF, or, with `make`
    /// off, when the course's folder isn't there.
    @discardableResult
    func syncText(_ course: String, folders: [String], make: Bool = true) -> CourseFiles? {
        let fm = FileManager.default
        let home = make ? dir(course) : path(course)
        let textDir = home.appendingPathComponent("text", isDirectory: true)
        try? fm.createDirectory(at: textDir, withIntermediateDirectories: make)
        guard make || Self.isFolder(textDir) else { return nil }
        var names = Set<String>()
        let pdfs = materials(course, folders: folders)
        for pdf in pdfs {
            let name = Self.textName(for: pdf, taken: &names)
            guard let indexed = index(pdf) else { continue }
            let target = textDir.appendingPathComponent(name)
            // A text copy carries its PDF's date. Any other date means the PDF changed or the
            // name belonged to another PDF (an older one included): write it again.
            let have = (try? fm.attributesOfItem(atPath: target.path))?[.modificationDate] as? Date
            if have.map({ abs($0.timeIntervalSince(indexed.stamp)) > 0.001 }) ?? true {
                try? Self.textFile(name: pdf.lastPathComponent, pages: indexed.pages)
                    .write(to: target, atomically: true, encoding: .utf8)
                try? fm.setAttributes([.modificationDate: indexed.stamp], ofItemAtPath: target.path)
            }
        }
        for old in (try? fm.contentsOfDirectory(at: textDir, includingPropertiesForKeys: nil)) ?? []
        where old.pathExtension == "txt" && !names.contains(old.lastPathComponent.lowercased()) {
            try? fm.removeItem(at: old)
        }
        guard !pdfs.isEmpty else { return nil }
        return CourseFiles(text: textDir.path, pdfs: home.appendingPathComponent("materials", isDirectory: true).path, count: pdfs.count)
    }

    /// Finds the page that holds the selected sentence. Returns nil when no page matches.
    func locate(_ selection: String, course: String, hint: String?, folders: [String] = []) -> Located? {
        let chars = Array(Self.normalize(selection))
        guard chars.count >= 8 else { return nil }
        let window = min(36, chars.count)
        var probes = [String(chars.prefix(window))]
        if chars.count > window * 2 {
            let mid = chars.count / 2 - window / 2
            probes.append(String(chars[mid..<(mid + window)]))
        }
        if chars.count > window {
            probes.append(String(chars.suffix(window)))
        }

        let hintText = (hint ?? "").lowercased()
        let files = materials(course, folders: folders).sorted { a, b in
            let aHit = hintText.contains(a.deletingPathExtension().lastPathComponent.lowercased())
            let bHit = hintText.contains(b.deletingPathExtension().lastPathComponent.lowercased())
            return aHit && !bHit
        }

        var best: (score: Int, file: URL, page: Int, indexed: Indexed)?
        search: for file in files {
            guard let indexed = index(file) else { continue }
            for (i, page) in indexed.normalized.enumerated() where !page.isEmpty {
                let score = probes.reduce(0) { $0 + (page.contains($1) ? 1 : 0) }
                if score > (best?.score ?? 0) {
                    best = (score, file, i, indexed)
                    if score == probes.count { break search }
                }
            }
        }
        guard let hit = best else { return nil }

        var context = String(hit.indexed.pages[hit.page].prefix(3500))
        if hit.page + 1 < hit.indexed.pages.count {
            let next = hit.indexed.pages[hit.page + 1].prefix(700)
            if !next.isEmpty { context += "\n\n[Start of the next page]\n" + next }
        }
        return Located(file: hit.file.lastPathComponent, page: hit.page + 1, context: context)
    }

    /// Copies a PDF into the course, straight into the folder for its kind.
    @discardableResult
    func addMaterial(_ source: URL, course: String) -> Bool {
        guard source.pathExtension.lowercased() == "pdf" else { return false }
        if ownMaterials(course).contains(where: { $0.lastPathComponent == source.lastPathComponent }) { return true }
        let firstPage = MaterialKind.of(name: source.lastPathComponent) == .other
            ? (PDFDocument(url: source)?.page(at: 0)?.string ?? "") : ""
        let kind = MaterialKind.of(name: source.lastPathComponent, firstPage: firstPage)
        let folder = dir(course).appendingPathComponent("materials", isDirectory: true)
            .appendingPathComponent(kind.rawValue, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(source.lastPathComponent))
            return true
        } catch {
            return false
        }
    }

    /// Moves one of the course's own PDFs to the Trash (and forgets its read text).
    @discardableResult
    func trashMaterial(_ url: URL, course: String) -> Bool {
        let own = dir(course).appendingPathComponent("materials", isDirectory: true).standardizedFileURL.path
        guard url.standardizedFileURL.path.hasPrefix(own + "/") else { return false }
        let cacheFile = Self.textCache(for: url, courses: Paths.courses, cache: Paths.textCache)
        guard Self.trasher(url) else { return false }
        try? FileManager.default.removeItem(at: cacheFile)
        lock.lock()
        cache[url.path] = nil
        lock.unlock()
        return true
    }

    /// Renames the course's folder. False when the new name's folder is already there.
    @discardableResult
    func rename(_ old: String, to new: String) -> Bool {
        let from = path(old), to = path(new)
        guard from.path != to.path else { return true }
        let fm = FileManager.default
        guard fm.fileExists(atPath: from.path) else { return true }
        // A name that differs only by capitals is the same folder on most Macs: go through a spare name.
        if from.path.lowercased() == to.path.lowercased() {
            let spare = from.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
            return (try? fm.moveItem(at: from, to: spare)) != nil && (try? fm.moveItem(at: spare, to: to)) != nil
        }
        guard !fm.fileExists(atPath: to.path) else { return false }
        return (try? fm.moveItem(at: from, to: to)) != nil
    }

    /// Moves the course's whole folder (notes, log, cards, copied PDFs) to the Trash. Linked
    /// folders are not touched.
    @discardableResult
    func trash(_ course: String) -> Bool {
        let folder = path(course)
        guard FileManager.default.fileExists(atPath: folder.path) else { return true }
        return Self.trasher(folder)
    }

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func append(_ text: String, to url: URL) {
        guard var data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forUpdating: url) {
            defer { try? handle.close() }
            // A file edited by hand may end without a newline (memory.md asks for lines to be
            // deleted); the new text would join its last line.
            if let size = try? handle.seekToEnd(), size > 0, (try? handle.seek(toOffset: size - 1)) != nil,
               let last = try? handle.read(upToCount: 1), last != Data([0x0A]) {
                data.insert(0x0A, at: 0)
            }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    func appendLog(course: String, quote: String?, question: String, answer: String) {
        let file = dir(course).appendingPathComponent("log", isDirectory: true)
            .appendingPathComponent(Self.dayFormat.string(from: Date()) + ".md")
        var entry = "\n## \(Self.timeFormat.string(from: Date())) \(question)\n\n"
        if let quote, !quote.isEmpty { entry += "> " + quote.replacingOccurrences(of: "\n", with: " ") + "\n\n" }
        entry += answer + "\n"
        append(entry, to: file)
    }

    // MARK: - The course's profile: how it is taught and tested

    /// The kinds a profile is written from.
    static let profileKinds: [MaterialKind] = [.outline, .quizzes, .exams, .examPrep, .assignments]

    /// `<course>/profile.md`, as the AI last wrote it (empty when there is none).
    func profile(_ course: String) -> String {
        let text = (try? String(contentsOf: path(course).appendingPathComponent("profile.md"), encoding: .utf8)) ?? ""
        return String(text.prefix(5000))
    }

    func profileDate(_ course: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path(course).appendingPathComponent("profile.md").path))?[.modificationDate] as? Date
    }

    func saveProfile(_ course: String, text: String) {
        try? text.write(to: dir(course).appendingPathComponent("profile.md"), atomically: true, encoding: .utf8)
    }

    /// Pure: the text a profile is written from: the first pages of each file, marked with its
    /// name and page so the AI can say where a fact is, and no more than `limit` characters.
    /// Every file's first page goes in before any file's second, so a few long files can't use up
    /// the room the others need; each file's pages still come out together, in the files' order.
    static func profileSources(_ files: [(name: String, pages: [String])], pagesEach: Int = 3, limit: Int = 30000) -> String {
        var taken = Array(repeating: [String](), count: files.count)
        // A file whose next page didn't fit gives no more pages.
        var full = Array(repeating: false, count: files.count)
        var used = 0
        for page in 0..<pagesEach {
            for (f, file) in files.enumerated() where !full[f] && page < file.pages.count {
                let body = file.pages[page].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !body.isEmpty else { continue }
                let block = "=== \(file.name), page \(page + 1) ===\n" + String(body.prefix(2500)) + "\n\n"
                guard used + block.count <= limit else { full[f] = true; continue }
                taken[f].append(block)
                used += block.count
            }
        }
        return taken.flatMap { $0 }.joined()
    }

    /// Pure: the groups a profile is written from, in `profileKinds`' order: the outline, then the
    /// quizzes, exams and exam prep, and the assignments last (`byKind` puts them before the quizzes).
    static func profileGroups(_ groups: [(kind: MaterialKind, pdfs: [URL])]) -> [(kind: MaterialKind, pdfs: [URL])] {
        profileKinds.compactMap { kind in groups.first { $0.kind == kind } }
    }

    /// The course's outline, quizzes, exams, exam prep and assignments, as `profileSources`.
    func profileSources(_ course: String, folders: [String]) -> (text: String, kinds: [(kind: MaterialKind, names: [String])]) {
        let groups = Self.profileGroups(byKind(course, folders: folders))
        let files = groups.flatMap(\.pdfs).map { (name: $0.lastPathComponent, pages: pages(of: $0)) }
        return (Self.profileSources(files), groups.map { ($0.kind, $0.pdfs.map(\.lastPathComponent)) })
    }

    // MARK: - The course's memory: what was asked in it before

    /// Pure: one line of a course's memory: the day, the question, the picked text and where the
    /// answer came from ("Source: Lecture 5.pdf p.4" at its end).
    static func memoryLine(date: Date, question: String, quote: String?, answer: String) -> String {
        func oneLine(_ text: String, _ limit: Int) -> String {
            let flat = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            return flat.count > limit ? String(flat.prefix(limit - 1)) + "…" : flat
        }
        var line = "- \(dayFormat.string(from: date)) · \(oneLine(question, 80))"
        if let quote, !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            line += " · “\(oneLine(quote, 70))”"
        }
        let source = answer.components(separatedBy: "\n").reversed()
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " *_`")) }
            .first { $0.hasPrefix("Source:") }
            .map { String($0.dropFirst("Source:".count)).trimmingCharacters(in: .whitespaces) }
        if let source, !source.isEmpty { line += " · \(oneLine(source, 60))" }
        return line
    }

    /// The course's memory, oldest first: one line per question answered in it.
    func memory(_ course: String) -> [String] {
        let file = path(course).appendingPathComponent("memory.md")
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        return text.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    }

    /// Adds a question to the course's memory, so the course's next questions know it was asked.
    func remember(course: String, line: String) {
        let file = dir(course).appendingPathComponent("memory.md")
        if !FileManager.default.fileExists(atPath: file.path) {
            try? "# What was asked in \(course)\n\nStudyNotch adds a line after each answer and sends the latest ones with every question in this course. Delete lines you don't want remembered.\n\n"
                .write(to: file, atomically: true, encoding: .utf8)
        }
        append(line + "\n", to: file)
    }

    func appendCard(course: String, front: String, back: String) {
        let file = dir(course).appendingPathComponent("cards.md")
        let entry = "\n## \(front.replacingOccurrences(of: "\n", with: " "))\n\n\(back)\n"
        append(entry, to: file)
    }
}
