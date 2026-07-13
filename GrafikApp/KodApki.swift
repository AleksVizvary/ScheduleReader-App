import SwiftUI
import UniformTypeIdentifiers

// MARK: - Models

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

struct ShiftRecord: Hashable {
    var dateLabel: String
    var startHour: Int
    var endHour: Int
    var description: String
}

enum EmployeeSelectionMode: String, CaseIterable, Identifiable, Codable {
    case picker = "Lista"
    case stepper = "Przeklikiwanie"

    var id: String { rawValue }
}

enum ScheduleReaderError: LocalizedError {
    case unsupportedXLSX
    case unreadableSource
    case noEmployee

    var errorDescription: String? {
        switch self {
        case .unsupportedXLSX:
            return "Wybrany XLSX jest gotowy do podpięcia biblioteki Excela, ale natywny Swift parser czyta teraz CSV. Wyeksportuj grafik do CSV albo podepnij moduł XLSX."
        case .unreadableSource:
            return "Nie mogę odczytać wybranego pliku."
        case .noEmployee:
            return "Dodaj lub wybierz pracownika przed generowaniem."
        }
    }
}

// MARK: - Backend facade with the Python parser rules ported to Swift

final class ScheduleReaderBackend: ObservableObject {
    @Published var employees: [Employee] = [
        Employee(name: "Aleksander Vizváry"),
        Employee(name: "Marcin Chełpa"),
        Employee(name: "Malwina Walus"),
        Employee(name: "Dorota Hazik"),
        Employee(name: "Dariusz Dutkiewicz"),
        Employee(name: "Małgorzata Janowska"),
        Employee(name: "Anna Majewska")
    ]

    @Published var workHourBugs: [WorkHourBug] = [
        WorkHourBug(text: ",-"),
        WorkHourBug(text: "-,")
    ]

    @Published var generatedFiles: [GeneratedScheduleFile] = []

    func generateSchedule(sourceURL: URL, employee: Employee, month: String, customName: String) throws -> GeneratedScheduleFile {
        guard sourceURL.pathExtension.lowercased() != "xlsx" else { throw ScheduleReaderError.unsupportedXLSX }
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let shifts = parseScheduleCSV(source, employee: employee)
        let csv = makeEmployeeCSV(shifts: shifts, employee: employee, sourceFileName: sourceURL.lastPathComponent)
        let fileURL = try save(csv: csv, employee: employee, month: month, customName: customName)

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

    private func parseScheduleCSV(_ source: String, employee: Employee) -> [ShiftRecord] {
        var shifts: [ShiftRecord] = []
        var presentDay = ""
        let rows = source
            .split(whereSeparator: \.isNewline)
            .map { splitCSVLine(String($0)) }

        for row in rows {
            if let date = row.compactMap(parseDateLabel).first {
                presentDay = date
            }

            let employeeInRow = row.contains { $0.localizedCaseInsensitiveContains(employee.name) }
            guard employeeInRow else { continue }

            for cell in row {
                if let hours = parseWorkHours(cell) {
                    shifts.append(
                        ShiftRecord(
                            dateLabel: presentDay.isEmpty ? "bez daty" : presentDay,
                            startHour: hours.start,
                            endHour: hours.end,
                            description: "Praca"
                        )
                    )
                }
            }
        }

        return shifts
    }

    private func parseWorkHours(_ raw: String) -> (start: Int, end: Int)? {
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
        return (start, end)
    }

    private func parseDateLabel(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let formats = ["dd.MM.yyyy", "d.MM.yyyy", "yyyy-MM-dd", "dd/MM/yyyy", "d/MM/yyyy"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter.string(from: date)
            }
        }

        if value.range(of: #"^\d{1,2}\.?\s+[A-Za-zĄĆĘŁŃÓŚŹŻąćęłńóśźż]+\s+\d{4}$"#, options: .regularExpression) != nil {
            return value
        }
        return nil
    }

