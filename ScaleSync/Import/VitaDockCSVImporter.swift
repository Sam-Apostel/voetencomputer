//
//  VitaDockCSVImporter.swift
//  ScaleSync
//
//  Imports the CSV export from VitaDock Online / the VitaDock+ app so your
//  history is preserved. The export format varies by locale, so this parser
//  detects the delimiter and matches columns by header keywords.
//

import Foundation
import SwiftData

enum VitaDockCSVImporter {

    struct Result {
        var imported = 0
        var skipped = 0
    }

    @MainActor
    static func importCSV(at url: URL, container: ModelContainer) throws -> Result {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }

        var text = try String(decoding: Data(contentsOf: url), as: UTF8.self)
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard lines.count > 1 else { return Result() }

        let header = lines.removeFirst()
        let delimiter: Character = header.filter { $0 == ";" }.count >= header.filter { $0 == "," }.count ? ";" : ","
        let columns = split(header, on: delimiter).map { $0.lowercased() }

        func columnIndex(_ keywords: [String]) -> Int? {
            columns.firstIndex { col in keywords.contains { col.contains($0) } }
        }

        let dateIdx = columnIndex(["date", "datum", "zeit", "time"])
        let weightIdx = columnIndex(["weight", "gewicht", "poids", "peso"])
        let fatIdx = columnIndex(["fat", "fett", "graisse", "grasa"])
        let waterIdx = columnIndex(["water", "wasser", "eau", "agua"])
        let muscleIdx = columnIndex(["muscle", "muskel"])
        let boneIdx = columnIndex(["bone", "knochen", "os ", "hueso"])

        guard let dIdx = dateIdx, let wIdx = weightIdx else {
            throw NSError(domain: "VitaDockCSV", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not find date/weight columns. Header was: \(header)"
            ])
        }

        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "dd.MM.yyyy HH:mm",
                       "dd.MM.yyyy HH:mm:ss", "MM/dd/yyyy HH:mm", "dd.MM.yyyy", "yyyy-MM-dd", "MM/dd/yyyy"]
        let formatters: [DateFormatter] = formats.map { f in
            let df = DateFormatter()
            df.dateFormat = f
            df.locale = Locale(identifier: "en_US_POSIX")
            return df
        }

        func parseDate(_ s: String) -> Date? {
            for f in formatters { if let d = f.date(from: s) { return d } }
            return nil
        }

        func parseNumber(_ s: String?) -> Double? {
            guard var s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
            s = s.replacingOccurrences(of: ",", with: ".")
            s = s.filter { "0123456789.-".contains($0) }
            return Double(s)
        }

        let context = container.mainContext
        var result = Result()

        for line in lines {
            let fields = split(line, on: delimiter)
            guard fields.count > max(dIdx, wIdx),
                  let date = parseDate(fields[dIdx].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))),
                  let weight = parseNumber(fields[wIdx]), weight > 2 else {
                result.skipped += 1
                continue
            }

            func field(_ idx: Int?) -> Double? {
                guard let idx, fields.count > idx else { return nil }
                return parseNumber(fields[idx])
            }

            let key = ScaleMeasurement.makeKey(date: date, userId: 0)
            let predicate = #Predicate<ScaleMeasurement> { $0.key == key }
            if (try? context.fetch(FetchDescriptor(predicate: predicate)))?.first != nil {
                result.skipped += 1
                continue
            }

            let m = ScaleMeasurement(
                date: date, userId: 0, weightKg: weight,
                fatPercent: field(fatIdx), waterPercent: field(waterIdx),
                musclePercent: field(muscleIdx), boneKg: field(boneIdx),
                source: "csv"
            )
            context.insert(m)
            result.imported += 1
        }
        try context.save()
        return result
    }

    /// CSV field splitter with basic quoted-field support.
    private static func split(_ line: String, on delimiter: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" { inQuotes.toggle(); continue }
            if ch == delimiter && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        fields.append(current)
        return fields
    }
}
