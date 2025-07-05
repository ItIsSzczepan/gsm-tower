import Foundation
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var localLatestDate: Date?
    @Published var remoteDate: Date?
    @Published var isRefreshing = false
    @Published var progress: Double = 0.0
    @Published var progressText: String?
    @Published var error: String?
    
    private let repo = PointsRepository.shared
    
    func loadMetadata() {
        do {
            let dates = try repo.getLocalDates()
            localLatestDate = dates.max()
            
        } catch {
            self.error = "Nie udało się załadować danych lokalnych: \(error.localizedDescription)"
        }
        
        Task {
            do {
                remoteDate = try await repo.getRemoteDate()
            } catch {
                self.error = "Nie udało się pobrać daty z serwera: \(error.localizedDescription)"
            }
        }
    }
    
    func refresh() async {
        isRefreshing = true
        progress = 0.0
        progressText = ""
        error = nil
        
        do {
            try await repo.refresh { [weak self] value, text in
                DispatchQueue.main.async {
                    self?.progress = value
                    self?.progressText = text
                }
            }
            loadMetadata()
        } catch {
            self.error = "Błąd podczas odświeżania danych: \(error.localizedDescription)"
        }
        isRefreshing = false
        
    }
    
    func deleteAll() {
        do {
            try repo.deleteAllLocalData()
            localLatestDate = nil
        } catch {
            self.error = "Nie udało się usunąć danych: \(error.localizedDescription)"
        }
    }
}
