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

/// A PDF or a linked folder shown in a course's list.
struct CourseItem: Identifiable, Equatable {
    enum Kind { case folder, pdf }
    var url: URL
    var kind: Kind
    /// For a folder: how many PDFs are in it; nil when the folder can't be found.
    var count: Int?
    var id: String { url.path }
}

/// A course is a folder: ~/StudyNotch/Courses/<course>/{course.md, materials/, log/, cards.md}.
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

    /// Where a course's folder is (whether or not it has been made yet).
    func path(_ course: String) -> URL {
        let safe = course.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return Paths.courses.appendingPathComponent(safe, isDirectory: true)
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

    /// The PDFs copied into the course's own folder.
    func ownMaterials(_ course: String) -> [URL] {
        let folder = dir(course).appendingPathComponent("materials", isDirectory: true)
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.pathExtension.lowercased() == "pdf" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
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

    /// What a course's list shows: its linked folders first, then its own PDFs.
    func items(_ course: String, folders: [String]) -> [CourseItem] {
        Self.items(folders.map { URL(fileURLWithPath: $0) } + ownMaterials(course))
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

    /// Reads every PDF of the course once so the first question does not wait for it, and brings
    /// the course's project folder up to date.
    func warm(_ course: String, folders: [String] = []) {
        syncText(course, folders: folders)
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
    /// Linked folders are only read. Returns nil when the course has no PDF.
    @discardableResult
    func syncText(_ course: String, folders: [String]) -> CourseFiles? {
        let fm = FileManager.default
        let home = dir(course)
        let textDir = home.appendingPathComponent("text", isDirectory: true)
        try? fm.createDirectory(at: textDir, withIntermediateDirectories: true)
        var names = Set<String>()
        let pdfs = materials(course, folders: folders)
        for pdf in pdfs {
            let name = Self.textName(for: pdf, taken: &names)
            guard let indexed = index(pdf) else { continue }
            let target = textDir.appendingPathComponent(name)
            let have = (try? fm.attributesOfItem(atPath: target.path))?[.modificationDate] as? Date
            if have == nil || have! < indexed.stamp {
                try? Self.textFile(name: pdf.lastPathComponent, pages: indexed.pages)
                    .write(to: target, atomically: true, encoding: .utf8)
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

    @discardableResult
    func addMaterial(_ source: URL, course: String) -> Bool {
        guard source.pathExtension.lowercased() == "pdf" else { return false }
        let target = dir(course).appendingPathComponent("materials", isDirectory: true)
            .appendingPathComponent(source.lastPathComponent)
        if FileManager.default.fileExists(atPath: target.path) { return true }
        do {
            try FileManager.default.copyItem(at: source, to: target)
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
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
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

    func appendCard(course: String, front: String, back: String) {
        let file = dir(course).appendingPathComponent("cards.md")
        let entry = "\n## \(front.replacingOccurrences(of: "\n", with: " "))\n\n\(back)\n"
        append(entry, to: file)
    }
}
