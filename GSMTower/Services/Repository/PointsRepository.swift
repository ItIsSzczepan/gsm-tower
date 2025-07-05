import Foundation

final class PointsRepository {
    private let downloader: PointFileDownloader
    private let storage: PointFileStorageManager
    private let db: DatabaseManager
    private let mapper: PointFileMapping
    
    private let dataSourceURL = URL(string: "https://bip.uke.gov.pl/pozwolenia-radiowe/wykaz-pozwolen-radiowych-tresci/stacje-gsm-umts-lte-5gnr-oraz-cdma,12,0.html")!
    
    static let shared: PointsRepository = {
        do {
            let downloader = PointFileDownloader()
            let storage = PointFileStorageManager(
                storageDirectory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            )
            let database = try DatabaseManager()
            
            return PointsRepository(
                downloader: downloader,
                storage: storage,
                db: database,
                mapper: PointFileMapper()
            )
        } catch {
            fatalError("Nie udało się utworzyć bazy danych: \(error.localizedDescription)")
        }
    }()
    
    
    init(
        downloader: PointFileDownloader,
        storage: PointFileStorageManager,
        db: DatabaseManager,
        mapper: PointFileMapping,
    ) {
        self.downloader = downloader
        self.storage = storage
        self.db = db
        self.mapper = mapper
    }
    
    func isNewVersionAvailable() async throws -> Bool {
        let remoteDate = try await downloader.fetchCurrentDataDate(from: dataSourceURL)
        let localDates = try storage.listAvailableDates()
        guard let latestLocal = localDates.max() else { return true }
        let calendar = Calendar.current
        let remoteComponents = calendar.dateComponents([.year, .month, .day], from: remoteDate)
        let localComponents = calendar.dateComponents([.year, .month, .day], from: latestLocal)
        
        // Compare the components directly
        if remoteComponents.year! > localComponents.year! { return true }
        if remoteComponents.year! < localComponents.year! { return false }
        if remoteComponents.month! > localComponents.month! { return true }
        if remoteComponents.month! < localComponents.month! { return false }
        if remoteComponents.day! > localComponents.day! { return true }
        return false
    }
    
    // MARK: - 2. Refresh data
    
    func refresh(progress: @escaping (Double, String) -> Void) async throws {
        // 1. Download current files
        progress(0.0, "Pobieranie plików...")
        try await downloader.downloadFiles(from: dataSourceURL) { date, data, fileName in
            do {
                try self.storage.save(fileData: data, date: date, fileName: fileName)
            } catch {
            }
        }
        
        // 2. Remove old data
        progress(0.3, "Usuwaie starych punktów")
        try db.deleteAllPoints()
        
        // 3. Load and parse data
        progress(0.4, "Odczytywanie plików")
        let availableDates = try storage.listAvailableDates()
        guard let latestDate = availableDates.max() else {
            progress(1.0, "Brak dostępnych dat")
            return
        }
        
        // 3a. Divide file into 3 batches
        let files = try storage.listFiles(for: latestDate)
        let fileBatches = files.chunked(into: 3)
        
        // 3b. Set async saving
        let limiter  = ConcurrencyLimiter(limit: 8)
        let acc = PointAccumulator { batch in
            try await limiter.run(tasks: [
                { try self.db.save(batch) }
            ])
        }
        
        // 3c. Read and pares files
        for (batchIdx, batch) in fileBatches.enumerated() {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for url in batch {
                    group.addTask {
                        let fileName = url.lastPathComponent
                        let tech = url.deletingPathExtension().lastPathComponent
                        try await self.storage.readFile(named: fileName, for: latestDate) { row in
                            do {
                                if let p = try? self.mapper.parse(fields: row, technology: tech) {
                                    try await acc.add(p)
                                }
                            }catch {
                                // NO-OP
                            }
                        }
                    }
                }
                try await group.waitForAll()
            }
            let done = 0.40 + 0.55 * Double(batchIdx + 1) / Double(fileBatches.count)
            progress(done, "Przetwarzanie plików \(batchIdx + 1)/\(fileBatches.count)")
        }
        
        try await acc.finish()
        progress(1.0, "Gotowe")
    }
    
    func getPoints(for center:  Location, radiusMeters: Double, filter: PointFilter) async throws -> [Point] {
        return try await db.findPoints(near: center, radius: radiusMeters, filter: filter) // Changed to call async findPoints
    }
    
    func getTechnologies() throws -> [String] {
        return try db.getAllTechnologies()
    }
    
    func getOperatorNames() throws -> [String] {
        return try db.getAllOperatorNames()
    }
    
    func getLocalDates() throws -> [Date] {
        return try storage.listAvailableDates()
    }
    
    func getRemoteDate() async throws -> Date {
        return try await downloader.fetchCurrentDataDate(from: dataSourceURL)
    }
    
    func deleteAllLocalData() throws {
        try storage.deleteAllFiles()
        try db.deleteAllPoints()
    }

    func getAllPoints() async throws -> [Point] {
        return try await db.getAllPoints()
    }

    func getAllPoints(filter: PointFilter? = nil) async throws -> [Point] {
        return try await db.getAllPoints(filter: filter)
    }
}
