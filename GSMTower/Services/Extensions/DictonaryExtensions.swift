
extension Dictionary where Key == String, Value == Point {
    mutating func mergePoint(_ point: Point) {
        if let existing = self[point.details.stationId] {
            self[point.details.stationId] = Point(
                longitude: existing.longitude,
                latitude: existing.latitude,
                details: existing.details,
                permissions: existing.permissions + point.permissions
            )
        } else {
            self[point.details.stationId] = point
        }
    }
}
