import Foundation

class PointFileStorageManager {
    private let storageDirectory: URL
    private let fileManager: FileManager
    
    init(storageDirectory: URL, fileManager: FileManager = .default) {
        self.storageDirectory = storageDirectory
        self.fileManager = fileManager
    }
    
    func save(fileData: Data, date: Date, fileName: String) throws {
        guard fileName.hasSuffix(".xlsx") else {
            throw NSError(domain: "PointFileStorageManager", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Invalid file extension"])
        }
        
        let simplifiedName = simplifyFileName(fileName)
        let folderURL = folderURL(for: date)
        
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let fileURL = folderURL.appendingPathComponent(simplifiedName)
        
        try fileData.write(to: fileURL)
    }
    
    func listAvailableDates() throws -> [Date] {
        guard fileManager.fileExists(atPath: storageDirectory.path) else { return [] }
        let contents = try fileManager.contentsOfDirectory(atPath: storageDirectory.path)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        return contents.compactMap { formatter.date(from: $0) }
    }
    
    func listFiles(for date: Date) throws -> [URL] {
        let folder = folderURL(for: date)
        guard fileManager.fileExists(atPath: folder.path) else { return [] }
        let contents = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        return contents.filter { $0.pathExtension == "xlsx" }
    }
    
    
    func readFile(named fileName: String, for date: Date, onRowRead: ([String]) async -> Void) async throws {
        let fileURL = folderURL(for: date).appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw NSError(domain: "PointFileStorageManager", code: 1002, userInfo: [NSLocalizedDescriptionKey: "File not found"])
        }
                
        let sharedStrings = try quickSharedStrings(fileURL: fileURL, )
        let worksheet = try quickWorksheetPaths(fileURL: fileURL)
        var skipFirstRow: Bool = true
        let rows = try XLSXAsyncRowIterator(fileURL: fileURL, worksheetPath: worksheet.first!.value, sharedStrings: sharedStrings)
        for await row in rows {
            if skipFirstRow {
                skipFirstRow = false
                continue // Skip header row
            }
            let rowData = row.values.sorted(by: { $0.key < $1.key }).map { key, value in
                if key == "D"{
                    let oa: Double? = Double(value)
                    if let ts = oa, let timestamp = ts.oaDateToUnix() {
                        return String(Int(timestamp))
                    }
                    return ""
                }else{
                    return value
                }
            }
            await onRowRead(rowData)
        }
    }
    
    func deleteFolder(for date: Date) throws {
        let folder = folderURL(for: date)
        if fileManager.fileExists(atPath: folder.path) {
            try fileManager.removeItem(at: folder)
        }
    }
    
    func deleteAllFiles() throws {
        let allDates = try listAvailableDates()
        for date in allDates {
            try deleteFolder(for: date)
        }
    }
    
    // MARK: - Helpers
    
    private func folderURL(for date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return storageDirectory.appendingPathComponent(formatter.string(from: date))
    }
    
    private func simplifyFileName(_ fullName: String) -> String {
        let pattern = #"_-_stan_na_\d{4}-\d{2}-\d{2}"#
        return fullName.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
}
