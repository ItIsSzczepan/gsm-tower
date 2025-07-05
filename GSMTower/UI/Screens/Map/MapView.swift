import SwiftUI
import MapKit
import CoreLocation
import ClusterMap        // https://github.com/vospennikov/ClusterMap
import ClusterMapSwiftUI

// MARK: - Cluster wrapper
/// Lightweight wrapper so that `ClusterMap` clusters can be shown with the iOS-17 `Annotation` API.
struct PointClusterAnnotation: CoordinateIdentifiable, Identifiable, Hashable {
    let id: UUID
    var coordinate: CLLocationCoordinate2D
    let count: Int
}

struct MapView: View {
    // MARK: – State & View-Model
    @StateObject private var vm = MapViewModel()
    
    // Runtime UI state
    @State private var isShowingFilter = false
    @State private var isShowingSettings = false
    @State private var isShowingList = false
    
    // MARK: – Map / Cluster state
    /// iOS-17 camera binding used by the new `Map` initialiser.
    @State private var cameraPosition: MapCameraPosition = .region(AppConstants.initialRegion)
    @State private var mapSize: CGSize = .zero
    
    @State private var clusterManager = ClusterManager<Point>()
    @State private var visiblePoints: [Point] = []
    @State private var visibleClusters: [PointClusterAnnotation] = []
    @State private var visibleClusterPoints: [Point] = []
    
    @State private var didSetInitialUserLocation = false
    @State private var didRequestLocationPermission = false
    
    private let regionDebounce: TimeInterval = 0.5
    
