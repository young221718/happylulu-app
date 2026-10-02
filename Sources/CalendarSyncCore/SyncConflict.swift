import Foundation

public enum SyncBaseline: Codable, Equatable, Sendable {
    case content(CalendarEventContent)
    case deleted
}

/// The two remote IDs must refer to the same event only when a verified marker or
/// explicit user choice established that pairing. Matching title/time is insufficient.
public struct CalendarMapping: Codable, Equatable, Sendable {
    public var id: String
    public var daouEventID: String?
    public var googleEventID: String?
    public var baseline: SyncBaseline?

    public init(id: String, daouEventID: String?, googleEventID: String?, baseline: SyncBaseline?) {
        self.id = id
        self.daouEventID = daouEventID
        self.googleEventID = googleEventID
        self.baseline = baseline
    }

    public func eventID(on side: CalendarSide) -> String? {
        side == .daou ? daouEventID : googleEventID
    }
}

public enum SyncConflictReason: String, Codable, Sendable {
    case simultaneousEdits
    case editVersusDeletion
    case initialPairAmbiguous
}

public struct SyncConflict: Codable, Equatable, Sendable {
    public let mappingID: String
    public let reason: SyncConflictReason
    public let baseline: SyncBaseline?
    public let daou: CalendarObservation
    public let google: CalendarObservation

    public init(
        mappingID: String,
        reason: SyncConflictReason,
        baseline: SyncBaseline?,
        daou: CalendarObservation,
        google: CalendarObservation
    ) {
        self.mappingID = mappingID
        self.reason = reason
        self.baseline = baseline
        self.daou = daou
        self.google = google
    }
}

public enum SyncHoldReason: Codable, Equatable, Sendable {
    case incompleteObservation
    case incompleteMapping
    case unverifiedAbsence
    case identityMismatch
    case excludedEvent(CalendarEventExclusion)
    case missingVersion
    case tombstoneResurrection
}
