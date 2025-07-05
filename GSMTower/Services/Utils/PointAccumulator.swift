
actor PointAccumulator {
    private var map: [String : Point] = [:]
    private let flushSize: Int
    private let flushHandler: ([Point]) async throws -> Void
    
    init(flushSize: Int = 5_000,
         flushHandler: @escaping ([Point]) async throws -> Void) {
        self.flushSize = flushSize
        self.flushHandler = flushHandler
    }
    
    func add(_ point: Point) async throws {
        let id = point.details.stationId
        if var existing = map[id] {
            let newPerms = point.permissions.filter { perm in
                !existing.permissions.contains(where: {
                    $0.technology == perm.technology &&
                    $0.operatorName == perm.operatorName
                })
            }
            existing = Point(
                longitude: existing.longitude,
                latitude: existing.latitude,
                details: existing.details,
                permissions: existing.permissions + newPerms
            )
            map[id] = existing
        } else {
            map[id] = point
        }
        
        if map.count >= flushSize {
            try await flush()
        }
    }
    
    func flush() async throws {
        guard !map.isEmpty else { return }
        let batch = Array(map.values)
        map.removeAll(keepingCapacity: true)
        try await flushHandler(batch)
    }
    
    func finish() async throws { try await flush() }
}
