import Foundation
import SwiftUI

final class GrafikViewModel: ObservableObject {
    @Published var backend = ScheduleReaderBackend()
    @Published var selectedInputFileName = "Nie wybrano pliku"
    @Published var selectedInputFileURL: URL?
    @Published var selectedEmployeeIndex = 0
    @Published var selectedMonth = GrafikViewModel.nextMonthName()
    @Published var manualFileName = ""
    @Published var selectionMode: EmployeeSelectionMode = .picker
    @Published var isSettingsVisible = false
    @Published var themeName = "Domyślny"
    @Published var logoName = "GG"
    @Published var statusMessage = "Gotowe do generowania ICS z grafiku XLSX."
    @Published var latestGeneratedFile: GeneratedScheduleFile?
    @Published var isSettingsPinned = false

    let months = [
        "styczeń", "luty", "marzec", "kwiecień", "maj", "czerwiec",
        "lipiec", "sierpień", "wrzesień", "październik", "listopad", "grudzień"
    ]

    var selectedEmployee: Employee? {
        guard backend.employees.indices.contains(selectedEmployeeIndex) else { return nil }
        return backend.employees[selectedEmployeeIndex]
    }

    var suggestedFileName: String {
        guard let selectedEmployee else { return "grafik_\(selectedMonth)_pracownik.ics" }
        return "grafik_\(selectedMonth)_\(selectedEmployee.name.replacingOccurrences(of: " ", with: "_")).ics"
    }

    func selectFile(_ url: URL) {
        selectedInputFileURL = url
        selectedInputFileName = url.lastPathComponent
        statusMessage = "Załadowano grafik XLSX: \(url.lastPathComponent)"
    }

    func selectPreviousEmployee() {
        guard !backend.employees.isEmpty else { return }
        selectedEmployeeIndex = (selectedEmployeeIndex - 1 + backend.employees.count) % backend.employees.count
        syncManualFileNameIfNeeded()
    }

    func selectNextEmployee() {
        guard !backend.employees.isEmpty else { return }
        selectedEmployeeIndex = (selectedEmployeeIndex + 1) % backend.employees.count
        syncManualFileNameIfNeeded()
    }

    func addEmployee() {
        backend.employees.append(Employee(name: "Nowy pracownik"))
        selectedEmployeeIndex = backend.employees.count - 1
        syncManualFileNameIfNeeded(force: true)
    }

    func removeEmployees(at offsets: IndexSet) {
        backend.employees.remove(atOffsets: offsets)
        selectedEmployeeIndex = min(selectedEmployeeIndex, max(backend.employees.count - 1, 0))
        syncManualFileNameIfNeeded(force: true)
    }

    func addWorkHourBug() {
        backend.workHourBugs.append(WorkHourBug(text: ""))
    }

    func removeWorkHourBugs(at offsets: IndexSet) {
        backend.workHourBugs.remove(atOffsets: offsets)
    }

    func generate() {
        guard let selectedEmployee else {
            statusMessage = ScheduleReaderError.noEmployee.localizedDescription
            return
        }
        guard let selectedInputFileURL else {
            statusMessage = "Najpierw załaduj plik grafiku."
            return
        }

        do {
            let file = try backend.generateSchedule(
                sourceURL: selectedInputFileURL,
                employee: selectedEmployee,
                month: selectedMonth,
                customName: manualFileName
            )
            latestGeneratedFile = file
            statusMessage = "Wygenerowano ICS: \(file.fileName)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func syncManualFileNameIfNeeded(force: Bool = false) {
        if force || manualFileName.isEmpty || months.contains(where: { manualFileName.hasPrefix($0) }) {
            manualFileName = suggestedFileName
        }
    }

    static func nextMonthName(now: Date = Date()) -> String {
        let monthSymbols = [
            "styczeń", "luty", "marzec", "kwiecień", "maj", "czerwiec",
            "lipiec", "sierpień", "wrzesień", "październik", "listopad", "grudzień"
        ]
        let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: now) ?? now
        let component = Calendar.current.component(.month, from: nextMonth)
        return monthSymbols[max(0, min(component - 1, monthSymbols.count - 1))]
    }
}
