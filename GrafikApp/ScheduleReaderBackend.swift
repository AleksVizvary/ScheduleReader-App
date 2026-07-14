import Foundation
import SwiftUI

final class ScheduleReaderBackend: ObservableObject {
    @Published var employees: [Employee] = [
        Employee(name: "Aleksander Vizváry"),
        Employee(name: "Marcin Chełpa"),
        Employee(name: "Malwina Walus"),
        Employee(name: "Dorota Hazik"),
        Employee(name: "Dariusz Dutkiewicz"),
        Employee(name: "Małgorzata Janowska"),
        Employee(name: "Anna Majewska"),
        Employee(name: "Grzegorz")
    ]

    @Published var workHourBugs: [WorkHourBug] = [
        WorkHourBug(text: ",-"),
        WorkHourBug(text: "-,")
    ]

    @Published var generatedFiles: [GeneratedScheduleFile] = []

    private let eventName = "Praca"
    private let address = "ul. Pawia 5, 31-154, Kraków, Polska"

    var bossName: String {
        employees.indices.contains(7) ? employees[7].name : employees.last?.name ?? ""
    }

    func generateSchedule(sourceURL: URL, employee: Employee, month: String, customName: String) throws -> GeneratedScheduleFile {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let readableURL = try csvReadableURL(for: sourceURL)
        let source = try String(contentsOf: readableURL, encoding: .utf8)
        let schedule = parseScheduleCSV(source)
        let events = makeCalendarEvents(schedule: schedule, client: employee.name)
        let ics = makeICS(events: events)
        let fileURL = try save(ics: ics, employee: employee, month: month, customName: customName)

        let generated = GeneratedScheduleFile(
            fileName: fileURL.lastPathComponent,
            employeeName: employee.name,
            month: month,
            sourceFileName: sourceURL.lastPathComponent,
            createdAt: Date(),
            fileURL: fileURL
        )
        generatedFiles.insert(generated, at: 0)
        return generated
    }

    private func parseScheduleCSV(_ source: String) -> [(date: Date, people: [String: WorkShift?])] {
        var schedule: [(date: Date, people: [String: WorkShift?])] = []
        let rows = source
            .split(whereSeparator: \.isNewline)
            .map { splitCSVLine(String($0)) }

        for row in rows {
            for cell in row {
                if let date = parseDate(cell) {
                    let day = Dictionary(uniqueKeysWithValues: employees.map { ($0.name, Optional<WorkShift>.none) })
                    schedule.append((date: date, people: day))
                }
            }

            guard !schedule.isEmpty else { continue }
            let employee = employeeIn(row: row)

            for cell in row {
                if let shift = parseWorkHours(cell), let employee {
                    schedule[schedule.count - 1].people[employee] = shift
                }
            }
        }

        return schedule
    }

    private func employeeIn(row: [String]) -> String? {
        for employee in employees where row.contains(where: { $0.localizedCaseInsensitiveContains(employee.name) }) {
            return employee.name
        }
        return nil
    }

    private func parseWorkHours(_ raw: String) -> WorkShift? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        for bug in workHourBugs where !bug.text.isEmpty {
            value = value.replacingOccurrences(of: bug.text, with: "-")
        }
        value = value.replacingOccurrences(of: ",", with: "")
        value = value.replacingOccurrences(of: " ", with: "")

