import Foundation

struct AskPreset: Identifiable, Equatable {
    let id: String
    let label: String
    let prompt: String
}

enum Prompts {
    static let dontGet = AskPreset(id: "dontget", label: "I don’t get this",
                                   prompt: "I don’t understand this part. Explain what it means, starting with the key idea.")
    static let easier = AskPreset(id: "easier", label: "Simpler",
                                  prompt: "Explain that again much more simply, so someone seeing it for the first time can follow.")
    static let example = AskPreset(id: "example", label: "Example",
                                   prompt: "Show this with one concrete example.")
    static let summary = AskPreset(id: "summary", label: "One-line summary",
                                   prompt: "Sum this part up in one or two sentences.")
    static let steps = AskPreset(id: "steps", label: "Step by step",
                                 prompt: "Explain step by step how to solve this problem or equation, and why each step is needed.")
    static let again = AskPreset(id: "again", label: "Explain again",
                                 prompt: "Explain that again in a different way.")

    /// Shown right after a selection.
    static let offerText = [dontGet, easier, example, summary]
    /// Shown right after a screenshot or capture.
    static let offerImage = [dontGet, steps, summary]
    /// "Where are you stuck?" under the first answer.
    static let narrow = [
        AskPreset(id: "symbols", label: "What the symbols mean", prompt: "Explain each symbol and term here, one by one."),
        AskPreset(id: "why", label: "Why it holds", prompt: "Explain step by step why this holds."),
        AskPreset(id: "use", label: "Where it’s used", prompt: "Tell me where and how this is used, and how it shows up in problems."),
    ]
    static let followUps = [easier, example, again]

    /// What "Send" sends: the picked preset, what the student typed, or both together.
    static func compose(preset: AskPreset?, extra: String) -> (prompt: String, display: String)? {
        let text = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if let preset {
            if text.isEmpty { return (preset.prompt, preset.label) }
            return (preset.prompt + "\n\nThe student adds: " + text, preset.label + " · " + text)
        }
        return text.isEmpty ? nil : (text, text)
    }

    /// The answer follows what the student typed with this question: Korean words get a Korean answer.
    /// English words, or a button alone (its label is English), get an English one.
    static func answerLanguage(typed: String) -> String {
        let hangul = typed.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
        return hangul ? "ko" : "en"
    }

    /// `language` is en or ko, from `answerLanguage(typed:)`.
    static func system(language: String) -> String {
        let lang = language.lowercased().hasPrefix("ko")
            ? "Answer in Korean. The first time a technical term appears, give the original English term once in parentheses."
            : "Answer in English."
        return """
        You are a teaching assistant sitting next to a university student while they study. The student asks about a passage they selected in a textbook or lecture material, or about a screen capture.

        Rules:
        1. \(lang)
        2. Keep the first answer short: 3 to 5 sentences. Go into detail only when the student asks for more.
        3. Write maths in LaTeX: $...$ inside a sentence, $$...$$ for an equation on its own line.
        4. When a course material excerpt is given, use its notation and terms exactly. If the answer is based on the excerpt, end with the line `Source: <file name> p.<page>`.
        5. If there is no excerpt, or it has nothing to do with the question, answer from general knowledge and end with the line `Source: not from your files`. Never make it look as if the answer came from the materials.
        6. When a `<course_files>` section is given, you may open those files yourself, read-only. Do it only when the excerpt doesn’t cover the question, search the text copies first, and don’t narrate that you are looking. The files are listed by kind: to see how a topic is tested in this course, look in its quizzes and exams. If the answer rests on a page you opened, end with `Source: <file name> p.<page>` for that page.
        7. If it looks like an assignment or exam question, don’t give only the answer: explain how to solve it and why.
        8. No greeting, no restating the question, no closing remarks.
        """
    }

    /// Pure: the course's files by kind, at most 12 names a kind, for the AI to know what to open.
    static func kindList(_ kinds: [(kind: MaterialKind, names: [String])]) -> String {
        guard !kinds.isEmpty else { return "" }
        var out = "The files by kind:\n"
        for group in kinds {
            let shown = group.names.prefix(12).joined(separator: ", ")
            let more = group.names.count > 12 ? ", and \(group.names.count - 12) more" : ""
            out += "- \(group.kind.rawValue): \(shown)\(more)\n"
        }
        return out
    }

    static func user(course: String, note: String, located: Located?, quote: String?, hasImage: Bool,
                     sourceApp: String, sourceTitle: String, history: [(q: String, a: String)], question: String,
                     files: CourseFiles? = nil, kinds: [(kind: MaterialKind, names: [String])] = [],
                     memory: [String] = []) -> String {
        var parts: [String] = []
        if !course.isEmpty, course != AppConfig.generalCourse {
            parts.append("<course>\(course)</course>")
        }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty {
            parts.append("<course_notes>\n\(trimmedNote)\n</course_notes>")
        }
        if !memory.isEmpty {
            // Shared by every question in the course, like a project's memory.
            parts.append("""
            <course_memory>
            What the student asked earlier in this course, oldest first. Connect this answer to it when it helps; don't repeat old answers.
            \(memory.suffix(15).joined(separator: "\n"))
            </course_memory>
            """)
        }
        if let located {
            parts.append("<course_material_excerpt file=\"\(located.file)\" page=\"\(located.page)\">\n\(located.context)\n</course_material_excerpt>")
        }
        if let files {
            // The course as this AI's project: where its files are, for it to open when it needs to.
            parts.append("""
            <course_files>
            This course has \(files.count) PDF\(files.count == 1 ? "" : "s"). You can open them yourself, read-only.
            - Every PDF as plain text, one .txt file each, with a line `=== <file name>, page <n> ===` before every page: \(files.text) (you are working in this folder; search it first)
            - The PDFs copied into the course, one folder per kind: \(files.pdfs)
            \(kindList(kinds))</course_files>
            """)
        }
        if !sourceApp.isEmpty {
            let title = sourceTitle.isEmpty ? "" : " · Window: \(sourceTitle)"
            parts.append("<reading_in>App: \(sourceApp)\(title)</reading_in>")
        }
        if let quote, !quote.isEmpty {
            parts.append("<selected_passage>\n\(quote)\n</selected_passage>")
        }
        if hasImage {
            parts.append("A screen capture is attached. The student is asking about that capture.")
        }
        if !history.isEmpty {
            var block = "<earlier_conversation>\n"
            for turn in history.suffix(4) {
                block += "Student: \(turn.q)\nAssistant: \(turn.a)\n"
            }
            parts.append(block + "</earlier_conversation>")
        }
        parts.append("<question>\n\(question)\n</question>")
        return parts.joined(separator: "\n\n")
    }
}
