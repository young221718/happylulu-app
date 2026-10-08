import Foundation

public enum CalendarSide: String, Codable, CaseIterable, Sendable {
    case daou
    case google

    public var opposite: CalendarSide { self == .daou ? .google : .daou }
}

/// All-day end dates are exclusive, as they are in iCalendar and Google Calendar.
public enum CalendarEventTime: Codable, Equatable, Sendable {
    case allDay(startDate: String, exclusiveEndDate: String)
    case timed(start: Date, end: Date, timeZoneID: String)
}

public enum CalendarEventAlarm: Codable, Equatable, Sendable {
    case relative(TimeInterval)
    case absolute(Date)
}

/// Content of an ordinary personal copy; meeting participants and recurrence
/// rules remain on the original event rather than being recreated.
public struct CalendarEventContent: Codable, Equatable, Sendable {
    public var title: String
    public var time: CalendarEventTime
    public var notes: String?
    public var location: String?
    public var alarms: [CalendarEventAlarm]?

    public init(title: String, time: CalendarEventTime, notes: String? = nil, location: String? = nil,
                alarms: [CalendarEventAlarm]? = nil) {
        self.title = title
        self.time = time
        self.notes = notes
        self.location = location
        self.alarms = alarms
    }
}

public enum CalendarEventExclusion: Codable, Equatable, Sendable {
    case recurring
    case invitation
    case approvalManaged
    case unsupportedProperties
    case other(String)
}

public struct CalendarEvent: Codable, Equatable, Sendable {
    public var id: String
    public var version: String
    public var content: CalendarEventContent
    public var exclusion: CalendarEventExclusion?
    public var syncMarker: String?
    /// Optional for persisted observations created before invitation support.
    public var protectedSource: Bool?

    public init(
        id: String,
        version: String,
        content: CalendarEventContent,
        exclusion: CalendarEventExclusion? = nil,
        syncMarker: String? = nil,
        protectedSource: Bool? = nil
    ) {
        self.id = id
        self.version = version
        self.content = content
        self.exclusion = exclusion
        self.syncMarker = syncMarker
        self.protectedSource = protectedSource
    }
}

/// A missing item is not a deletion. Only a provider-confirmed tombstone may delete its peer.
public enum CalendarObservationIssue: String, Codable, Sendable {
    case authenticationRequired
    case permissionDenied
    case networkFailure
    case incompleteListing
    case outsideWindow
    case parseFailure
    case unknown
}

public enum CalendarObservation: Codable, Equatable, Sendable {
    case present(CalendarEvent)
    case absent
    case confirmedDeleted
    case unavailable(CalendarObservationIssue)
}
