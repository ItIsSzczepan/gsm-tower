import Foundation

protocol PointFileMapping {
    func parse(fields: [String], technology: String) throws -> Point
}

struct PointFileMapper: PointFileMapping {

    func parse(fields: [String], technology: String) throws -> Point {
        guard fields.count == 10 else {
            throw NSError(domain: "PointFileMapper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid data count"])
        }

        guard !technology.isEmpty else {
            throw NSError(domain: "PointFileMapper", code: 2, userInfo: [NSLocalizedDescriptionKey: "Technology cannot be empty"])
        }

        let operatorName = fields[0]
        let decisionNumber = fields[1]
        let decisionType = fields[2]
        let expiryDateString = fields[3]
        let longitudeString = fields[4]
        let latitudeString = fields[5]
        let city = fields[6]
        let location = fields[7]
        let stationId = fields[8]
        let teryt = fields[9]

        guard !operatorName.isEmpty,
              !decisionNumber.isEmpty,
              !decisionType.isEmpty,
              !expiryDateString.isEmpty,
              !longitudeString.isEmpty,
              !latitudeString.isEmpty,
              !city.isEmpty,
              !location.isEmpty,
              !stationId.isEmpty,
              !teryt.isEmpty else {
            throw NSError(domain: "PointFileMapper", code: 3, userInfo: [NSLocalizedDescriptionKey: "Fields cannot be empty"])
        }

        guard let expiryDate = Int(expiryDateString) else {
            throw NSError(domain: "PointFileMapper", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid expiry date format"])
        }

        guard let longitude = convertCoordinate(longitudeString),
              let latitude = convertCoordinate(latitudeString) else {
            throw NSError(domain: "PointFileMapper", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid coordinate format"])
        }

        let details = PointDetails(city: city, location: location, stationId: stationId, teryt: teryt)
        let permission = PointPermission(operatorName: operatorName, decisionNumber: decisionNumber, decisionType: decisionType, expiryDate: expiryDate, technology: technology)

        return Point(
            longitude: roundTo7Decimals(longitude),
            latitude: roundTo7Decimals(latitude),
            details: details,
            permissions: [permission]
        )
    }

    private func convertCoordinate(_ coordinate: String) -> Double? {
        let pattern = #"(\d{1,2})[ENWS]((\d{2})'(\d{2})")"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])

        guard let match = regex?.firstMatch(in: coordinate, options: [], range: NSRange(location: 0, length: coordinate.count)),
              let degreesRange = Range(match.range(at: 1), in: coordinate),
              let minutesRange = Range(match.range(at: 3), in: coordinate),
              let secondsRange = Range(match.range(at: 4), in: coordinate) else {
            return nil
        }

        let degrees = Double(coordinate[degreesRange]) ?? 0.0
        let minutes = Double(coordinate[minutesRange]) ?? 0.0
        let seconds = Double(coordinate[secondsRange]) ?? 0.0

        let decimalDegrees = degrees + (minutes / 60) + (seconds / 3600)

        return coordinate.contains("W") || coordinate.contains("S") ? -decimalDegrees : decimalDegrees
    }

    private func roundTo7Decimals(_ value: Double) -> Double {
        let factor = pow(10.0, 7.0)
        return (value * factor).rounded() / factor
    }
}
