import Foundation
import CalendarSyncCore

public enum CalendarProviderError: Error, LocalizedError, Sendable {
    case wrongSide
    case targetChanged
    case identityCollision

    public var errorDescription: String? {
        switch self {
        case .wrongSide: "동기화 대상이 일치하지 않습니다"
        case .targetChanged: "일정이 확인하는 동안 변경됐습니다"
        case .identityCollision: "동기화 일정 ID가 이미 사용 중입니다"
        }
    }
}

public actor DaouCalendarProvider: CalendarProvider {
    public nonisolated let side: CalendarSide = .daou
    private let client: DaouCalDAVClient
    private let calendarURL: URL

    public init(client: DaouCalDAVClient, calendarURL: URL) {
        self.client = client
        self.calendarURL = calendarURL
    }

    public func fetchChanges(cursor: String?, pageToken: String?) async throws -> CalendarChangePage {
        let now = Date()
        let windowStart = now.addingTimeInterval(-30 * 86_400)
        let windowEnd = now.addingTimeInterval(365 * 86_400)
        let resources = try await client.listEvents(in: calendarURL, from: windowStart, until: windowEnd)
        let events = try resources.map { resource in
            CalendarChange.upsert(try ICalendarCodec.decode(resource.iCalendarData,
                id: resource.url.absoluteString, etag: resource.etag))
        }
        return CalendarChangePage(changes: events, isFullSnapshot: true)
    }

    public func observe(eventID: String) async throws -> CalendarObservation {
        guard let url = URL(string: eventID) else { return .unavailable(.unknown) }
        do {
            let resource = try await client.event(at: url)
            return .present(try ICalendarCodec.decode(resource.iCalendarData,
                id: resource.url.absoluteString, etag: resource.etag))
        } catch CalendarHTTPError.httpStatus(404, _) {
            return .confirmedDeleted
        }
    }

    public func apply(_ operation: SyncOperation) async throws -> CalendarWriteReceipt {
        switch operation {
        case let .create(mappingID, target, _, content):
            guard target == .daou else { throw CalendarProviderError.wrongSide }
            let name = SyncIdentity.remoteID(for: mappingID)
            let targetURL = calendarURL.appendingPathComponent(name + ".ics")
            let data = try ICalendarCodec.create(content, mappingID: mappingID)
            do {
                _ = try await client.createEvent(data, in: calendarURL, resourceName: name)
            } catch {
                // A lost PUT reply is resolved by reading the predetermined resource.
                if let existing = try? await client.event(at: targetURL),
                   let decoded = try? ICalendarCodec.decode(existing.iCalendarData,
                       id: existing.url.absoluteString, etag: existing.etag),
                   decoded.syncMarker == mappingID {
                    return CalendarWriteReceipt(eventID: decoded.id, version: decoded.version)
                }
                throw error
            }
            let saved = try await client.event(at: targetURL)
            let decoded = try ICalendarCodec.decode(saved.iCalendarData,
                id: saved.url.absoluteString, etag: saved.etag)
            guard decoded.syncMarker == mappingID else { throw CalendarProviderError.identityCollision }
            return CalendarWriteReceipt(eventID: decoded.id, version: decoded.version)

        case let .update(_, target, eventID, expectedVersion, content):
            guard target == .daou, let url = URL(string: eventID) else { throw CalendarProviderError.wrongSide }
            let original = try await client.event(at: url)
            guard original.etag == expectedVersion else { throw CalendarProviderError.targetChanged }
            let decoded = try ICalendarCodec.decode(original.iCalendarData, id: eventID, etag: original.etag)
            guard decoded.exclusion == nil else { throw CalendarCodecError.unsupportedEvent }
            _ = try await client.updateEvent(try ICalendarCodec.update(original.iCalendarData, with: content),
                                             at: url, etag: expectedVersion)
            let updated = try await client.event(at: url)
            return CalendarWriteReceipt(eventID: eventID, version: updated.etag)

        case let .delete(_, target, eventID, expectedVersion):
            guard target == .daou, let url = URL(string: eventID) else { throw CalendarProviderError.wrongSide }
            try await client.deleteEvent(at: url, etag: expectedVersion)
            return CalendarWriteReceipt(eventID: eventID, version: nil)
        }
    }
}

public actor GoogleCalendarProvider: CalendarProvider {
    public nonisolated let side: CalendarSide = .google
    private let client: GoogleCalendarClient
    private let calendarID: String

    public init(client: GoogleCalendarClient, calendarID: String) {
        self.client = client
        self.calendarID = calendarID
    }

    public func fetchChanges(cursor: String?, pageToken: String?) async throws -> CalendarChangePage {
        let page = try await client.listEvents(calendarID: calendarID, syncToken: cursor)
        let changes = try page.events.map { resource -> CalendarChange in
            if resource.status == "cancelled" { return .deleted(id: resource.id) }
            return .upsert(try GoogleEventCodec.decode(resource))
        }
        return CalendarChangePage(changes: changes, nextCursor: page.nextSyncToken)
    }

    public func observe(eventID: String) async throws -> CalendarObservation {
        do {
            let resource = try await client.event(calendarID: calendarID, eventID: eventID)
            if resource.status == "cancelled" { return .confirmedDeleted }
            return .present(try GoogleEventCodec.decode(resource))
        } catch CalendarHTTPError.httpStatus(404, _) {
            let calendars = try await client.listCalendars()
            guard calendars.contains(where: { $0.id == calendarID }) else {
                return .unavailable(.permissionDenied)
            }
            return .confirmedDeleted
        }
    }

    public func apply(_ operation: SyncOperation) async throws -> CalendarWriteReceipt {
        switch operation {
        case let .create(mappingID, target, _, content):
            guard target == .google else { throw CalendarProviderError.wrongSide }
            let eventID = SyncIdentity.remoteID(for: mappingID)
            let data = try GoogleEventCodec.writeJSON(content, mappingID: mappingID, id: eventID)
            do {
                let saved = try await client.createEvent(calendarID: calendarID, json: data)
                return CalendarWriteReceipt(eventID: saved.id, version: saved.etag)
            } catch {
                // A retry must inspect the stable ID before attempting another POST.
                if let existing = try? await client.event(calendarID: calendarID, eventID: eventID),
                   let decoded = try? GoogleEventCodec.decode(existing),
                   decoded.syncMarker == mappingID {
                    return CalendarWriteReceipt(eventID: existing.id, version: existing.etag)
                }
                throw error
            }

        case let .update(_, target, eventID, expectedVersion, content):
            guard target == .google else { throw CalendarProviderError.wrongSide }
            let original = try await client.event(calendarID: calendarID, eventID: eventID)
            guard original.etag == expectedVersion else { throw CalendarProviderError.targetChanged }
            let decoded = try GoogleEventCodec.decode(original)
            guard decoded.exclusion == nil else { throw CalendarCodecError.unsupportedEvent }
            let patch = try GoogleEventCodec.writeJSON(content, mappingID: nil)
            let updated = try await client.updateEvent(calendarID: calendarID, eventID: eventID,
                                                       etag: expectedVersion, patchJSON: patch)
            return CalendarWriteReceipt(eventID: updated.id, version: updated.etag)

        case let .delete(_, target, eventID, expectedVersion):
            guard target == .google else { throw CalendarProviderError.wrongSide }
            try await client.deleteEvent(calendarID: calendarID, eventID: eventID, etag: expectedVersion)
            return CalendarWriteReceipt(eventID: eventID, version: nil)
        }
    }
}
