import Foundation
import GRDB

class DatabaseManager {
    let dbQueue: DatabaseQueue
    
    init(inMemory: Bool = false) throws {
        if inMemory {
            dbQueue = try DatabaseQueue()
        } else {
            let path = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("gsm_points.sqlite").path
            dbQueue = try DatabaseQueue(path: path)
            
            try dbQueue.writeWithoutTransaction { db in
                // set WAL
                _ = try String.fetchOne(db, sql: "PRAGMA journal_mode=WAL;")
                try db.execute(sql: "PRAGMA synchronous=NORMAL;")
            }
        }
        
        try migrator.migrate(dbQueue)
    }
        
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("createTables") { db in
            // R-Tree with location
            try db.execute(sql: """
                CREATE VIRTUAL TABLE points USING rtree(
                    id INTEGER PRIMARY KEY,
                    minLat DOUBLE,
                    maxLat DOUBLE,
                    minLon DOUBLE,
                    maxLon DOUBLE
                )
            """)
            
            // point details
            try db.create(table: "point_details") { t in
                t.column("id", .integer).primaryKey()
                t.column("city", .text)
                t.column("location", .text)
                t.column("stationId", .text)
                t.column("teryt", .text)
            }
            
            // permissions
            try db.create(table: "permissions") { t in
                t.column("id", .integer).primaryKey()
                t.column("pointId", .integer).notNull().references("point_details", onDelete: .cascade)
                t.column("operatorName", .text).notNull()
                t.column("decisionNumber", .text).notNull()
                t.column("decisionType", .text)
                t.column("expiryDate", .integer)
                t.column("technology", .text)
            }
        }
        
        // Indexes
        migrator.registerMigration("createIndexes") { db in
            // point details stationId index
            try db.execute(sql: """
                 CREATE UNIQUE INDEX IF NOT EXISTS idx_point_station
                 ON point_details(stationId);
             """)
            
            // permission unique index for faster adding
            try db.execute(sql: """
                 CREATE UNIQUE INDEX IF NOT EXISTS idx_perm_unique
                 ON permissions(pointId, technology, operatorName);
             """)
            
            // permission technology index
            try db.execute(sql: """
                 CREATE INDEX IF NOT EXISTS idx_perm_tech
                 ON permissions(technology);
             """)
            
            // permission operator name index
            try db.execute(sql: """
                 CREATE INDEX IF NOT EXISTS idx_perm_oper
                 ON permissions(operatorName);
             """)
        }
        
