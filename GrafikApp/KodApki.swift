import SwiftUI
import Combine


// ======================================================
// Dane ekranu, funkcje i stany (viewModel)
// ======================================================

final class GrafikViewModel: ObservableObject {

    @Published var lista: [String] = []
    @Published var osoba: String = ""
    @Published var wybranaOsoba: String = ""
    // =----------
    func dodajOsobe(){
        lista.append(osoba)
        osoba = ""
    }

// ======================================================
// ======================================================


// main:
struct ContentView: View {
    @StateObject private var viewModel = GrafikViewModel()
    
    var body: some View {
        
        TextField("Dodaj osobe:", text: $viewModel.osoba)
        
        Button("Dodaj") {
            viewModel.dodajOsobe()
        }
        
        Picker("Wybierz opcje", selection:  $viewModel.wybranaOsoba){
            ForEach(viewModel.lista, id: \.self) {
                osoba in Text(osoba).tag(osoba)
            }
        }
        
        
    }
}
