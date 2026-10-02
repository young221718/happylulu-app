import Foundation

public enum CalendarChange: Codable, Equatable, Sendable {
    case upsert(CalendarEvent)
    case deleted(id: String)
}

/// nextCursor is usable only after all pages have been received and persisted.
public struct CalendarChangePage: Codable, Equatable, Sendable {
    public var changes: [CalendarChange]
    public var nextPageToken: String?
    public var nextCursor: String?
    public var isFullSnapshot: Bool

    public init(
        changes: [CalendarChange],
        nextPageToken: String? = nil,
        nextCursor: String? = nil,
        isFullSnapshot: Bool = false
    ) {
        self.changes = changes
        self.nextPageToken = nextPageToken
        self.nextCursor = nextCursor
        self.isFullSnapshot = isFullSnapshot
    }
}

/// Each operation must be journaled before apply. For creates, the adapter
/// derives a stable remote ID from mappingID and checks it after a lost reply.
public enum SyncOperation: Codable, Equatable, Sendable {
    case create(mappingID: String, target: CalendarSide, sourceEventID: String, content: CalendarEventContent)
    case update(mappingID: String, target: CalendarSide, targetEventID: String, expectedVersion: String, content: CalendarEventContent)
    case delete(mappingID: String, target: CalendarSide, targetEventID: String, expectedVersion: String)
}

public struct CalendarWriteReceipt: Codable, Equatable, Sendable {
    public let eventID: String
    public let version: String?

    public init(eventID: String, version: String?) {
        self.eventID = eventID
        self.version = version
    }
}

/// Provider implementations must fail closed on pagination, auth, parsing,
/// and conditional-write errors. In particular, an incomplete listing must
/// never be emitted as confirmed deletions.
public protocol CalendarProvider: Sendable {
    var side: CalendarSide { get }
    func fetchChanges(cursor: String?, pageToken: String?) async throws -> CalendarChangePage
    func observe(eventID: String) async throws -> CalendarObservation
    func apply(_ operation: SyncOperation) async throws -> CalendarWriteReceipt
    func recover(_ operation: SyncOperation) async throws -> CalendarWriteReceipt
}

public extension CalendarProvider {
    /// Remote adapters with deterministic IDs can safely replay a journaled write.
    func recover(_ operation: SyncOperation) async throws -> CalendarWriteReceipt {
        try await apply(operation)
    }
}
