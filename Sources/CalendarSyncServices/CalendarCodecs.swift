import Foundation
import CalendarSyncCore
import CryptoKit

public enum CalendarCodecError: Error, LocalizedError, Sendable {
    case unsupportedEvent
    case malformedEvent
    case missingVersion

    public var errorDescription: String? {
        switch self {
        case .unsupportedEvent: "이 일정 유형은 자동 동기화 대상이 아닙니다"
        case .malformedEvent: "일정 내용을 읽을 수 없습니다"
        case .missingVersion: "서버의 일정 버전을 확인할 수 없습니다"
        }
    }
}

enum SyncIdentity {
    static func remoteID(for mappingID: String) -> String {
        let digest = SHA256.hash(data: Data(mappingID.utf8))
        return "hl" + digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum ICalendarCodec {
    private static func unfold(_ data: Data) throws -> [String] {
        guard let text = String(data: data, encoding: .utf8) else { throw CalendarCodecError.malformedEvent }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.first == " " || line.first == "\t" {
                guard !lines.isEmpty else { throw CalendarCodecError.malformedEvent }
                lines[lines.count - 1] += line.dropFirst()
            } else {
                lines.append(String(line))
            }
        }
        return lines
    }

    private static func property(_ line: String) -> (name: String, parameters: String, value: String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let left = String(line[..<colon])
        let name = String(left.split(separator: ";", maxSplits: 1).first ?? "").uppercased()
        let parameters = String(left.dropFirst(name.count))
        return (name, parameters, String(line[line.index(after: colon)...]))
    }

    private static func unescape(_ text: String) -> String {
        var result = ""
        var escaped = false
        for char in text {
            if escaped {
                switch char {
                case "n", "N": result.append("\n")
                case ",", ";", "\\": result.append(char)
                default: result.append(char)
                }
                escaped = false
            } else if char == "\\" { escaped = true }
            else { result.append(char) }
        }
        if escaped { result.append("\\") }
        return result
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
    }

    private static func parseDate(_ value: String, parameters: String) throws -> (date: Date, timeZoneID: String)? {
        if parameters.uppercased().contains("VALUE=DATE") || (value.count == 8 && !value.contains("T")) { return nil }
        let tzid = parameters.components(separatedBy: ";").first(where: { $0.uppercased().hasPrefix("TZID=") })
            .map { String($0.dropFirst(5)) }
        let timeZone = tzid.flatMap(TimeZone.init(identifier:)) ?? TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = value.hasSuffix("Z") ? TimeZone(secondsFromGMT: 0)! : timeZone
        formatter.dateFormat = value.hasSuffix("Z") ? "yyyyMMdd'T'HHmmss'Z'" : "yyyyMMdd'T'HHmmss"
        guard let date = formatter.date(from: value) else { throw CalendarCodecError.malformedEvent }
        return (date, tzid ?? (value.hasSuffix("Z") ? "UTC" : timeZone.identifier))
    }

    static func decode(_ data: Data, id: String, etag: String?) throws -> CalendarEvent {
        let lines = try unfold(data)
        guard lines.contains("BEGIN:VCALENDAR"), lines.contains("END:VCALENDAR") else {
            throw CalendarCodecError.malformedEvent
        }
        var eventLines: [String] = []
        var inEvent = false
        var eventCount = 0
        for line in lines {
            if line == "BEGIN:VEVENT" { inEvent = true; eventCount += 1 }
            if inEvent { eventLines.append(line) }
            if line == "END:VEVENT" { inEvent = false }
        }
        guard eventCount == 1 else { throw CalendarCodecError.unsupportedEvent }
        var values: [String: (parameters: String, value: String)] = [:]
        var exclusion: CalendarEventExclusion?
        for line in eventLines {
            guard let item = property(line) else { continue }
            if ["RRULE", "RDATE", "EXDATE", "RECURRENCE-ID"].contains(item.name) { exclusion = .recurring }
            if ["ORGANIZER", "ATTENDEE"].contains(item.name) { exclusion = .invitation }
            if ["BEGIN", "END"].contains(item.name), item.value == "VALARM" { exclusion = .unsupportedProperties }
            if values[item.name] != nil, ["UID", "DTSTART", "DTEND"].contains(item.name) {
                exclusion = .unsupportedProperties
            }
            values[item.name] = (item.parameters, item.value)
        }
        guard let title = values["SUMMARY"]?.value,
              let start = values["DTSTART"], let end = values["DTEND"],
              values["UID"]?.value != nil else { throw CalendarCodecError.malformedEvent }
        if unescape(title).contains("/") { exclusion = .unsupportedProperties }
        let time: CalendarEventTime
        if start.parameters.uppercased().contains("VALUE=DATE") || (start.value.count == 8 && !start.value.contains("T")) {
            guard start.value.count == 8, end.value.count == 8 else { throw CalendarCodecError.malformedEvent }
            time = .allDay(startDate: "\(start.value.prefix(4))-\(start.value.dropFirst(4).prefix(2))-\(start.value.suffix(2))",
                           exclusiveEndDate: "\(end.value.prefix(4))-\(end.value.dropFirst(4).prefix(2))-\(end.value.suffix(2))")
        } else {
            guard let parsedStart = try parseDate(start.value, parameters: start.parameters),
                  let parsedEnd = try parseDate(end.value, parameters: end.parameters) else {
                throw CalendarCodecError.malformedEvent
            }
            let rememberedZone = values["X-HAPPYLULU-TZID"]?.value
            let zoneID = rememberedZone.flatMap { TimeZone(identifier: $0) == nil ? nil : $0 }
                ?? parsedStart.timeZoneID
            time = .timed(start: parsedStart.date, end: parsedEnd.date, timeZoneID: zoneID)
        }
        return CalendarEvent(
            id: id, version: etag ?? "",
            content: CalendarEventContent(title: unescape(title), time: time,
                notes: values["DESCRIPTION"].map { unescape($0.value) },
                location: values["LOCATION"].map { unescape($0.value) }),
            exclusion: exclusion,
            syncMarker: values["X-HAPPYLULU-ID"]?.value
        )
    }

    private static func supportedLines(_ content: CalendarEventContent) throws -> [String] {
        // The legacy REST adapters do not yet encode alarm trigger semantics.
        // Reject rather than silently dropping alarms supported by EventKit.
        guard content.alarms?.isEmpty != false else { throw CalendarCodecError.unsupportedEvent }
        guard !content.title.contains("/") else { throw CalendarCodecError.unsupportedEvent }
        var lines = ["SUMMARY:\(escape(content.title))"]
        switch content.time {
        case let .allDay(start, end):
            lines += ["DTSTART;VALUE=DATE:\(start.replacingOccurrences(of: "-", with: ""))",
                      "DTEND;VALUE=DATE:\(end.replacingOccurrences(of: "-", with: ""))"]
        case let .timed(start, end, timeZoneID):
            guard TimeZone(identifier: timeZoneID) != nil else { throw CalendarCodecError.malformedEvent }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            lines += ["DTSTART:\(formatter.string(from: start))",
                      "DTEND:\(formatter.string(from: end))",
                      "X-HAPPYLULU-TZID:\(timeZoneID)"]
        }
        if let notes = content.notes { lines.append("DESCRIPTION:\(escape(notes))") }
        if let location = content.location { lines.append("LOCATION:\(escape(location))") }
        return lines
    }

    private static func fold(_ lines: [String]) -> Data {
        var output = ""
        for line in lines {
            var length = 0
            for scalar in line.unicodeScalars {
                let size = scalar.utf8.count
                if length + size > 75 {
                    output += "\r\n "
                    length = 1
                }
                output.unicodeScalars.append(scalar)
                length += size
            }
            output += "\r\n"
        }
        return Data(output.utf8)
    }

    static func create(_ content: CalendarEventContent, mappingID: String) throws -> Data {
        let timestamp = DateFormatter()
        timestamp.locale = Locale(identifier: "en_US_POSIX")
        timestamp.timeZone = TimeZone(secondsFromGMT: 0)
        timestamp.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//HappyLulu//Calendar Sync//KO",
                     "BEGIN:VEVENT", "UID:\(SyncIdentity.remoteID(for: mappingID))@happylulu.local",
                     "DTSTAMP:\(timestamp.string(from: Date()))", "X-HAPPYLULU-ID:\(mappingID)"]
            + (try supportedLines(content)) + ["END:VEVENT", "END:VCALENDAR"]
        return fold(lines)
    }

