import SwiftUI
import UniformTypeIdentifiers

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
                        Image(systemName: "sidebar.right")
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
                Label("Załaduj grafik XLSX", systemImage: "folder")
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
                    Toggle("Przypnij", isOn: $viewModel.isSettingsPinned)
                        .toggleStyle(.switch)
                        .labelsHidden()
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
