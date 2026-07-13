import SwiftUI
import UniformTypeIdentifiers

// MARK: - Models ported from the Python ScheduleReader flow

struct Employee: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
}

struct ParserRule: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var pattern: String
    var isEnabled: Bool
    var note: String
}

struct GeneratedScheduleFile: Identifiable, Hashable, Codable {
    var id = UUID()
    var fileName: String
    var employeeName: String
    var month: String
    var sourceFileName: String
    var createdAt: Date
}

enum EmployeeSelectionMode: String, CaseIterable, Identifiable, Codable {
    case picker = "Lista"
    case stepper = "Przeklikiwanie"

    var id: String { rawValue }
}

// MARK: - Backend facade

final class ScheduleReaderBackend: ObservableObject {
    @Published var employees: [Employee] = [
        Employee(name: "p1"),
        Employee(name: "p2"),
        Employee(name: "p3")
    ]

    @Published var parserRules: [ParserRule] = [
        ParserRule(
            name: "Godziny pracy",
            pattern: #"^\d{1,2}-\d{1,2}|^\d{1,2},-\d{1,2}"#,
            isEnabled: true,
            note: "Odpowiednik Cell.is_time() z Pythona. Obsługuje formaty 8-16 oraz 8,-16."
        ),
        ParserRule(
            name: "Urlop",
            pattern: "u",
            isEnabled: true,
            note: "Odpowiednik Cell.is_urlop(); pojedyncze 'u' oznacza urlop."
        ),
        ParserRule(
            name: "Daty w komórkach",
            pattern: "Date / DateTime",
            isEnabled: true,
            note: "Odpowiednik Cell.is_date(); data startuje nowy dzień grafiku."
        ),
        ParserRule(
            name: "Przypisanie pracownika",
            pattern: "Nazwa z listy w wierszu",
            isEnabled: true,
            note: "Odpowiednik what_employee(); parser szuka pracownika w wartościach aktualnego wiersza."
        )
    ]

    @Published var generatedFiles: [GeneratedScheduleFile] = []

    func generateSchedule(sourceFileName: String, employee: Employee, month: String, customName: String) -> GeneratedScheduleFile {
        let sanitizedEmployee = employee.name.replacingOccurrences(of: " ", with: "_")
        let fallbackName = "\(month)_\(sanitizedEmployee).csv"
        let finalName = customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackName : customName
        let generated = GeneratedScheduleFile(
            fileName: finalName,
            employeeName: employee.name,
            month: month,
            sourceFileName: sourceFileName,
            createdAt: Date()
        )
        generatedFiles.insert(generated, at: 0)
        return generated
    }
}

// MARK: - View model

final class GrafikViewModel: ObservableObject {
    @Published var backend = ScheduleReaderBackend()
    @Published var selectedInputFileName = "Nie wybrano pliku"
    @Published var selectedEmployeeIndex = 0
    @Published var selectedMonth = GrafikViewModel.nextMonthName()
    @Published var manualFileName = ""
    @Published var selectionMode: EmployeeSelectionMode = .picker
    @Published var isSettingsPinned = false
    @Published var isSettingsVisible = false
    @Published var themeName = "Domyślny"
    @Published var logoName = "GG"
    @Published var statusMessage = "Wybierz grafik, pracownika i kliknij Generuj."

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

    func addParserRule() {
        backend.parserRules.append(ParserRule(name: "Nowa poprawka", pattern: "", isEnabled: true, note: "Opisz błąd parsera lub wyjątek grafiku."))
    }

    func removeParserRules(at offsets: IndexSet) {
        backend.parserRules.remove(atOffsets: offsets)
    }

