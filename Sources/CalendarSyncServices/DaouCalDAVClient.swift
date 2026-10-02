import Foundation

public enum CalDAVError: Error, LocalizedError, Sendable {
    case invalidAddress
    case missingCredential
    case malformedResponse
    case principalNotFound
    case calendarHomeNotFound
    case calendarOutsideAccount

    public var errorDescription: String? {
        switch self {
        case .invalidAddress: "다우오피스 HTTPS 주소를 확인해 주세요"
        case .missingCredential: "다우오피스 계정 연결이 필요합니다"
        case .malformedResponse: "다우오피스 CalDAV 응답을 읽을 수 없습니다"
        case .principalNotFound: "CalDAV 계정을 찾을 수 없습니다"
        case .calendarHomeNotFound: "CalDAV 캘린더 목록을 찾을 수 없습니다"
        case .calendarOutsideAccount: "선택한 캘린더 주소가 계정 범위를 벗어납니다"
        }
    }
}

public struct CalDAVCalendar: Sendable, Identifiable {
    public let url: URL
    public let name: String
    public var id: String { url.absoluteString }
}

public struct CalDAVResource: Sendable {
    public let url: URL
    public let etag: String?
    public let iCalendarData: Data
}

private struct CalDAVXMLResponse {
    var href: String?
    var displayName: String?
    var etag: String?
    var calendarData: String?
    var isCalendar = false
    var currentUserPrincipal: String?
    var calendarHomeSet: String?
}

private final class CalDAVXMLReader: NSObject, XMLParserDelegate {
    private var stack: [String] = []
    private var text = ""
    private var current: CalDAVXMLResponse?
    private(set) var responses: [CalDAVXMLResponse] = []

