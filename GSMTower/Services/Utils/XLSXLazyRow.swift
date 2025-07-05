//
//  XLSXLazyRow.swift
//  GSMTower
//
//  Created by Jakub Szczepaniak on 26/05/2025.
//

import Foundation
import ZIPFoundation

// MARK: ––––– Helpers to avoid CoreXLSX heavyweight parsing –––––––––––––––––-

/// Fast workbook helper – returns *sheet‑name → worksheet path*.
public func quickWorksheetPaths(fileURL: URL) throws -> [String: String] {
    let archive = try Archive(url: fileURL, accessMode: .read)
    guard let wbEntry  = archive["xl/workbook.xml"],
          let relEntry = archive["xl/_rels/workbook.xml.rels"] else {
        throw CocoaError(.fileReadNoSuchFile)
    }
    let wbPairs = try SelfParse.sheetNameRidPairs(xml: try archive.extractSmallXML(entry: wbEntry))
    let ridMap  = try SelfParse.relsRidTargets(xml: try archive.extractSmallXML(entry: relEntry))
    return Dictionary(uniqueKeysWithValues: wbPairs.compactMap { (name, rid) in
        ridMap[rid].map { (name, $0) }
    })
}

/// Fast shared‑strings loader – returns `[String]`.
public func quickSharedStrings(fileURL: URL) throws -> [String] {
    let archive = try Archive(url: fileURL, accessMode: .read)
    guard let entry = archive["xl/sharedStrings.xml"] else { return [] }
    return try SelfParse.sharedStrings(xml: try archive.extractSmallXML(entry: entry))
}

// MARK: ––––– Public row model ––––––––––––––––––––––––––––––––––––––––––––-

public struct XLSXLazyRow {
    /// Excel row index (1‑based)
    public let index: UInt
    /// Column‑letter → cell value (already resolved via shared‑strings, if any)
    public let values: [String: String]
}

// MARK: ––––– Iterator ––––––––––––––––––––––––––––––––––––––––––––––––––––-
public final class XLSXAsyncRowIterator: NSObject, AsyncSequence, AsyncIteratorProtocol {
    public typealias Element = XLSXLazyRow

    // AsyncSequence requirement
    public func makeAsyncIterator() -> XLSXAsyncRowIterator { self }

    private var continuation: CheckedContinuation<XLSXLazyRow?, Never>?
    private var isFinished = false
    private let syncQueue = DispatchQueue(label: "LazyXLSX.sync")

    private var rowQueue: [XLSXLazyRow] = []

    // MARK: – Init (prawie bez zmian)
    private let sharedStrings: [String]
    private let inputStream: InputStream
    private var parser: XMLParser!
    
    private var currentRowIdx: UInt = 0
    private var values: [String:String] = [:]
    private var cellRef: String?
    private var cellType: String?
    private var buf = ""
    private var insideV = false

    public init(fileURL: URL, worksheetPath: String, sharedStrings: [String] = []) throws {
        self.sharedStrings = sharedStrings
        let archive = try Archive(url: fileURL, accessMode: .read)
        guard let entry = archive[worksheetPath] else { throw CocoaError(.fileReadNoSuchFile) }
        inputStream = try archive.makeStream(for: entry)
        super.init()
        setupParser()
        startParsing()
    }

    // MARK: – Async next()
    public func next() async -> XLSXLazyRow? {
        await withCheckedContinuation { continuation in
            syncQueue.sync {
                if !rowQueue.isEmpty {
                    let row = rowQueue.removeFirst()
                    continuation.resume(returning: row)
                } else if isFinished {
                    continuation.resume(returning: nil)
                } else {
                    self.continuation = continuation
                }
            }
        }
    }

    // MARK: – Parser handling
    private func setupParser() {
        parser = XMLParser(stream: inputStream)
        parser.delegate = self
        parser.shouldResolveExternalEntities = false
    }

    private func startParsing() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.parser.parse()
            self.syncQueue.sync {
                self.isFinished = true
                self.continuation?.resume(returning: nil)
                self.continuation = nil
            }
        }
    }

    // MARK: – Add parsed row
    private func enqueue(row: XLSXLazyRow) {
        syncQueue.sync {
            if let cont = continuation {
                continuation = nil
                cont.resume(returning: row)
            } else {
                rowQueue.append(row)
            }
        }
    }
}