    /// Replaces only managed VEVENT properties. Unknown fields remain unchanged.
    static func update(_ original: Data, with content: CalendarEventContent) throws -> Data {
        let lines = try unfold(original)
        guard lines.filter({ $0 == "BEGIN:VEVENT" }).count == 1 else { throw CalendarCodecError.unsupportedEvent }
        var output: [String] = []
        var inEvent = false
        for line in lines where !line.isEmpty {
            if line == "BEGIN:VEVENT" { inEvent = true }
            if inEvent, let item = property(line),
               ["SUMMARY", "DESCRIPTION", "LOCATION", "DTSTART", "DTEND", "X-HAPPYLULU-TZID"].contains(item.name) { continue }
            if line == "END:VEVENT" {
                output += try supportedLines(content)
                inEvent = false
            }
            output.append(line)
        }
        return fold(output)
    }
}

enum GoogleEventCodec {
    private static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    static func decode(_ resource: GoogleEventResource) throws -> CalendarEvent {
        guard let object = try JSONSerialization.jsonObject(with: resource.json) as? [String: Any] else {
            throw CalendarCodecError.malformedEvent
        }
        var exclusion: CalendarEventExclusion?
        if object["recurrence"] != nil || object["recurringEventId"] != nil { exclusion = .recurring }
        if object["attendees"] != nil || (object["organizer"] as? [String: Any])?["self"] as? Bool == false {
            exclusion = .invitation
        }
        if let eventType = object["eventType"] as? String, eventType != "default" { exclusion = .approvalManaged }
        guard let title = object["summary"] as? String,
              let start = object["start"] as? [String: Any],
              let end = object["end"] as? [String: Any] else { throw CalendarCodecError.malformedEvent }
        // Daou Office does not accept a slash in calendar event titles. Mark it
        // before planning so a preview never promises a write that CalDAV rejects.
        if title.contains("/") { exclusion = .unsupportedProperties }
        let time: CalendarEventTime
        if let startDate = start["date"] as? String, let endDate = end["date"] as? String {
            time = .allDay(startDate: startDate, exclusiveEndDate: endDate)
        } else if let startText = start["dateTime"] as? String,
                  let endText = end["dateTime"] as? String,
                  let startDate = date(startText), let endDate = date(endText) {
            time = .timed(start: startDate, end: endDate, timeZoneID: (start["timeZone"] as? String) ?? "UTC")
        } else { throw CalendarCodecError.malformedEvent }
        let marker = ((object["extendedProperties"] as? [String: Any])?["private"] as? [String: Any])?["happyluluId"] as? String
        return CalendarEvent(id: resource.id, version: resource.etag ?? "",
            content: CalendarEventContent(title: title, time: time,
                notes: object["description"] as? String, location: object["location"] as? String),
            exclusion: exclusion, syncMarker: marker)
    }

    static func writeJSON(_ content: CalendarEventContent, mappingID: String?, id: String? = nil) throws -> Data {
        guard content.alarms?.isEmpty != false else { throw CalendarCodecError.unsupportedEvent }
        var object: [String: Any] = ["summary": content.title]
        switch content.time {
        case let .allDay(start, end):
            object["start"] = ["date": start]
            object["end"] = ["date": end]
        case let .timed(start, end, timeZoneID):
            guard let zone = TimeZone(identifier: timeZoneID) else { throw CalendarCodecError.malformedEvent }
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = zone
            formatter.formatOptions = [.withInternetDateTime]
            object["start"] = ["dateTime": formatter.string(from: start), "timeZone": timeZoneID]
            object["end"] = ["dateTime": formatter.string(from: end), "timeZone": timeZoneID]
        }
        object["description"] = content.notes ?? NSNull()
        object["location"] = content.location ?? NSNull()
        if let id { object["id"] = id }
        if let mappingID { object["extendedProperties"] = ["private": ["happyluluId": mappingID]] }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
