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

enum EmployeeSelectionMode: String, CaseIterable, Identifiable, Codable {
    case picker = "Lista"
    case stepper = "Przeklikiwanie"

    var id: String { rawValue }
}

enum ScheduleReaderError: LocalizedError {
    case unreadableSource
    case noEmployee

    var errorDescription: String? {
        switch self {
        case .unreadableSource:
            return "Nie mogę odczytać wybranego pliku."
        case .noEmployee:
            return "Dodaj lub wybierz pracownika przed generowaniem."
        }
    }
}