    private func makeEmployeeCSV(shifts: [ShiftRecord], employee: Employee, sourceFileName: String) -> String {
        var rows = ["Pracownik,Data,Start,Koniec,Opis,Źródło"]
        if shifts.isEmpty {
            rows.append(csvRow([employee.name, "", "", "", "Brak rozpoznanych zmian w CSV", sourceFileName]))
        } else {
            rows.append(contentsOf: shifts.map { shift in
                csvRow([
                    employee.name,
                    shift.dateLabel,
                    "\(shift.startHour):00",
                    "\(shift.endHour):00",
                    shift.description,
                    sourceFileName
                ])
            })
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private func save(csv: String, employee: Employee, month: String, customName: String) throws -> URL {
        let sanitizedEmployee = employee.name.replacingOccurrences(of: " ", with: "_")
        let fallbackName = "\(month)_\(sanitizedEmployee).csv"
        var finalName = customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackName : customName
        if !finalName.lowercased().hasSuffix(".csv") {
            finalName += ".csv"
        }

        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScheduleReader", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(finalName)
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func splitCSVLine(_ line: String) -> [String] {
        let delimiter: Character = line.contains(";") ? ";" : ","
        return line.split(separator: delimiter, omittingEmptySubsequences: false).map(String.init)
    }

    private func csvRow(_ values: [String]) -> String {
        values
            .map { value in
                let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
            .joined(separator: ",")
    }
}

// MARK: - View model

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
    @Published var statusMessage = "Gotowe do generowania CSV."
    @Published var latestGeneratedFile: GeneratedScheduleFile?

    let months = [
        "styczeń", "luty", "marzec", "kwiecień", "maj", "czerwiec",
        "lipiec", "sierpień", "wrzesień", "październik", "listopad", "grudzień"
    ]

    var selectedEmployee: Employee? {
        guard backend.employees.indices.contains(selectedEmployeeIndex) else { return nil }
        return backend.employees[selectedEmployeeIndex]
    }

    var suggestedFileName: String {
        guard let selectedEmployee else { return "\(selectedMonth)_pracownik.csv" }
        return "\(selectedMonth)_\(selectedEmployee.name.replacingOccurrences(of: " ", with: "_")).csv"
    }

    func selectFile(_ url: URL) {
        selectedInputFileURL = url
        selectedInputFileName = url.lastPathComponent
        statusMessage = "Załadowano grafik: \(url.lastPathComponent)"
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
            statusMessage = "Wygenerowano CSV: \(file.fileName)"
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

// MARK: - UI

struct ContentView: View {
    @StateObject private var viewModel = GrafikViewModel()
    @State private var isFileImporterPresented = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .trailing) {
                ScrollView {
                    mainScreen
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(appBackground)

                if viewModel.isSettingsVisible {
                    settingsSidebar
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            viewModel.isSettingsVisible.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                }
            }
        }
        .onAppear { viewModel.syncManualFileNameIfNeeded(force: true) }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.commaSeparatedText, .plainText, .data],
            allowsMultipleSelection: false
        ) { result in
            if let url = try? result.get().first {
                viewModel.selectFile(url)
            }
        }
    }

    private var mainScreen: some View {
        VStack(spacing: 18) {
            headerCard
            filePickerCard
            employeePickerCard
            generateCard
        }
        .frame(maxWidth: 720)
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            Image(viewModel.logoName)
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("GENERATOR PLIKÓW")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .cardStyle()
    }

    private var filePickerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Plik grafiku", systemImage: "doc.badge.plus")
                .font(.headline)
            Text(viewModel.selectedInputFileName)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button {
                isFileImporterPresented = true
            } label: {
                Label("Załaduj grafik CSV", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .cardStyle()
    }

    private var employeePickerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Pracownik", systemImage: "person.crop.circle")
                .font(.headline)

            if viewModel.selectionMode == .picker {
                Picker("Pracownik", selection: $viewModel.selectedEmployeeIndex) {
                    ForEach(Array(viewModel.backend.employees.enumerated()), id: \.offset) { index, employee in
                        Text(employee.name).tag(index)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: viewModel.selectedEmployeeIndex) { _, _ in viewModel.syncManualFileNameIfNeeded() }
            } else {
                HStack(spacing: 16) {
                    Button { viewModel.selectPreviousEmployee() } label: { Image(systemName: "chevron.left") }
                    Text(viewModel.selectedEmployee?.name ?? "Brak pracowników")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                    Button { viewModel.selectNextEmployee() } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var generateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nazwa wyniku")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(viewModel.suggestedFileName, text: $viewModel.manualFileName)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Button("Generuj") { viewModel.generate() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                if let file = viewModel.latestGeneratedFile {
                    ShareLink(item: file.fileURL) {
                        Label("Pobierz / otwórz", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }

            Text(viewModel.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .cardStyle()
    }

    private var settingsSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Ustawienia")
                        .font(.title2.bold())
                    Spacer()
                    Button { viewModel.isSettingsVisible = false } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                }

                monthSection
                employeeSettingsSection
                workHourBugsSection
                themeSection
                generatedFilesSection
            }
            .padding(18)
        }
        .frame(width: 360)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding()
        .shadow(radius: 20)
    }

    private var monthSection: some View {
        GroupBox("Miesiąc i nazwa") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Miesiąc", selection: $viewModel.selectedMonth) {
                    ForEach(viewModel.months, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: viewModel.selectedMonth) { _, _ in viewModel.syncManualFileNameIfNeeded(force: true) }
                TextField("Nazwa pliku", text: $viewModel.manualFileName)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var employeeSettingsSection: some View {
        GroupBox("Pracownicy") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Sposób wyboru", selection: $viewModel.selectionMode) {
                    ForEach(EmployeeSelectionMode.allCases) { Text($0.rawValue).tag($0) }
                }
                ForEach($viewModel.backend.employees) { $employee in
                    TextField("Imię", text: $employee.name)
                        .textFieldStyle(.roundedBorder)
                }
                Button { viewModel.addEmployee() } label: { Label("Dodaj pracownika", systemImage: "plus") }
            }
        }
    }

