//
//  MapViewModel.swift
//  GSMTower
//
//  Created by Jakub Szczepaniak on 26/05/2025.
//


//
//  MapScreen.swift
//  GSMExplorer
//
//  Updated for new `Point` model on 26/05/2025.
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - View‑Model
@MainActor
final class MapViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    // Published
    @Published var coordinateRegion: MKCoordinateRegion
    @Published var points: [Point] = []
    @Published var selectedPoint: Point?
    @Published var isDataOutdated = false
    
    @Published var isLoading = false
    @Published var loadingMessage: String? = nil
    @Published var loadingProgress: Double? = nil

    
    // filters
    @Published var selectedTechnologies: Set<String> = []
    @Published var selectedOperators: Set<String> = []
    
    // search
    @Published var searchText = ""
    
    // deps
    private let repository = PointsRepository.shared
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder() // Make geocoder an instance property
    
    // Points loading state
    @Published var allPointsLoaded = false
    private var allPoints: [Point] = []
    private var allPointsTask: Task<Void, Never>? = nil
    private var currentFilter: PointFilter? = nil
    
    override init() {
        coordinateRegion = AppConstants.initialRegion
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        Task { await validateLocalData() }
        Task { await startPointsLoadingFlow() }
    }

    // MARK: – Points loading flow
    func startPointsLoadingFlow() async {
        resetPointsLoadingState()
        let filter = makeCurrentFilter()
        currentFilter = filter
        // 1. Load region points immediately
        await fetchPointsAroundVisibleRegion(filter: filter)
        // 2. Start loading all points in background
        allPointsTask = Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                let all = try await self.repository.getAllPoints(filter: filter)
                await MainActor.run {
                    self.allPoints = all
                    self.allPointsLoaded = true
                    self.points = all
                }
            } catch {
                // Optionally handle error
            }
        }
    }

    private func resetPointsLoadingState() {
        allPointsLoaded = false
        allPoints = []
        allPointsTask?.cancel()
        allPointsTask = nil
    }

    private func makeCurrentFilter() -> PointFilter? {
        let technologyFilter = selectedTechnologies.isEmpty ? nil : Array(selectedTechnologies)
        let operatorFilter = selectedOperators.isEmpty ? nil : Array(selectedOperators)
        if technologyFilter == nil && operatorFilter == nil { return nil }
        return PointFilter(technologies: technologyFilter, operatorNames: operatorFilter)
    }

    // MARK: – Data freshness
    func validateLocalData() async {
        do {
            isDataOutdated = try await repository.isNewVersionAvailable()
            guard isDataOutdated else { return }
            isLoading = true
            loadingMessage = "Aktualizuję dane..."
            loadingProgress = 0.0
            try await repository.refresh { progress, message in
                DispatchQueue.main.async {
                    self.loadingMessage = message
                    self.loadingProgress = progress
                }
            }
            isDataOutdated = false
            await startPointsLoadingFlow()
        } catch {
            print("Refresh failed", error)
        }
        await MainActor.run {
            isLoading = false
            loadingMessage = nil
            loadingProgress = nil
        }
    }

    
    // MARK: – Fetch
    func fetchPointsAroundVisibleRegion(filter: PointFilter? = nil) async {
        guard !allPointsLoaded else { return } // Don't fetch region points if all loaded
        isLoading = true
        defer { isLoading = false }
        
        let center = Location(latitude: coordinateRegion.center.latitude,
                              longitude: coordinateRegion.center.longitude)
        
        // Use the smaller of visible radius or selectedSearchRadius (converted to meters)
        let radius = visibleRadiusMeters()
        
        guard radius > 0 else { return }
        
        // Apply filters if they are not empty
        let filter = filter ?? makeCurrentFilter()
        
        do {
            let fetched = try await repository.getPoints(for: center, radiusMeters: radius, filter: filter ?? PointFilter())
            if allPointsLoaded || !allPoints.isEmpty {
                await MainActor.run { points = allPoints }
                return
            }
            await MainActor.run { points = fetched }
        } catch { print("Fetching failed", error) }
    }
    
    private func visibleRadiusMeters() -> Double {
        coordinateRegion.span.latitudeDelta * 111_000 / 2.0
    }
    
    // MARK: – Map interactions
    func refreshIfNeeded(for region: MKCoordinateRegion) {
        coordinateRegion = region
        if !allPointsLoaded {
            Task { await fetchPointsAroundVisibleRegion() }
        }
    }
    func select(_ point: Point) { selectedPoint = point }
    
    // MARK: – User‑location support
    func requestUserLocation() {
        locationManager.requestWhenInUseAuthorization()
        if let loc = locationManager.location {
            moveTo(coordinate: loc.coordinate)
        } else {
            locationManager.startUpdatingLocation()
        }
    }
    private func moveTo(coordinate: CLLocationCoordinate2D, span: MKCoordinateSpan = .init(latitudeDelta: 0.08, longitudeDelta: 0.08)) {
        coordinateRegion = MKCoordinateRegion(center: coordinate, span: span)
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Dispatch back to the main actor since we need to update UI state
        Task { @MainActor in
            guard let loc = locations.last else { return }
            self.moveTo(coordinate: loc.coordinate)
            manager.stopUpdatingLocation()
        }
    }
    
    // MARK: – Search
    func performSearch() {
        // Cancel any ongoing geocode operation before starting a new one.
        if (geocoder.isGeocoding) {
            geocoder.cancelGeocode()
        }
        
        guard !searchText.isEmpty else { return }
        
        // Capture the current search text for the closure,
        // to ensure we only act on the results for the latest search query.
        let currentSearchText = searchText
        
        geocoder.geocodeAddressString(currentSearchText) { [weak self] placemarks, error in
            guard let self = self else { return }
            
            // If an error occurred (e.g., operation cancelled by a new search), or no placemarks, do nothing.
            // CLError.geocodeCanceled is a common error code when cancelGeocode() is called.
            if error != nil {
                // You might want to log non-cancellation errors if needed.
                // print("Geocoding error: \(error!)")
                return
            }
            
            // Ensure this completion is for the most recent search text.
            // This is an additional safeguard in case cancellation isn't immediate or there's a race condition.
            guard currentSearchText == self.searchText else {
                return
            }
            
            guard let coord = placemarks?.first?.location?.coordinate else {
                // Handle case where no placemarks are found, e.g., show an alert to the user.
                // print("No location found for: \(currentSearchText)")
                return
            }
            
            // Move the map to the found coordinate.
            self.moveTo(coordinate: coord)
        }
    }
}
