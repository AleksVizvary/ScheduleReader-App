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
    private(set) var lastDiagnosticReport: ScheduleParserDiagnosticReport?

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
            let result = try parseScheduleXLSXWithDiagnostics(sourceURL)
            lastDiagnosticReport = result.diagnostic
            #if DEBUG
            printDiagnosticReport(result.diagnostic)
            #endif
            return try validated(schedule: result.schedule)
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

    func diagnoseXLSX(sourceURL: URL) throws -> (schedule: [(date: Date, people: [String: WorkShift?])], diagnostic: ScheduleParserDiagnosticReport) {
        try parseScheduleXLSXWithDiagnostics(sourceURL)
    }

    private func parseScheduleXLSXWithDiagnostics(_ sourceURL: URL) throws -> (schedule: [(date: Date, people: [String: WorkShift?])], diagnostic: ScheduleParserDiagnosticReport) {
#if canImport(CoreXLSX)
        guard let file = XLSXFile(filepath: sourceURL.path) else { throw ScheduleReaderError.unreadableXLSX }
        let sharedStrings = try? file.parseSharedStrings()
        let worksheetInfos = try worksheetInfos(in: file)
        guard !worksheetInfos.isEmpty else { throw ScheduleReaderError.noWorksheet }

        var analyzedSheets: [(path: String, name: String, rows: [Row], dates: [Int: [(row: Int, date: Date, diagnostic: ParsedCellDiagnostic)]], employees: [Int: (name: String, diagnostic: ParsedCellDiagnostic)], shifts: [(row: Int, column: Int, diagnostic: ParsedCellDiagnostic, shift: WorkShift)])] = []

        for info in worksheetInfos {
            let worksheet = try file.parseWorksheet(at: info.path)
            let rows = worksheet.data?.rows ?? []
            var dates: [Int: [(row: Int, date: Date, diagnostic: ParsedCellDiagnostic)]] = [:]
            var employeesByRow: [Int: (String, ParsedCellDiagnostic)] = [:]
            var shifts: [(Int, Int, ParsedCellDiagnostic, WorkShift)] = []

            for row in rows {
                var rowTexts: [(reference: String, text: String)] = []
                for cell in row.cells {
                    let reference = String(describing: cell.reference)
                    let text = xlsxText(for: cell, sharedStrings: sharedStrings)
                    rowTexts.append((reference, text))
                    let column = columnIndex(from: reference)
                    if let date = cell.dateValue ?? parseDate(text) {
                        dates[column, default: []].append((rowIndex(from: reference), date, ParsedCellDiagnostic(reference: reference, rawValue: text.isEmpty ? String(describing: cell.value ?? "") : text, interpretedAs: isoDay(date))))
                    }
                    if let shift = parseWorkHours(text) {
                        shifts.append((rowIndex(from: reference), column, ParsedCellDiagnostic(reference: reference, rawValue: text, interpretedAs: shift.displayText), shift))
                    }
                }
                if let match = employeeIn(cells: rowTexts) {
                    employeesByRow[rowIndex(from: match.reference)] = (match.name, ParsedCellDiagnostic(reference: match.reference, rawValue: match.rawValue, interpretedAs: match.name))
                }
            }
            analyzedSheets.append((info.path, info.name, rows, dates, employeesByRow, shifts))
        }

        let candidates = analyzedSheets.filter { !$0.dates.isEmpty && !$0.employees.isEmpty && !$0.shifts.isEmpty }
        guard let selected = (candidates.max { $0.shifts.count < $1.shifts.count } ?? analyzedSheets.first) else { throw ScheduleReaderError.noWorksheet }

        var report = ScheduleParserDiagnosticReport()
        report.sheetNames = worksheetInfos.map(\.name)
        report.selectedSheetName = selected.name
        report.rowCount = selected.rows.count
        report.recognizedDates = selected.dates.values.flatMap { $0.map(\.diagnostic) }.sorted { cellOrder($0.reference, $1.reference) }
        report.recognizedEmployees = selected.employees.values.map(\.diagnostic).sorted { cellOrder($0.reference, $1.reference) }
        report.recognizedShifts = selected.shifts.map(\.diagnostic).sorted { cellOrder($0.reference, $1.reference) }

        var scheduleByDay: [Date: [String: WorkShift?]] = [:]
        for dateInfo in selected.dates.values.flatMap({ $0 }) { scheduleByDay[dateInfo.date] = emptyDay() }

        for shiftInfo in selected.shifts {
            guard let dateInfo = selected.dates[shiftInfo.column]?.filter({ $0.row <= shiftInfo.row }).max(by: { $0.row < $1.row }), let employeeInfo = selected.employees[shiftInfo.row] else { continue }
            scheduleByDay[dateInfo.date, default: emptyDay()][employeeInfo.name] = shiftInfo.shift
            report.assignments.append(ScheduleAssignmentDiagnostic(dateReference: dateInfo.diagnostic.reference, employeeReference: employeeInfo.diagnostic.reference, shiftReference: shiftInfo.diagnostic.reference, date: dateInfo.date, employee: employeeInfo.name, shift: shiftInfo.shift))
        }
        report.assignments.sort { $0.date == $1.date ? $0.employee < $1.employee : $0.date < $1.date }

        if selected.dates.isEmpty { throw ScheduleReaderError.noRecognizedDates }
        if selected.employees.isEmpty { throw ScheduleReaderError.noRecognizedEmployees }
        return (scheduleByDay.keys.sorted().map { (date: $0, people: scheduleByDay[$0] ?? emptyDay()) }, report)
#else
        throw ScheduleReaderError.unreadableXLSX
#endif
    }