    private var workHourBugsSection: some View {
        GroupBox("Lista bugów komórki godzin pracy") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Wpisz tylko zepsuty fragment komórki, np. 16-,22 albo samo ,-. Parser zamieni go na standardowy zapis 16-22.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(Array(viewModel.backend.workHourBugs.indices), id: \.self) { index in
                    HStack {
                        TextField("np. 16-,22 albo ,-", text: $viewModel.backend.workHourBugs[index].text)
                            .textFieldStyle(.roundedBorder)
                        Button(role: .destructive) {
                            viewModel.backend.workHourBugs.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                    }
                }

                Button { viewModel.addWorkHourBug() } label: { Label("Dodaj bug godzin", systemImage: "plus") }
            }
        }
    }

    private var themeSection: some View {
        GroupBox("Szata graficzna") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Nazwa motywu", text: $viewModel.themeName)
                    .textFieldStyle(.roundedBorder)
                TextField("Nazwa assetu logo", text: $viewModel.logoName)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var generatedFilesSection: some View {
        GroupBox("Zapamiętane pliki") {
            VStack(alignment: .leading, spacing: 10) {
                if viewModel.backend.generatedFiles.isEmpty {
                    Text("Brak wygenerowanych plików w tej sesji.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.backend.generatedFiles) { file in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading) {
                                Text(file.fileName).font(.headline)
                                Text("\(file.employeeName) · \(file.month) · źródło: \(file.sourceFileName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            ShareLink(item: file.fileURL) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }
        }
    }

    private var appBackground: some View {
        LinearGradient(
            colors: [Color.blue.opacity(0.18), Color.purple.opacity(0.12), Color(.systemBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private extension View {
    func cardStyle() -> some View {
        background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }
}

#Preview {
    ContentView()
}
