import SwiftUI
import MapKit

struct FilterView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: FilterViewModel
    @Binding var selectedTechnologies: Set<String>
    @Binding var selectedOperators: Set<String>
    var onSave: () -> Void
    
    init(
        selectedTechnologies: Binding<Set<String>>,
        selectedOperators: Binding<Set<String>>,
        onSave: @escaping () -> Void
    ) {
        self._selectedTechnologies = selectedTechnologies
        self._selectedOperators = selectedOperators
        self.onSave = onSave
        self._vm = StateObject(
            wrappedValue: FilterViewModel(
                selectedTechnologies: selectedTechnologies.wrappedValue,
                selectedOperators: selectedOperators.wrappedValue,
            )
        )
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Operators section
                Section {
                    if vm.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        ForEach(vm.availableOperators, id: \.self) { op in
                            MultipleSelectionRow(
                                title: op,
                                isSelected: vm.selectedOperators.contains(op)
                            ) {
                                vm.toggleOperator(op)
                            }
                            .overlay(
                                Circle()
                                    .fill(operatorColor(op))
                                    .frame(width: 16, height: 16)
                                    .padding(.trailing, 8),
                                alignment: .trailing
                            )
                        }
                    }
                } header: {
                    Text("Operatorzy")
                }
                
                // Technologies section
                Section {
                    if vm.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        ForEach(vm.availableTechnologies, id: \.self) { tech in
                            MultipleSelectionRow(
                                title: tech,
                                isSelected: vm.selectedTechnologies.contains(tech)
                            ) {
                                vm.toggleTechnology(tech)
                            }
                        }
                    }
                } header: {
                    Text("Technologie")
                }
                

            }
            .navigationTitle("Filtry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") {
                        saveAndDismiss()
                    }
                }
            }
        }
    }
    
    private func saveAndDismiss() {
        // Update bindings with the view model values
        selectedTechnologies = vm.selectedTechnologies
        selectedOperators = vm.selectedOperators
        
        // Trigger the callback to apply filters
        onSave()
        dismiss()
    }
    
    // Helper for operator color
    private func operatorColor(_ op: String) -> Color {
        let op = op.uppercased()
        switch op {
        case let s where s.contains("P4"): return AppColors.p4
        case let s where s.contains("PKP"): return AppColors.pkp
        case let s where s.contains("POLKOMTEL"): return AppColors.polkomtel
        case let s where s.contains("T-MOBILE"): return AppColors.tmobile
        case let s where s.contains("PGE"): return AppColors.pge
        case let s where s.contains("ORANGE"): return AppColors.orange
        case let s where s.contains("NORDISK"): return AppColors.nordisk
        default: return AppColors.defaultOperator
        }
    }
}
