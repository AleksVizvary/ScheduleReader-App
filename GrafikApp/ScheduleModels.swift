import Foundation

struct Employee: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
}

struct WorkHourBug: Identifiable, Hashable, Codable {
    var id = UUID()
    var text: String
}

struct GeneratedScheduleFile: Identifiable, Hashable, Codable {
    var id = UUID()
    var fileName: String
    var employeeName: String
    var month: String
    var sourceFileName: String
    var createdAt: Date
    var fileURL: URL
}

struct WorkShift: Hashable {
    var startHour: Int
    var endHour: Int
}

struct CalendarEvent: Hashable {
    var date: Date
    var shift: WorkShift
    var description: String
}

struct ParsedCellDiagnostic: Hashable {
    let reference: String
    let rawValue: String
    let interpretedAs: String
}

struct ScheduleAssignmentDiagnostic: Hashable {
    let dateReference: String
    let employeeReference: String
    let shiftReference: String
    let date: Date
    let employee: String
    let shift: WorkShift
}

struct ScheduleParserDiagnosticReport: Hashable {
    var sheetNames: [String] = []
    var selectedSheetName: String = ""
    var rowCount: Int = 0
    var recognizedDates: [ParsedCellDiagnostic] = []
    var recognizedEmployees: [ParsedCellDiagnostic] = []
    var recognizedShifts: [ParsedCellDiagnostic] = []
    var assignments: [ScheduleAssignmentDiagnostic] = []
}

enum EmployeeSelectionMode: String, CaseIterable, Identifiable, Codable {
    case picker = "Lista"
    case stepper = "Przeklikiwanie"

    var id: String { rawValue }
}

enum ScheduleReaderError: LocalizedError {
    case unsupportedExtension
    case unreadableSource
    case unreadableXLSX
    case noWorksheet
    case noRecognizedDates
    case noRecognizedEmployees
    case noShiftsForEmployee
    case noEmployee
    case icsWriteFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedExtension:
            return "Nieobsługiwane rozszerzenie pliku. Wybierz plik XLSX albo CSV."
        case .unreadableSource:
            return "Nie mogę odczytać wybranego pliku."
        case .unreadableXLSX:
            return "Plik XLSX jest uszkodzony albo nieczytelny."
        case .noWorksheet:
            return "Plik XLSX nie zawiera arkusza z grafikiem."
        case .noRecognizedDates:
            return "Nie rozpoznano żadnych dat w grafiku."
        case .noRecognizedEmployees:
            return "Nie rozpoznano żadnych pracowników w grafiku."
        case .noShiftsForEmployee:
            return "Nie znaleziono zmian wybranego pracownika."
        case .noEmployee:
            return "Dodaj lub wybierz pracownika przed generowaniem."
        case .icsWriteFailed:
            return "Nie udało się zapisać pliku ICS."
        }
    }
}

extension WorkShift {
    var displayText: String {
        String(format: "%02d:00-%02d:00", startHour, endHour)
    }
}
