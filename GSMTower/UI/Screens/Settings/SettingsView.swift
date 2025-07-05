import SwiftUI

struct SettingsView: View {
    @ObservedObject var mapVM: MapViewModel
    @StateObject private var viewModel = SettingsViewModel()
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Dane lokalne")) {
                    if let date = viewModel.localLatestDate {
                        Text("Ostatnia lokalna data: \(format(date))")
                    } else {
                        Text("Brak lokalnych danych")
                    }
                    
                    if let remote = viewModel.remoteDate {
                        Text("Data z UKE: \(format(remote))")
                    } else {
                        Text("Brak informacji")
                    }
                    
                    Button("Odśwież dane") {
                        Task{
                            await viewModel.refresh()
                            await mapVM.fetchPointsAroundVisibleRegion()
                        }
                    }
                    if viewModel.isRefreshing {
                        if let text = viewModel.progressText {
                            Text(text)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        ProgressView(value: viewModel.progress)
                            .progressViewStyle(.linear)
                    }
                }
                
                Section(header: Text("Dane z serwera")) {
                    Button("Usuń wszystkie dane") {
                        viewModel.deleteAll()
                    }.foregroundColor(.red)
                    
                }
                
                if let error = viewModel.error {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
                
                Section(header: Text("Licencja danych")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Dane pochodzą z publicznego rejestru UKE, dostępnego na portalu dane.gov.pl.")
                            .font(.footnote)
                        Link("Zobacz źródło i licencję", destination: URL(string: "https://dane.gov.pl/pl/dataset/1075,wykazy-pozwolen-radiowych-dla-stacji-bazowych-telefonii-komorkowej-gsm-umts-lte-oraz-stacji-wykorzystujacych-technologie-cdma")!)
                            .font(.footnote)
                    }
                    .padding(.vertical, 4)
                }
                
            }
            .navigationTitle("Ustawienia")
            .onAppear {
                viewModel.loadMetadata()
            }

        }
    }
    
    private func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