extension XLSXAsyncRowIterator: XMLParserDelegate {
    public func parser(_ p: XMLParser, didStartElement n: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String : String] = [:]) {
        switch n {
        case "row":
            currentRowIdx = UInt(a["r"] ?? "") ?? currentRowIdx + 1
            values.removeAll(keepingCapacity: true)
        case "c":
            cellRef = a["r"]; cellType = a["t"]
        case "v":
            insideV = true; buf = ""
        default: break
        }
    }

    public func parser(_ p: XMLParser, foundCharacters s: String) {
        if insideV { buf += s }
    }

    public func parser(_ p: XMLParser, didEndElement n: String, namespaceURI: String?, qualifiedName: String?) {
        switch n {
        case "v": insideV = false
        case "c":
            guard let ref = cellRef else { break }
            let raw = buf.trimmingCharacters(in: .whitespacesAndNewlines)
            let val: String
            if cellType == "s", let idx = Int(raw), idx < sharedStrings.count {
                val = sharedStrings[idx]
            } else {
                val = raw
            }
            let col = ref.trimmingCharacters(in: .decimalDigits)
            values[col] = val
        case "row":
            let row = XLSXLazyRow(index: currentRowIdx, values: values)
            enqueue(row: row)
        default: break
        }
    }

    public func parser(_ p: XMLParser, parseErrorOccurred err: Error) {
        syncQueue.sync {
            self.isFinished = true
            self.continuation?.resume(returning: nil)
            self.continuation = nil
        }
    }

    // local parser state

}

// MARK: ––––– ZIPFoundation helper ––––––––––––––––––––––––––––––––––––––––-

extension OutputStream: @unchecked @retroactive Sendable {}
extension InputStream:  @unchecked @retroactive Sendable {}

private extension Archive {
    /// For tiny XML files – loads into a Data buffer.
    func extractSmallXML(entry: Entry) throws -> Data {
        var d = Data(); _ = try extract(entry, consumer: { d.append($0) }); return d
    }

    /// Creates a pipe‑backed **streaming** InputStream for a large worksheet.
    func makeStream(for entry: Entry) throws -> InputStream {
        var input: InputStream?; var output: OutputStream?
        Stream.getBoundStreams(withBufferSize: 64 * 1024, inputStream: &input, outputStream: &output)
        guard let inS = input, let outS = output else { throw CocoaError(.fileReadUnknown) }
        outS.open()
        DispatchQueue.global(qos: .userInitiated).async { [outS] in
            defer { outS.close() }
            do {
                _ = try self.extract(entry, consumer: { chunk in
                    chunk.withUnsafeBytes { raw in
                        guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                        var remaining = chunk.count
                        while remaining > 0 {
                            let written = outS.write(base.advanced(by: chunk.count - remaining), maxLength: remaining)
                            if written <= 0 { return }
                            remaining -= written
                        }
                    }
                })
            } catch { }
        }
        return inS
    }
}

// MARK: ––––– Minimal in‑house XML parsers for helpers ––––––––––––––––––––-

private enum SelfParse {
    static func sheetNameRidPairs(xml: Data) throws -> [(String,String)] {
        class D: NSObject, XMLParserDelegate {
            var rows: [(String,String)] = []
            func parser(_ p: XMLParser, didStartElement n: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String : String] = [:]) {
                if n == "sheet", let name = a["name"], let rid = a["r:id"] { rows.append((name,rid)) }
            }
        }
        let d = D(); XMLParser(data: xml).apply{ $0.delegate = d; $0.parse() }; return d.rows
    }
    static func relsRidTargets(xml: Data) throws -> [String:String] {
        class D: NSObject, XMLParserDelegate {
            var map: [String:String] = [:]
            func parser(_ p: XMLParser, didStartElement n: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String : String] = [:]) {
                if n == "Relationship", let id = a["Id"], let t = a["Target"], t.hasPrefix("worksheets/") { map[id] = "xl/" + t }
            }
        }
        let d = D(); XMLParser(data: xml).apply{ $0.delegate = d; $0.parse() }; return d.map
    }
    static func sharedStrings(xml: Data) throws -> [String] {
        class D: NSObject, XMLParserDelegate {
            var strings = [String]()
            private var buf = ""; private var insideT = false
            func parser(_ p: XMLParser, didStartElement n: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String : String] = [:]) { if n == "t" { insideT = true; buf = "" } }
            func parser(_ p: XMLParser, foundCharacters s: String) { if insideT { buf += s } }
            func parser(_ p: XMLParser, didEndElement n: String, namespaceURI: String?, qualifiedName: String?) { if n == "t" { insideT = false; strings.append(buf) } }
        }
        let d = D(); XMLParser(data: xml).apply{ $0.delegate = d; $0.parse() }; return d.strings
    }
}

// MARK: ––––– XMLParser fluent helper –––––––––––––––––––––––––––––––––––––-

private extension XMLParser { @discardableResult func apply(_ block: (XMLParser)->Void) -> XMLParser { block(self); return self } }
