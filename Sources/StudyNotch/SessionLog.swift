import Foundation

struct SessionRecord: Codable {
    var course: String
    var task: String
    var start: Date
    var end: Date
    var plannedMinutes: Int
    var focusSeconds: Int
    var distractSeconds: Int
    var questions: [String]
}

/// One JSON line per finished session in ~/StudyNotch/sessions.jsonl.
enum SessionLog {
    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func append(_ record: SessionRecord) {
        Paths.ensure()
        guard var data = try? encoder.encode(record) else { return }
        data.append(0x0A)
        if let handle = try? FileHandle(forUpdating: Paths.sessions) {
            defer { try? handle.close() }
            // A log that ends in the middle of a line (the Mac went down while it was written) would
            // take this session into that line, and neither could be read again.
            if let size = try? handle.seekToEnd(), size > 0, (try? handle.seek(toOffset: size - 1)) != nil,
               let last = try? handle.read(upToCount: 1), last != Data([0x0A]) {
                data.insert(0x0A, at: 0)
            }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: Paths.sessions)
        }
    }

    static func all() -> [SessionRecord] {
        guard let text = try? String(contentsOf: Paths.sessions, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(SessionRecord.self, from: data)
        }
    }

    /// A course was renamed: its past sessions follow it, so "stuck last time" still finds them.
    /// Only that course's lines are written again. Every other line, one that can't be read included,
    /// stays as it is: the log is the student's record, and a rename is no reason to drop any of it.
    static func rename(_ old: String, to new: String) {
        guard let text = try? String(contentsOf: Paths.sessions, encoding: .utf8) else { return }
        var changed = false
        var data = Data()
        for line in text.split(separator: "\n") {
            var out = Data(line.utf8)
            if var record = try? decoder.decode(SessionRecord.self, from: out), record.course == old {
                record.course = new
                guard let written = try? encoder.encode(record) else { return }
                out = written
                changed = true
            }
            data.append(out)
            data.append(0x0A)
        }
        guard changed else { return }
        try? data.write(to: Paths.sessions, options: .atomic)
    }

    /// The questions asked in the most recent session of this course that had any.
    static func lastStuck(course: String) -> [String] {
        for record in all().reversed() where AppConfig.renamed(record.course) == course && !record.questions.isEmpty {
            return Array(record.questions.suffix(3))
        }
        return []
    }
}

/// One day's study, for the record tab.
struct DayTotal: Equatable {
    var day: Date
    var minutes: Int
}

struct DayStats: Equatable {
    var minutes = 0
    var sessions = 0
    var questions = 0
}

/// Pure sums over the session log. A session counts on the day it ended; only focused time counts.
enum StudyStats {
    static func today(_ records: [SessionRecord], now: Date, calendar: Calendar = .current) -> DayStats {
        var stats = DayStats()
        for r in records where calendar.isDate(r.end, inSameDayAs: now) {
            stats.minutes += r.focusSeconds / 60
            stats.sessions += 1
            stats.questions += r.questions.count
        }
        return stats
    }

    /// The seven days that end today, oldest first.
    static func week(_ records: [SessionRecord], now: Date, calendar: Calendar = .current) -> [DayTotal] {
        let todayStart = calendar.startOfDay(for: now)
        var days = (0..<7).reversed().compactMap { back -> DayTotal? in
            calendar.date(byAdding: .day, value: -back, to: todayStart).map { DayTotal(day: $0, minutes: 0) }
        }
        for r in records {
            let start = calendar.startOfDay(for: r.end)
            if let i = days.firstIndex(where: { $0.day == start }) { days[i].minutes += r.focusSeconds / 60 }
        }
        return days
    }
}
