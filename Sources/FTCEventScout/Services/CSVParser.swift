import Foundation

enum CSVParser {
    static func rows(from data: Data) throws -> [[String: String]] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CSVParserError.invalidEncoding
        }
        // Swift treats CRLF as a single extended grapheme cluster, so a
        // Character-by-Character parser will not match either "\r" or "\n".
        // Normalize line endings first so CSVs written by Python's csv module
        // split into records correctly on macOS.
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let records = parse(normalizedText)
        guard let rawHeaders = records.first else { return [] }
        let headers = rawHeaders.map { $0.replacingOccurrences(of: "\u{feff}", with: "") }
        return records.dropFirst().compactMap { record in
            guard record.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
                return nil
            }
            var row: [String: String] = [:]
            for (index, header) in headers.enumerated() {
                row[header] = index < record.count
                    ? record[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
            }
            return row
        }
    }

    private static func parse(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var insideQuotes = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                let next = text.index(after: index)
                if insideQuotes, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = text.index(after: next)
                    continue
                }
                insideQuotes.toggle()
            } else if character == ",", !insideQuotes {
                record.append(field)
                field = ""
            } else if (character == "\n" || character == "\r"), !insideQuotes {
                if character == "\r" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\n" {
                        index = next
                    }
                }
                record.append(field)
                field = ""
                records.append(record)
                record = []
            } else {
                field.append(character)
            }
            index = text.index(after: index)
        }

        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }
        return records
    }
}

enum CSVParserError: LocalizedError {
    case invalidEncoding

    var errorDescription: String? {
        "A generated CSV file is not valid UTF-8."
    }
}
