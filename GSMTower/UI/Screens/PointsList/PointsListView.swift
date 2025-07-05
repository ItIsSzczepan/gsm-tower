import SwiftUI

struct PointsListView: View {
    @State private var searchText: String = ""
    @State private var selectedTab: Tab = .visible
    @Binding var isAllPointsLoaded: Bool
    @Binding var allPoints: [Point]
    @Binding var visiblePoints: [Point]
    
    enum Tab: String, CaseIterable, Identifiable {
        case visible = "Widoczne na mapie"
        case all = "Wszystkie punkty"
        var id: String { rawValue }
    }
    
    init(visiblePoints: Binding<[Point]>, allPoints: Binding<[Point]>, isAllPointsLoaded: Binding<Bool>) {
        self._allPoints = allPoints
        self._visiblePoints = visiblePoints
        self._isAllPointsLoaded = isAllPointsLoaded
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Sekcja", selection: $selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.all)
                
                List {
                    if selectedTab == .visible {
                        if !filteredVisiblePoints.isEmpty {
                            ForEach(filteredVisiblePoints, id: \.details.stationId) { p in
                                pointRow(p)
                            }
                        } else {
                            Text("Brak punktów do wyświetlenia")
                        }
                    } else {
                        if !isAllPointsLoaded {
                            HStack {
                                Spacer()
                                ProgressView("Ładowanie wszystkich punktów...")
                                    .padding()
                                Spacer()
                            }
                        }
                        if !filteredAllPoints.isEmpty {
                            ForEach(filteredAllPoints, id: \.details.stationId) { p in
                                pointRow(p)
                            }
                        } else if isAllPointsLoaded {
                            Text("Brak punktów do wyświetlenia")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("Punkty")
                .searchable(text: $searchText, prompt: "Szukaj po lokalizacji, ID lub operatorze")
            }
        }
    }
    
    // MARK: - Helpers
    private func pointRow(_ p: Point) -> some View {
        NavigationLink(destination: PointDetailView(point: p)) {
            HStack(alignment: .top, spacing: 12) {
                if p.permissions.first?.operatorName != nil {
                    Circle()
                        .fill(p.color())
                        .frame(width: 16, height: 16)
                } else {
                    Circle()
                        .fill(AppColors.defaultOperator)
                        .frame(width: 16, height: 16)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.details.city)
                        .font(.headline)
                    if !p.details.location.isEmpty {
                        Text(p.details.location)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Text("ID: \(p.details.stationId)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let operatorName = p.permissions.first?.operatorName {
                        Text(operatorName)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    let technologies = Set(p.permissions.map { $0.technology }).sorted()
                    if !technologies.isEmpty {
                        Text(technologies.joined(separator: ", "))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Filtering
    private var filteredVisiblePoints: [Point] {
        filterPoints(visiblePoints)
    }
    private var filteredAllPoints: [Point] {
        return filterPoints(allPoints)
    }
    private func filterPoints(_ points: [Point]) -> [Point] {
        guard !searchText.isEmpty else { return points }
        let lower = searchText.lowercased()
        return points.filter { p in
            p.details.city.lowercased().contains(lower) ||
            p.details.location.lowercased().contains(lower) ||
            p.details.stationId.lowercased().contains(lower) ||
            (p.permissions.first?.operatorName.lowercased().contains(lower) ?? false)
        }
    }
}