#if canImport(CoreXLSX)
    private func worksheetInfos(in file: XLSXFile) throws -> [(path: String, name: String)] {
        let paths = try file.parseWorksheetPaths()
        // CoreXLSX exposes names through workbook metadata on supported versions.
        if let workbook = try? file.parseWorkbooks().first,
           let named = try? file.parseWorksheetPathsAndNames(workbook: workbook), !named.isEmpty {
            return named.map { (path: $0.path, name: $0.name) }
        }
        return paths.enumerated().map { (offset, path) in (path: path, name: "Sheet\(offset + 1)") }
    }

    private func xlsxText(for cell: Cell, sharedStrings: SharedStrings?) -> String {
        if let sharedStrings, let value = cell.stringValue(sharedStrings) {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let inline = Mirror(reflecting: cell).children.first(where: { $0.label == "inlineString" })?.value as? String {
            return inline.trimmingCharacters(in: .whitespacesAndNewlines)
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
        employeeIn(cells: row.enumerated().map { (reference: "", text: $0.element) })?.name
    }

    private func employeeIn(cells: [(reference: String, text: String)]) -> (name: String, reference: String, rawValue: String)? {
        let normalizedCells = cells.map { (reference: $0.reference, rawValue: $0.text, normalized: normalizedName($0.text)) }

        for employee in employees {
            let expected = normalizedName(employee.name)
            let exact = normalizedCells.filter { $0.normalized == expected }
            if exact.count == 1 { return (employee.name, exact[0].reference, exact[0].rawValue) }
        }

        for employee in employees {
            let expected = normalizedName(employee.name)
            let contained = normalizedCells.filter { !$0.normalized.isEmpty && $0.normalized.localizedCaseInsensitiveContains(expected) }
            if contained.count == 1 { return (employee.name, contained[0].reference, contained[0].rawValue) }
        }

        for cell in cells {
            let value = normalizedName(cell.text).uppercased()
            guard value.hasPrefix("P"), let number = Int(value.dropFirst()), employees.indices.contains(number - 1) else { continue }
            return (employees[number - 1].name, cell.reference, cell.text)
        }

        return nil
    }

    private func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    private func parseWorkHours(_ raw: String) -> WorkShift? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        for bug in workHourBugs where !bug.text.isEmpty {
            value = value.replacingOccurrences(of: bug.text, with: "-")
        }
        value = value.replacingOccurrences(of: ",", with: "")
        value = value.replacingOccurrences(of: " ", with: "")
        value = value.replacingOccurrences(of: ":00", with: "")

        let parts = value.split(separator: "-", omittingEmptySubsequences: true)
        guard parts.count == 2,
              let start = Int(parts[0]),
              let end = Int(parts[1]),
              (0...23).contains(start),
              (1...24).contains(end),
              end > start else { return nil }
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


    private func rowIndex(from reference: String) -> Int {
        Int(reference.filter(\.isNumber)) ?? 0
    }

    private func cellOrder(_ left: String, _ right: String) -> Bool {
        let leftRow = rowIndex(from: left)
        let rightRow = rowIndex(from: right)
        if leftRow == rightRow { return columnIndex(from: left) < columnIndex(from: right) }
        return leftRow < rightRow
    }

    private func isoDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func printDiagnosticReport(_ report: ScheduleParserDiagnosticReport) {
        print("[Sheets] \(report.sheetNames.joined(separator: ", "))")
        print("[Sheet] \(report.selectedSheetName)")
        print("[Rows] \(report.rowCount)")
        report.recognizedDates.forEach { print("[Date] \($0.reference) raw=\($0.rawValue) parsed=\($0.interpretedAs)") }
        report.recognizedEmployees.forEach { print("[Employee] \($0.reference) raw=\"\($0.rawValue)\"") }
        report.recognizedShifts.forEach { print("[Shift] \($0.reference) raw=\"\($0.rawValue)\" parsed=\($0.interpretedAs)") }
        report.assignments.forEach { print("[Assignment] \(isoDay($0.date)) | \($0.employee) | \($0.shift.displayText) dateCell=\($0.dateReference) employeeCell=\($0.employeeReference) shiftCell=\($0.shiftReference)") }
    }

    func makeCalendarEvents(schedule: [(date: Date, people: [String: WorkShift?])], client: String) -> [CalendarEvent] {
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

    func makeICS(events: [CalendarEvent]) -> String {
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