    static func read(_ data: Data) throws -> [CalDAVXMLResponse] {
        let reader = CalDAVXMLReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else { throw CalDAVError.malformedResponse }
        return reader.responses
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        stack.append(name)
        text = ""
        if name == "response" { current = CalDAVXMLResponse() }
        if name == "calendar", stack.contains("resourcetype") { current?.isCalendar = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "href", let parent = stack.dropLast().last {
            switch parent {
            case "response": current?.href = value
            case "current-user-principal": current?.currentUserPrincipal = value
            case "calendar-home-set": current?.calendarHomeSet = value
            default: break
            }
        } else if name == "displayname" { current?.displayName = value }
        else if name == "getetag" { current?.etag = value }
        else if name == "calendar-data" { current?.calendarData = value }
        else if name == "response", let current {
            responses.append(current)
            self.current = nil
        }
        if !stack.isEmpty { stack.removeLast() }
        text = ""
    }
}

/// Direct CalDAV access. Account discovery is performed before a calendar can be selected.
public actor DaouCalDAVClient {
    private let baseURL: URL
    private let email: String
    private let credentialStore: CredentialStore
    private let http: CalendarHTTPClient

    public init(baseURL: URL, email: String, credentialStore: CredentialStore = CredentialStore(), http: CalendarHTTPClient = CalendarHTTPClient()) throws {
        guard baseURL.scheme == "https", baseURL.host != nil else { throw CalDAVError.invalidAddress }
        self.baseURL = baseURL
        self.email = email
        self.credentialStore = credentialStore
        self.http = http
    }

    private func authorization() throws -> String {
        guard let password = try credentialStore.load(for: "daou.password"), !password.isEmpty else {
            throw CalDAVError.missingCredential
        }
        return "Basic " + Data("\(email):\(password)".utf8).base64EncodedString()
    }

    private func sameOrigin(_ url: URL) -> Bool {
        url.scheme == "https" && url.host?.lowercased() == baseURL.host?.lowercased()
            && (url.port ?? 443) == (baseURL.port ?? 443)
    }

    private func resolve(_ href: String, against url: URL) throws -> URL {
        guard let result = URL(string: href, relativeTo: url)?.absoluteURL, sameOrigin(result) else {
            throw CalDAVError.calendarOutsideAccount
        }
        return result
    }

    private func propfind(_ url: URL, depth: Int, properties: String) async throws -> [CalDAVXMLResponse] {
        guard sameOrigin(url) else { throw CalDAVError.calendarOutsideAccount }
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop>\(properties)</d:prop></d:propfind>
        """
        let result = try await http.send(url, method: "PROPFIND", headers: [
            "Authorization": try authorization(), "Depth": String(depth),
            "Content-Type": "application/xml; charset=utf-8"
        ], body: Data(body.utf8))
        return try CalDAVXMLReader.read(result.data)
    }

    public func discoverCalendars() async throws -> [CalDAVCalendar] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/.well-known/caldav"
        components.query = nil
        guard let discoveryURL = components.url else { throw CalDAVError.invalidAddress }
        let principalResults = try await propfind(discoveryURL, depth: 0, properties: "<d:current-user-principal/>")
        guard let principalHref = principalResults.compactMap(\.currentUserPrincipal).first,
              let principalURL = try? resolve(principalHref, against: discoveryURL) else {
            throw CalDAVError.principalNotFound
        }
        let homeResults = try await propfind(principalURL, depth: 0, properties: "<c:calendar-home-set/>")
        guard let homeHref = homeResults.compactMap(\.calendarHomeSet).first,
              let homeURL = try? resolve(homeHref, against: principalURL) else {
            throw CalDAVError.calendarHomeNotFound
        }
        let calendars = try await propfind(homeURL, depth: 1, properties: "<d:displayname/><d:resourcetype/>")
        return try calendars.filter(\.isCalendar).compactMap { response in
            guard let href = response.href else { return nil }
            let url = try resolve(href, against: homeURL)
            return CalDAVCalendar(url: url, name: response.displayName ?? url.lastPathComponent)
        }
    }

    public func listEvents(in calendarURL: URL, from start: Date, until end: Date) async throws -> [CalDAVResource] {
        guard sameOrigin(calendarURL) else { throw CalDAVError.calendarOutsideAccount }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:prop><d:getetag/><c:calendar-data/></d:prop>
          <c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT"><c:time-range start="\(formatter.string(from: start))" end="\(formatter.string(from: end))"/></c:comp-filter></c:comp-filter></c:filter>
        </c:calendar-query>
        """
        let result = try await http.send(calendarURL, method: "REPORT", headers: [
            "Authorization": try authorization(), "Depth": "1",
            "Content-Type": "application/xml; charset=utf-8"
        ], body: Data(body.utf8))
        return try CalDAVXMLReader.read(result.data).compactMap { response in
            guard let href = response.href, let calendarData = response.calendarData else { return nil }
            let url = try resolve(href, against: calendarURL)
            return CalDAVResource(url: url, etag: response.etag, iCalendarData: Data(calendarData.utf8))
        }
    }

    public func event(at url: URL) async throws -> CalDAVResource {
        guard sameOrigin(url) else { throw CalDAVError.calendarOutsideAccount }
        let result = try await http.send(url, headers: ["Authorization": try authorization()])
        return CalDAVResource(url: url, etag: result.etag, iCalendarData: result.data)
    }

    public func createEvent(_ data: Data, in calendarURL: URL, resourceName: String) async throws -> CalDAVResource {
        guard sameOrigin(calendarURL), resourceName.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            throw CalDAVError.calendarOutsideAccount
        }
        let url = calendarURL.appendingPathComponent(resourceName + ".ics")
        let result = try await http.send(url, method: "PUT", headers: [
            "Authorization": try authorization(), "Content-Type": "text/calendar; charset=utf-8",
            "If-None-Match": "*"
        ], body: data)
        return CalDAVResource(url: url, etag: result.etag, iCalendarData: data)
    }

    public func updateEvent(_ data: Data, at url: URL, etag: String) async throws -> CalDAVResource {
        guard sameOrigin(url), !etag.isEmpty else { throw CalDAVError.calendarOutsideAccount }
        let result = try await http.send(url, method: "PUT", headers: [
            "Authorization": try authorization(), "Content-Type": "text/calendar; charset=utf-8",
            "If-Match": etag
        ], body: data)
        return CalDAVResource(url: url, etag: result.etag, iCalendarData: data)
    }

    public func deleteEvent(at url: URL, etag: String) async throws {
        guard sameOrigin(url), !etag.isEmpty else { throw CalDAVError.calendarOutsideAccount }
        _ = try await http.send(url, method: "DELETE", headers: [
            "Authorization": try authorization(), "If-Match": etag
        ])
    }
}