        let parts = value.split(separator: "-", omittingEmptySubsequences: true)
        guard parts.count == 2,
              let start = Int(parts[0]),
              let end = Int(parts[1]),
              (0...24).contains(start),
              (0...24).contains(end) else { return nil }
        return WorkShift(startHour: start, endHour: end)
    }

    private func parseDate(_ raw: String) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let formats = ["dd.MM.yyyy", "d.MM.yyyy", "yyyy-MM-dd", "dd/MM/yyyy", "d/MM/yyyy"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private func makeCalendarEvents(schedule: [(date: Date, people: [String: WorkShift?])], client: String) -> [CalendarEvent] {
        schedule.compactMap { day in
            createDescription(day: day.people, client: client).map { result in
                CalendarEvent(date: day.date, shift: result.shift, description: result.description)
            }
        }
    }

    private func createDescription(day: [String: WorkShift?], client: String) -> (shift: WorkShift, description: String)? {
        var myShift: WorkShift?
        var thoseWorking: [(name: String, shift: WorkShift)] = []
        var thoseHavingDayOff: [(name: String, status: String)] = []

        for employee in employees {
            let name = employee.name
            let hours = day[name] ?? nil
            if name != client, let hours {
                thoseWorking.append((name: name, shift: hours))
            } else if name == client {
                myShift = hours
            } else if name != client {
                thoseHavingDayOff.append((name: name, status: "wolne"))
            }
        }

        guard let myShift else { return nil }

        var description = ""
        if isThereBoss(myShift: myShift, peopleOnShift: thoseWorking) {
            description = "\tZMIANA Z G\n"
        }

        thoseWorking.sort { left, right in
            if left.shift.startHour == right.shift.startHour {
                return left.shift.endHour < right.shift.endHour
            }
            return left.shift.startHour < right.shift.startHour
        }

        description += thoseWorking
            .map { "\($0.name): \($0.shift.startHour)-\($0.shift.endHour)\n" }
            .joined()
        description += thoseHavingDayOff
            .map { "\($0.name): \($0.status)\n" }
            .joined()

        return (shift: myShift, description: description)
    }

    private func isThereBoss(myShift: WorkShift, peopleOnShift: [(name: String, shift: WorkShift)]) -> Bool {
        for shift in peopleOnShift {
            if (shift.shift.startHour == myShift.startHour || shift.shift.endHour == myShift.endHour) && shift.name == bossName {
                return true
            }
        }
        return false
    }

    private func makeICS(events: [CalendarEvent]) -> String {
        var lines = [
            "BEGIN:VCALENDAR",
            "PRODID:-//My calendar product//example.com//",
            "VERSION:2.0"
        ]

        for event in events {
            lines.append(contentsOf: makeVEVENT(event))
        }

        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private func makeVEVENT(_ event: CalendarEvent) -> [String] {
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: event.shift.startHour, minute: 0, second: 0, of: event.date) ?? event.date
        let end = calendar.date(bySettingHour: event.shift.endHour, minute: 0, second: 0, of: event.date) ?? event.date

        return [
            "BEGIN:VEVENT",
            "SUMMARY:\(escapeICS(eventName))",
            "DTSTART:\(icsDateFormatter.string(from: start))",
            "DTEND:\(icsDateFormatter.string(from: end))",
            "DESCRIPTION:\(escapeICS(event.description))",
            "LOCATION:\(escapeICS(address))",
            "END:VEVENT"
        ]
    }

    private var icsDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }

    private func escapeICS(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func save(ics: String, employee: Employee, month: String, customName: String) throws -> URL {
        let sanitizedEmployee = employee.name.replacingOccurrences(of: " ", with: "_")
        let fallbackName = "grafik_\(month)_\(sanitizedEmployee).ics"
        var finalName = customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackName : customName
        if !finalName.lowercased().hasSuffix(".ics") {
            finalName += ".ics"
        }

        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScheduleReader", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(finalName)
        try ics.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func csvReadableURL(for sourceURL: URL) throws -> URL {
        guard sourceURL.pathExtension.lowercased() == "xlsx" else { return sourceURL }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("csv")

        if FileManager.default.fileExists(atPath: temporaryURL.path) {
            try FileManager.default.removeItem(at: temporaryURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: temporaryURL)
        return temporaryURL
    }

    private func splitCSVLine(_ line: String) -> [String] {
        let delimiter: Character = line.contains(";") ? ";" : ","
        return line.split(separator: delimiter, omittingEmptySubsequences: false).map(String.init)
    }
}
