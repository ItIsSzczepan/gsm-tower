import Foundation
import SwiftUI
import Combine

@MainActor
final class FilterViewModel: ObservableObject {
    // Published properties for the view
    @Published var availableTechnologies: [String] = []
    @Published var availableOperators: [String] = []
    @Published var isLoading: Bool = false
    
    // Selected values
    @Published var selectedTechnologies: Set<String>
    @Published var selectedOperators: Set<String>
    
    // Repository for data access
    private let repository = PointsRepository.shared
    
    init(selectedTechnologies: Set<String>, selectedOperators: Set<String>, searchRadius: Double = 5.0) {
        self.selectedTechnologies = selectedTechnologies
        self.selectedOperators = selectedOperators
        
        // Load available filter options when initialized
        Task { await loadFilterOptions() }
    }
    
    func loadFilterOptions() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Fetch available technologies and operators from the database
            let technologies = try repository.getTechnologies()
            let operators = try repository.getOperatorNames()
            
            await MainActor.run {
                self.availableTechnologies = technologies
                self.availableOperators = operators
            }
        } catch {
            
        }
    }
    
    // Toggle selection for technologies
    func toggleTechnology(_ tech: String) {
        if selectedTechnologies.contains(tech) {
            selectedTechnologies.remove(tech)
        } else {
            selectedTechnologies.insert(tech)
        }
    }
    
    // Toggle selection for operators
    func toggleOperator(_ op: String) {
        if selectedOperators.contains(op) {
            selectedOperators.remove(op)
        } else {
            selectedOperators.insert(op)
        }
    }
}
