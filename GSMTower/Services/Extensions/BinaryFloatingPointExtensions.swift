//
//  BinaryFloatingPointExtensions.swift
//  GSMTower
//
//  Created by Jakub Szczepaniak on 26/05/2025.
//

import Foundation


public extension BinaryFloatingPoint {
    /// Converts an Excel / OADate serial value to a Unix timestamp (seconds since 1970‑01‑01 UTC).
    /// - Parameter timeZone: **Interpretation** of the serial value. Excel stores dates relative
    ///   to the *local* clock, so if you pass `.current` you’ll get the same civil date back.
    ///   The default has been changed to UTC to avoid off‑by‑one‑day surprises when comparing
    ///   raw timestamps.
    func excelSerialToUnix(timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!) -> TimeInterval? {
        let serial = Double(self)
        let wholeDays = Int(serial)
        let fraction  = serial - Double(wholeDays)
        // Adjust for Excel’s fictitious 29 Feb 1900 (serial 60)
        let correctedDays = wholeDays >= 60 ? wholeDays - 1 : wholeDays
        var originComps = DateComponents()
        originComps.year = 1899; originComps.month = 12; originComps.day = 31; originComps.timeZone = timeZone
        let cal = Calendar(identifier: .gregorian)
        guard let origin = cal.date(from: originComps) else { return nil }
        let date = origin.addingTimeInterval(TimeInterval(correctedDays) * 86_400 + fraction * 86_400)
        return date.timeIntervalSince1970
    }
    /// Alias for developers coming from .NET `DateTime.ToOADate()`.
    func oaDateToUnix(timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!) -> TimeInterval? {
        excelSerialToUnix(timeZone: timeZone)
    }
}
