//
//  PointDetailViewModel.swift
//  GSMTower
//
//  Created by Jakub Szczepaniak on 03/06/2025.
//

import Foundation
import SwiftUICore


class PointDetailViewModel: ObservableObject {
    let point: Point

    @Published var existsAnswer: Bool? = nil
    @Published var workingAnswer: Bool? = nil

    init(point: Point) {
        self.point = point
    }

    var city: String { point.details.city }
    var location: String { point.details.location }
    var stationId: String { point.details.stationId }
    
    var mainOperator: String? {
        point.permissions.first?.operatorName
    }


    var uniquePermissions: [PointPermission] {
        var seen = Set<PointPermission>()
        var result: [PointPermission] = []
        for perm in point.permissions {
            if !seen.contains(perm) {
                seen.insert(perm)
                result.append(perm)
            }
        }
        return result
    }

    func formattedDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return date.formatted(date: .numeric, time: .omitted)
    }

    func openCompass() {
        // TODO: implementacja kompasu – np. przejście do nowego widoku z kompasem
        print("Otwórz kompas dla punktu \(point.details.stationId)")
    }
}