    // MARK: – Body
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            mapLayer
            fabStack
        }
        // Search bar inset at the top
        .safeAreaInset(edge: .top) { searchBar.padding(.horizontal).padding(.vertical, 4) }
        // List button overlay
        .overlay(alignment: .bottomLeading) {
            listButton.padding(.leading).padding(.bottom, 32)
        }
        // Remove loading overlay for points loading, only show for data refresh
        .overlay(alignment: .top) {
            if vm.isDataOutdated || vm.loadingMessage != nil || vm.loadingProgress != nil {
                loadingOverlay
            }
        }
        // Keep clusters & view-model in sync with camera movements
        .onMapCameraChange(frequency: .onEnd) { context in
            // Update VM’s region so filters & repository know where we are
            vm.refreshIfNeeded(for: context.region)
            // vm.coordinateRegion = context.region // This is handled by refreshIfNeeded
            Task.detached { await reloadClusters(for: context.region) }
        }
        // Re-cluster whenever underlying data changes
        .onChange(of: vm.points) { _, newPoints in // Corrected to use newPoints
            Task.detached { await refreshAnnotations(with: newPoints) }
        }
        // Keep VM → camera binding in sync
        .onChange(of: vm.coordinateRegion) { _, newRegion in
            withAnimation {
                cameraPosition = .region(newRegion)
            }
        }
        // Set initial camera position from view model
        .task {
            // Ensure initial camera position is synced with view model's region
            // This handles the case where vm.coordinateRegion might be different from AppDefaults.initialRegion
            // due to persisted state or other initial logic in the ViewModel.
            if cameraPosition.region != vm.coordinateRegion {
                cameraPosition = .region(vm.coordinateRegion)
            }
        }
        // Sheets
        .sheet(item: $vm.selectedPoint) { PointDetailView(point: $0) }
        .sheet(isPresented: $isShowingFilter) {
            FilterView(selectedTechnologies: $vm.selectedTechnologies,
                       selectedOperators:    $vm.selectedOperators) {
                Task { await vm.startPointsLoadingFlow() }
            }
        }
        .sheet(isPresented: $isShowingSettings) { SettingsView(mapVM: vm) }
        .sheet(isPresented: $isShowingList)    {
            PointsListView(
                visiblePoints: $visibleClusterPoints,
                allPoints: $vm.points,
                isAllPointsLoaded: $vm.allPointsLoaded
            )
        }
    }
    
    // MARK: – Map layer with annotations & clusters
    private var mapLayer: some View {
        Map(position: $cameraPosition, interactionModes: .all) {
            UserAnnotation()
            // Single towers
            ForEach(visiblePoints, id: \ .id) { point in
                Annotation("", coordinate: point.coordinate) {
                    Button { vm.select(point) } label: {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(point.color())
                    }
                }
            }
            // Cluster bubbles
            ForEach(visibleClusters, id: \ .id) { cluster in
                Annotation("", coordinate: cluster.coordinate) {
                    Button {
                        // Use vm.coordinateRegion.span as it's reliably updated from map context
                        let currentSpan = vm.coordinateRegion.span
                        
                        // Zoom in on the cluster by halving the current span
                        let newLatitudeDelta = max(currentSpan.latitudeDelta / 2, 0.0001) // Halve the span, ensure minimum
                        let newLongitudeDelta = max(currentSpan.longitudeDelta / 2, 0.0001) // Halve the span, ensure minimum
                        
                        let newSpan = MKCoordinateSpan(
                            latitudeDelta: newLatitudeDelta,
                            longitudeDelta: newLongitudeDelta
                        )
                        
                        let newRegion = MKCoordinateRegion(
                            center: cluster.coordinate, // Center on the tapped cluster
                            span: newSpan
                        )
                        
                        withAnimation {
                            // Update the view model's region, which will then update cameraPosition via .onChange
                            vm.coordinateRegion = newRegion
                        }
                    } label: {
                        ZStack {
                            Circle().fill(.thinMaterial).frame(width: 34, height: 34)
                            Text("\(cluster.count)")
                                .font(.caption2.bold())
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
        }
        .onAppear {
            vm.requestUserLocation()
        }        // Provide actual pixel size to ClusterMap
        .readSize(onChange: { mapSize = $0 })
    }
    
    // MARK: – Cluster helpers
    @Sendable
    private func refreshAnnotations(with points: [Point]) async {
        await clusterManager.removeAll()
        await clusterManager.add(points)
        await reloadClusters(for: vm.coordinateRegion)
    }
    
    @Sendable
    private func reloadClusters(for region: MKCoordinateRegion) async {
        guard mapSize != .zero else { return }
        let diff = await clusterManager.reload(mapViewSize: mapSize, coordinateRegion: region)
        // Pobierz wszystkie punkty widoczne w zasięgu (zarówno pojedyncze, jak i z klastrów)
        let allVisible = await clusterManager.fetchVisibleNestedAnnotations()
        // Usuń duplikaty po stationId
        var seen = Set<String>()
        let uniqueVisible = allVisible.filter { seen.insert($0.details.stationId).inserted }
        await MainActor.run {
            apply(diff)
            visibleClusterPoints = uniqueVisible
        }
    }
    
    private func apply(_ diff: ClusterManager<Point>.Difference) {
        for removal in diff.removals {
            switch removal {
            case .annotation(let annotation):
                visiblePoints.removeAll { $0 == annotation }
            case .cluster(let cluster):
                visibleClusters.removeAll { $0.id == cluster.id }
            }
        }
        for insertion in diff.insertions {
            switch insertion {
            case .annotation(let annotation):
                visiblePoints.append(annotation)
            case .cluster(let cluster):
                visibleClusters.append(.init(id: cluster.id,
                                             coordinate: cluster.coordinate,
                                             count: cluster.memberAnnotations.count))
            }
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                if let message = vm.loadingMessage {
                    Text(message)
                        .font(.headline)
                        .foregroundColor(.white)
                }
                
                if let progress = vm.loadingProgress {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .white))
                        .frame(width: 200)
                    Text("\(Int(progress * 100))%")
                        .foregroundColor(.white)
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 10)
        }
    }
    
    // MARK: – UI sub-components (unchanged)
    private var searchBar: some View {
        HStack {
            TextField("Szukaj miejsca…", text: $vm.searchText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(Color(.systemBackground).opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
                .submitLabel(.search)
                .onSubmit(vm.performSearch)
            Button(action: vm.performSearch) {
                Image(systemName: "magnifyingglass")
                    .padding()
                    .background(.thinMaterial, in: Circle())
            }
        }
    }
    
    private var fabStack: some View {
        VStack(spacing: 16) {
            Button(action: vm.requestUserLocation) { fabIcon("location.fill") }
            Button { isShowingFilter   = true } label: { fabIcon("line.3.horizontal.decrease.circle") }
            Button { isShowingSettings = true } label: { fabIcon("gearshape") }
        }
        .padding(.trailing)
        .padding(.bottom, 32)
    }
    private func fabIcon(_ system: String) -> some View {
        Image(systemName: system)
            .padding()
            .background(.thinMaterial, in: Circle())
    }
    
    private var listButton: some View {
        Button { isShowingList = true } label: {
            Label("Lista", systemImage: "list.bullet")
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
        }
    }
}

// Helper to make MKCoordinateRegion Equatable for .onChange
extension MKCoordinateRegion: @retroactive Equatable {
    public static func == (lhs: MKCoordinateRegion, rhs: MKCoordinateRegion) -> Bool {
        return lhs.center.latitude == rhs.center.latitude &&
        lhs.center.longitude == rhs.center.longitude &&
        lhs.span.latitudeDelta == rhs.span.latitudeDelta &&
        lhs.span.longitudeDelta == rhs.span.longitudeDelta
    }
}
