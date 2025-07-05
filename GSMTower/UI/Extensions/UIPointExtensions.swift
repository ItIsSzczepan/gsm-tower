//
//  UIPointExtensions.swift
//  GSMTower
//
//  Created by Jakub Szczepaniak on 26/05/2025.
//
import MapKit
import ClusterMap
import SwiftUICore

extension Point: CoordinateIdentifiable, Identifiable {
    var coordinate: CLLocationCoordinate2D {
        get {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        set {
            latitude = newValue.latitude
            longitude = newValue.longitude
        }
    }
    
    // model from Point.swift fileciteturn1file0
    public var id: String { details.stationId }
    //settable coordinate for MapKit

    public var operatorNames: [String] { permissions.map { $0.operatorName } }
    public var technologies: [String] { permissions.map { $0.technology } }
    public var title: String {
        let ops = operatorNames.joined(separator: ", ")
        let techs = technologies.joined(separator: ", ")
        return "\(ops) • \(techs)"
    }
    
    public func color() -> Color {
        let op = permissions.first?.operatorName.uppercased() ?? ""
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