        return migrator
    }
        
    func save(_ points: [Point]) throws {
        try dbQueue.write { db in
            for point in points { try self.writePoint(point, db) }
        }
    }
    
    private func writePoint(_ point: Point, _ db: Database) throws {
        try db.execute(sql: """
                INSERT INTO point_details (stationId, city, location, teryt)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(stationId) DO NOTHING;
            """, arguments: [point.details.stationId, point.details.city, point.details.location, point.details.teryt])
        
        let pointId: Int64 = try Int64.fetchOne(
            db, sql: "SELECT id FROM point_details WHERE stationId = ?",
            arguments: [point.details.stationId]
        )!
        
        try db.execute(sql: """
                INSERT OR IGNORE INTO points (id, minLat, maxLat, minLon, maxLon)
                VALUES (?, ?, ?, ?, ?);
            """, arguments: [pointId, point.latitude, point.latitude, point.longitude, point.longitude])
        
        for perm in point.permissions {
            try db.execute(sql: """
                  INSERT OR IGNORE INTO permissions
                    (pointId, operatorName, decisionNumber, decisionType, expiryDate, technology)
                  VALUES (?, ?, ?, ?, ?, ?);
                """, arguments: [
                    pointId, perm.operatorName, perm.decisionNumber,
                    perm.decisionType, perm.expiryDate, perm.technology
                ])
        }
        
    }
    
    func deleteAllPoints() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM permissions")
            try db.execute(sql: "DELETE FROM point_details")
            try db.execute(sql: "DELETE FROM points")
        }
    }
    
    func findPoints(near location: Location, radius: Double, filter: PointFilter) async throws -> [Point] {
        let latMin = location.latitude - radius / 111_000
        let latMax = location.latitude + radius / 111_000
        let lonMin = location.longitude - radius / 111_000
        let lonMax = location.longitude + radius / 111_000

        return try await dbQueue.read { db in // Changed to async read
            var conditions: [String] = [
                "minLat >= ?",
                "maxLat <= ?",
                "minLon >= ?",
                "maxLon <= ?"
            ]
            var arguments: [DatabaseValueConvertible] = [latMin, latMax, lonMin, lonMax]

            if let technologies = filter.technologies, !technologies.isEmpty {
                let placeholders = technologies.map { _ in "?" }.joined(separator: ", ")
                conditions.append("permissions.technology IN (\(placeholders))")
                arguments.append(contentsOf: technologies)
            }

            if let operatorNames = filter.operatorNames, !operatorNames.isEmpty {
                let placeholders = operatorNames.map { _ in "?" }.joined(separator: ", ")
                conditions.append("permissions.operatorName IN (\(placeholders))")
                arguments.append(contentsOf: operatorNames)
            }

            let whereClause = conditions.joined(separator: " AND ")

            let rows = try Row.fetchAll(db, sql: """
                SELECT
                    points.id AS pointId,
                    point_details.city, point_details.location, point_details.stationId, point_details.teryt,
                    permissions.operatorName, permissions.decisionNumber, permissions.decisionType, permissions.expiryDate, permissions.technology,
                    points.minLat, points.minLon
                FROM points
                JOIN point_details ON points.id = point_details.id
                JOIN permissions ON permissions.pointId = point_details.id
                WHERE \(whereClause)
            """, arguments: StatementArguments(arguments))

            var grouped: [Int64: (PointDetails, Double, Double, [PointPermission])] = [:]

            for row in rows {
                let pointId = row["pointId"] as Int64
                let permission = PointPermission(
                    operatorName: row["operatorName"],
                    decisionNumber: row["decisionNumber"],
                    decisionType: row["decisionType"],
                    expiryDate: row["expiryDate"],
                    technology: row["technology"]
                )

                if grouped[pointId] == nil {
                    let details = PointDetails(
                        city: row["city"],
                        location: row["location"],
                        stationId: row["stationId"],
                        teryt: row["teryt"]
                    )
                    let lat = row["minLat"] as Double
                    let lon = row["minLon"] as Double
                    grouped[pointId] = (details, lon, lat, [permission])
                } else {
                    grouped[pointId]?.3.append(permission)
                }
            }

            return grouped.map { (_, tuple) in
                Point(
                    longitude: tuple.1,
                    latitude: tuple.2,
                    details: tuple.0,
                    permissions: tuple.3
                )
            }
        }
    }

    
    func getAllTechnologies() throws -> [String] {
        return try dbQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT technology FROM permissions WHERE technology IS NOT NULL
                ORDER BY technology COLLATE NOCASE ASC
            """)
        }
    }
    
    func getAllOperatorNames() throws -> [String] {
        return try dbQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT operatorName FROM permissions WHERE operatorName IS NOT NULL
                ORDER BY operatorName COLLATE NOCASE ASC
            """)
        }
    }

    func getAllPoints(filter: PointFilter? = nil) async throws -> [Point] {
        return try await dbQueue.read { db in
            var conditions: [String] = []
            var arguments: [DatabaseValueConvertible] = []

            if let filter = filter {
                if let technologies = filter.technologies, !technologies.isEmpty {
                    let placeholders = technologies.map { _ in "?" }.joined(separator: ", ")
                    conditions.append("permissions.technology IN (\(placeholders))")
                    arguments.append(contentsOf: technologies)
                }
                if let operatorNames = filter.operatorNames, !operatorNames.isEmpty {
                    let placeholders = operatorNames.map { _ in "?" }.joined(separator: ", ")
                    conditions.append("permissions.operatorName IN (\(placeholders))")
                    arguments.append(contentsOf: operatorNames)
                }
            }

            let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")

            let rows = try Row.fetchAll(db, sql: """
                SELECT
                    points.id AS pointId,
                    point_details.city, point_details.location, point_details.stationId, point_details.teryt,
                    permissions.operatorName, permissions.decisionNumber, permissions.decisionType, permissions.expiryDate, permissions.technology,
                    points.minLat, points.minLon
                FROM points
                JOIN point_details ON points.id = point_details.id
                JOIN permissions ON permissions.pointId = point_details.id
                \(whereClause)
            """, arguments: StatementArguments(arguments))

            var grouped: [Int64: (PointDetails, Double, Double, [PointPermission])] = [:]

            for row in rows {
                let pointId = row["pointId"] as Int64
                let permission = PointPermission(
                    operatorName: row["operatorName"],
                    decisionNumber: row["decisionNumber"],
                    decisionType: row["decisionType"],
                    expiryDate: row["expiryDate"],
                    technology: row["technology"]
                )

                if grouped[pointId] == nil {
                    let details = PointDetails(
                        city: row["city"],
                        location: row["location"],
                        stationId: row["stationId"],
                        teryt: row["teryt"]
                    )
                    let lat = row["minLat"] as Double
                    let lon = row["minLon"] as Double
                    grouped[pointId] = (details, lon, lat, [permission])
                } else {
                    grouped[pointId]?.3.append(permission)
                }
            }

            return grouped.map { (_, tuple) in
                Point(
                    longitude: tuple.1,
                    latitude: tuple.2,
                    details: tuple.0,
                    permissions: tuple.3
                )
            }
        }
    }
}
