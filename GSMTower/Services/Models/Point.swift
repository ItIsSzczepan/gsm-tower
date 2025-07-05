import Foundation
import CoreLocation // Added for CLLocationCoordinate2D

struct Point: Codable, Hashable, Sendable {
    // Added Identifiable
    var longitude: Double
    var latitude: Double
    let details: PointDetails
    let permissions: [PointPermission]

    // Custom coding keys to prevent 'id' from being encoded/decoded if not in source data
    enum CodingKeys: String, CodingKey {
        case longitude, latitude, details, permissions
    }
}

struct PointDetails: Codable, Hashable, Sendable {
    let city: String
    let location: String
    let stationId: String
    let teryt: String
}

struct PointPermission: Codable, Hashable, Sendable {
    let operatorName: String
    let decisionNumber: String
    let decisionType: String
    let expiryDate: Int
    let technology: String
}

