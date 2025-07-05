import SwiftUI

/// A reusable row component for multiple selection lists
struct MultipleSelectionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    List {
        MultipleSelectionRow(title: "Option 1", isSelected: true) {}
        MultipleSelectionRow(title: "Option 2", isSelected: false) {}
    }
}