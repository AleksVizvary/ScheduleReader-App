import Combine
#if canImport(CoreXLSX)
import CoreXLSX
#endif
import Foundation

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

        let schedule = try parseSchedule(from: sourceURL)
        let events = makeCalendarEvents(schedule: schedule, client: employee.name)
        guard !events.isEmpty else { throw ScheduleReaderError.noShiftsForEmployee }

        let ics = makeICS(events: events)
        guard ics.contains("BEGIN:VEVENT") else { throw ScheduleReaderError.noShiftsForEmployee }

        let fileURL: URL
        do {
            fileURL = try save(ics: ics, employee: employee, month: month, customName: customName)
        } catch {
            throw ScheduleReaderError.icsWriteFailed
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { throw ScheduleReaderError.icsWriteFailed }

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

    private func parseSchedule(from sourceURL: URL) throws -> [(date: Date, people: [String: WorkShift?])] {
        switch sourceURL.pathExtension.lowercased() {
        case "csv":
            let source: String
            do {
                source = try String(contentsOf: sourceURL, encoding: .utf8)
            } catch {
                throw ScheduleReaderError.unreadableSource
            }
            return try validated(schedule: parseScheduleCSV(source))
        case "xlsx":
            return try validated(schedule: parseScheduleXLSX(sourceURL))
        default:
            throw ScheduleReaderError.unsupportedExtension
        }
    }

    private func parseScheduleCSV(_ source: String) -> [(date: Date, people: [String: WorkShift?])] {
        var schedule: [(date: Date, people: [String: WorkShift?])] = []
        let rows = source
            .split(whereSeparator: \.isNewline)
            .map { splitCSVLine(String($0)) }

        for row in rows {
            for cell in row {
                if let date = parseDate(cell) {
                    let day = emptyDay()
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

    private func parseScheduleXLSX(_ sourceURL: URL) throws -> [(date: Date, people: [String: WorkShift?])] {
#if canImport(CoreXLSX)
        guard let file = XLSXFile(filepath: sourceURL.path) else { throw ScheduleReaderError.unreadableXLSX }
        let sharedStrings = try? file.parseSharedStrings()
        _ = try? file.parseStyles()

        let worksheetPaths: [String]
        do {
            worksheetPaths = try file.parseWorksheetPaths()
        } catch {
            throw ScheduleReaderError.unreadableXLSX
        }
        guard let worksheetPath = worksheetPaths.first else { throw ScheduleReaderError.noWorksheet }

        let worksheet: Worksheet
        do {
            worksheet = try file.parseWorksheet(at: worksheetPath)
        } catch {
            throw ScheduleReaderError.unreadableXLSX
        }
        guard let rows = worksheet.data?.rows, !rows.isEmpty else { throw ScheduleReaderError.noWorksheet }

        var dateByColumn: [Int: Date] = [:]
        var scheduleByDay: [Date: [String: WorkShift?]] = [:]
        var recognizedEmployees = Set<String>()

        for row in rows {
            var rowValues: [(column: Int, text: String, date: Date?)] = []
            for cell in row.cells {
                let text = xlsxText(for: cell, sharedStrings: sharedStrings)
                let date = cell.dateValue ?? parseDate(text)
                let column = columnIndex(from: String(describing: cell.reference))
                rowValues.append((column: column, text: text, date: date))

                if let date {
                    dateByColumn[column] = date
                    if scheduleByDay[date] == nil {
                        scheduleByDay[date] = emptyDay()
                    }
                }
            }

            let employee = employeeIn(row: rowValues.map(\.text))
            if let employee {
                recognizedEmployees.insert(employee)
            }

            for value in rowValues {
                guard let employee, let date = dateByColumn[value.column], let shift = parseWorkHours(value.text) else { continue }
                if scheduleByDay[date] == nil {
                    scheduleByDay[date] = emptyDay()
                }
                scheduleByDay[date]?[employee] = shift
            }
        }

        if scheduleByDay.isEmpty { throw ScheduleReaderError.noRecognizedDates }
        if recognizedEmployees.isEmpty { throw ScheduleReaderError.noRecognizedEmployees }
        return scheduleByDay.keys.sorted().map { (date: $0, people: scheduleByDay[$0] ?? emptyDay()) }
#else
        throw ScheduleReaderError.unreadableXLSX
#endif
    }

#if canImport(CoreXLSX)
    private func xlsxText(for cell: Cell, sharedStrings: SharedStrings?) -> String {
        if let sharedStrings, let value = cell.stringValue(sharedStrings) {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (cell.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
#endif

    private func validated(schedule: [(date: Date, people: [String: WorkShift?])]) throws -> [(date: Date, people: [String: WorkShift?])] {
        guard !schedule.isEmpty else { throw ScheduleReaderError.noRecognizedDates }
        let hasEmployee = schedule.contains { day in
            employees.contains { day.people.keys.contains($0.name) }
        }
        guard hasEmployee else { throw ScheduleReaderError.noRecognizedEmployees }
        return schedule
    }

    private func emptyDay() -> [String: WorkShift?] {
        Dictionary(uniqueKeysWithValues: employees.map { ($0.name, Optional<WorkShift>.none) })
    }

    private func columnIndex(from reference: String) -> Int {
        var result = 0
        for scalar in reference.uppercased().unicodeScalars where scalar.value >= 65 && scalar.value <= 90 {
            result = result * 26 + Int(scalar.value - 64)
        }
        return result
    }

    private func employeeIn(row: [String]) -> String? {
        for employee in employees where row.contains(where: { $0.localizedCaseInsensitiveContains(employee.name) }) {
            return employee.name
        }

        for cell in row {
            let value = cell.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard value.hasPrefix("P"), let number = Int(value.dropFirst()), employees.indices.contains(number - 1) else { continue }
            return employees[number - 1].name
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

    private func splitCSVLine(_ line: String) -> [String] {
        let delimiter: Character = line.contains(";") ? ";" : ","
        return line.split(separator: delimiter, omittingEmptySubsequences: false).map(String.init)
    }
}