    func generate() {
        guard let selectedEmployee else {
            statusMessage = "Dodaj pracownika przed generowaniem."
            return
        }
        guard selectedInputFileName != "Nie wybrano pliku" else {
            statusMessage = "Najpierw wybierz plik grafiku."
            return
        }
        let file = backend.generateSchedule(
            sourceFileName: selectedInputFileName,
            employee: selectedEmployee,
            month: selectedMonth,
            customName: manualFileName
        )
        statusMessage = "Gotowe: \(file.fileName)"
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
                mainScreen
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(appBackground)

                if viewModel.isSettingsVisible || viewModel.isSettingsPinned {
                    settingsSidebar
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .navigationTitle("ScheduleReader")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            viewModel.isSettingsVisible.toggle()
                        }
                    } label: {
                        Label("Ustawienia", systemImage: "sidebar.right")
                    }
                }
            }
        }
        .onAppear { viewModel.syncManualFileNameIfNeeded(force: true) }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.spreadsheet, .commaSeparatedText, .data],
            allowsMultipleSelection: false
        ) { result in
            if let url = try? result.get().first {
                viewModel.selectedInputFileName = url.lastPathComponent
                viewModel.statusMessage = "Wybrano plik: \(url.lastPathComponent)"
            }
        }
    }

    private var mainScreen: some View {
        VStack(spacing: 24) {
            headerCard
            filePickerCard
            employeePickerCard
            generateCard
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 720)
    }

    private var headerCard: some View {
        VStack(spacing: 12) {
            Image(viewModel.logoName)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(radius: 12)

            Text("Generator grafików")
                .font(.largeTitle.bold())

            Text("Najważniejsze akcje są na ekranie głównym, a pracownicy, miesiąc, reguły parsera, motyw i historia plików siedzą w bocznym panelu.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
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
                Label("Wybierz plik XLSX / CSV", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
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
        .padding(20)
        .cardStyle()
    }

    private var generateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Nazwa wyniku")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(viewModel.suggestedFileName, text: $viewModel.manualFileName)
                        .textFieldStyle(.roundedBorder)
                }
                Button("Generuj") { viewModel.generate() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            Text(viewModel.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .cardStyle()
    }

    private var settingsSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Ustawienia")
                        .font(.title2.bold())
                    Spacer()
                    Toggle("Przypnij", isOn: $viewModel.isSettingsPinned)
                        .toggleStyle(.switch)
                        .labelsHidden()
                    Button { viewModel.isSettingsVisible = false } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                }

                monthSection
                employeeSettingsSection
                parserRulesSection
                themeSection
                generatedFilesSection
            }
            .padding(20)
        }
        .frame(width: 360)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding()
        .shadow(radius: 20)
    }

    private var monthSection: some View {
        GroupBox("Miesiąc i nazwa") {
            VStack(alignment: .leading) {
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

    private var parserRulesSection: some View {
        GroupBox("Lista bugów / reguł parsera") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach($viewModel.backend.parserRules) { $rule in
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $rule.isEnabled) {
                            TextField("Nazwa", text: $rule.name)
                        }
                        TextField("Wzorzec", text: $rule.pattern)
                            .textFieldStyle(.roundedBorder)
                        TextField("Notatka", text: $rule.note, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                    }
                    Divider()
                }
                Button { viewModel.addParserRule() } label: { Label("Dodaj regułę", systemImage: "ladybug") }
            }
        }
    }

    private var themeSection: some View {
        GroupBox("Szata graficzna") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Nazwa motywu z Framera", text: $viewModel.themeName)
                    .textFieldStyle(.roundedBorder)
                TextField("Nazwa assetu logo", text: $viewModel.logoName)
                    .textFieldStyle(.roundedBorder)
                Button { viewModel.statusMessage = "Motyw '\(viewModel.themeName)' przygotowany do podpięcia importera Framera." } label: {
                    Label("Wgraj / zastosuj motyw", systemImage: "paintpalette")
                }
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
                        VStack(alignment: .leading) {
                            Text(file.fileName).font(.headline)
                            Text("\(file.employeeName) · \(file.month) · źródło: \(file.sourceFileName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
