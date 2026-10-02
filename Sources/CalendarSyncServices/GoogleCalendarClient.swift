import Foundation

public protocol GoogleAccessTokenProvider: Sendable {
    func accessToken() async throws -> String
}

public enum GoogleCalendarError: Error, LocalizedError, Sendable {
    case malformedResponse
    case invalidCalendarID

    public var errorDescription: String? {
        switch self {
        case .malformedResponse: "Google 캘린더 응답을 읽을 수 없습니다"
        case .invalidCalendarID: "Google 캘린더 선택을 확인해 주세요"
        }
    }
}

public struct GoogleCalendarSummary: Sendable, Identifiable, Decodable {
    public let id: String
    public let summary: String
    public let accessRole: String?
    public let primary: Bool?
}

public struct GoogleEventResource: Sendable {
    public let id: String
    public let etag: String?
    public let status: String?
    public let json: Data
}

public struct GoogleEventPage: Sendable {
    public let events: [GoogleEventResource]
    public let nextSyncToken: String?
}

private struct GoogleCalendarListEnvelope: Decodable {
    let items: [GoogleCalendarSummary]?
    let nextPageToken: String?
}

private struct GoogleEventEnvelope: Decodable {
    struct Event: Decodable {
        let id: String
        let etag: String?
        let status: String?
    }
    let items: [Event]?
    let nextPageToken: String?
    let nextSyncToken: String?
}

/// Google Calendar v3 access scoped to the calendar IDs chosen in the app.
public actor GoogleCalendarClient {
    private let tokenProvider: any GoogleAccessTokenProvider
    private let http: CalendarHTTPClient
    private let baseURL = URL(string: "https://www.googleapis.com/calendar/v3")!

    public init(tokenProvider: any GoogleAccessTokenProvider, http: CalendarHTTPClient = CalendarHTTPClient()) {
        self.tokenProvider = tokenProvider
        self.http = http
    }

    private func url(_ parts: [String], query: [URLQueryItem] = []) throws -> URL {
        var result = baseURL
        for part in parts {
            guard !part.isEmpty else { throw GoogleCalendarError.invalidCalendarID }
            result.appendPathComponent(part)
        }
        var components = URLComponents(url: result, resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw GoogleCalendarError.invalidCalendarID }
        return url
    }

    private func request(
        _ url: URL, method: String = "GET", etag: String? = nil, body: Data? = nil
    ) async throws -> CalendarHTTPResult {
        var headers = ["Authorization": "Bearer " + (try await tokenProvider.accessToken())]
        if body != nil { headers["Content-Type"] = "application/json; charset=utf-8" }
        if let etag { headers["If-Match"] = etag }
        return try await http.send(url, method: method, headers: headers, body: body)
    }

    public func listCalendars() async throws -> [GoogleCalendarSummary] {
        var calendars: [GoogleCalendarSummary] = []
        var pageToken: String?
        repeat {
            var query = [URLQueryItem(name: "maxResults", value: "250")]
            if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let result = try await request(url(["users", "me", "calendarList"], query: query))
            let envelope = try JSONDecoder().decode(GoogleCalendarListEnvelope.self, from: result.data)
            calendars += envelope.items ?? []
            pageToken = envelope.nextPageToken
        } while pageToken != nil
        return calendars
    }

    /// Fetches every page. The caller must save nextSyncToken only after all observations are committed.
    public func listEvents(calendarID: String, syncToken: String? = nil) async throws -> GoogleEventPage {
        var all: [GoogleEventResource] = []
        var pageToken: String?
        var nextSyncToken: String?
        repeat {
            var query = [
                URLQueryItem(name: "maxResults", value: "2500"),
                URLQueryItem(name: "showDeleted", value: "true"),
                URLQueryItem(name: "singleEvents", value: "false")
            ]
            if let syncToken { query.append(URLQueryItem(name: "syncToken", value: syncToken)) }
            if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let result = try await request(url(["calendars", calendarID, "events"], query: query))
            guard let object = try JSONSerialization.jsonObject(with: result.data) as? [String: Any] else {
                throw GoogleCalendarError.malformedResponse
            }
            let items = object["items"] as? [[String: Any]] ?? []
            for item in items {
                guard let id = item["id"] as? String else { throw GoogleCalendarError.malformedResponse }
                let data = try JSONSerialization.data(withJSONObject: item, options: [.sortedKeys])
                all.append(GoogleEventResource(
                    id: id, etag: item["etag"] as? String,
                    status: item["status"] as? String, json: data
                ))
            }
            pageToken = object["nextPageToken"] as? String
            nextSyncToken = object["nextSyncToken"] as? String ?? nextSyncToken
        } while pageToken != nil
        guard nextSyncToken != nil else { throw GoogleCalendarError.malformedResponse }
        return GoogleEventPage(events: all, nextSyncToken: nextSyncToken)
    }

    public func event(calendarID: String, eventID: String) async throws -> GoogleEventResource {
        let result = try await request(url(["calendars", calendarID, "events", eventID]))
        guard let item = try JSONSerialization.jsonObject(with: result.data) as? [String: Any],
              let id = item["id"] as? String else { throw GoogleCalendarError.malformedResponse }
        return GoogleEventResource(id: id, etag: item["etag"] as? String,
                                   status: item["status"] as? String, json: result.data)
    }

    public func createEvent(calendarID: String, json: Data) async throws -> GoogleEventResource {
        let result = try await request(url(["calendars", calendarID, "events"]), method: "POST", body: json)
        guard let item = try JSONSerialization.jsonObject(with: result.data) as? [String: Any],
              let id = item["id"] as? String else { throw GoogleCalendarError.malformedResponse }
        return GoogleEventResource(id: id, etag: item["etag"] as? String,
                                   status: item["status"] as? String, json: result.data)
    }

    public func updateEvent(calendarID: String, eventID: String, etag: String, patchJSON: Data) async throws -> GoogleEventResource {
        let result = try await request(url(["calendars", calendarID, "events", eventID]),
                                       method: "PATCH", etag: etag, body: patchJSON)
        guard let item = try JSONSerialization.jsonObject(with: result.data) as? [String: Any],
              let id = item["id"] as? String else { throw GoogleCalendarError.malformedResponse }
        return GoogleEventResource(id: id, etag: item["etag"] as? String,
                                   status: item["status"] as? String, json: result.data)
    }

    public func deleteEvent(calendarID: String, eventID: String, etag: String) async throws {
        _ = try await request(url(["calendars", calendarID, "events", eventID]), method: "DELETE", etag: etag)
    }
}
