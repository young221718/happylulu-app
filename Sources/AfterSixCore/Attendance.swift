import Foundation

public struct WorkSettings: Codable, Equatable, Sendable {
    public var workMinutes: Int = 480
    public var breakMinutes: Int = 60
    public init() {}

    public var isValid: Bool {
        (60...960).contains(workMinutes) && (0...240).contains(breakMinutes)
    }
}

public enum ArrivalSource: String, Codable, Sendable {
    case unlock, manual
}

public struct Arrival: Codable, Equatable, Sendable {
    public let day: String
    public let time: Date
    public let source: ArrivalSource
    public let timeZoneID: String

    public init(day: String, time: Date, source: ArrivalSource, timeZoneID: String) {
        self.day = day
        self.time = time
        self.source = source
        self.timeZoneID = timeZoneID
    }
}

public struct AttendanceState: Codable, Equatable, Sendable {
    public var version = 1
    public var settings = WorkSettings()
    public var arrivals: [String: Arrival] = [:]
    // A cleared day stays suppressed until the next day or an explicit manual entry.
    public var suppressedDays: Set<String> = []
    public var lastUnlockAt: Date?
    public var didOfferLoginItem = false
    public init() {}
}

public enum AttendanceError: LocalizedError {
    case invalidTime, invalidSettings, invalidState
    public var errorDescription: String? {
        switch self {
        case .invalidTime: "오늘 날짜의 현재 시각 이전으로 입력해 주세요."
        case .invalidSettings: "근무는 1~16시간, 휴게는 0~4시간으로 설정해 주세요."
        case .invalidState: "기록 파일을 읽을 수 없습니다. 원본을 보존했습니다."
        }
    }
}

public enum Attendance {
    public static func clockLabel(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return String(format: "%02d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
    }

    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public static func today(in state: AttendanceState, now: Date, calendar: Calendar) -> Arrival? {
        state.arrivals[dayKey(now, calendar: calendar)]
    }

    @discardableResult
    public static func recordUnlock(in state: inout AttendanceState, at date: Date, calendar: Calendar) -> Bool {
        state.lastUnlockAt = date
        let day = dayKey(date, calendar: calendar)
        guard calendar.component(.hour, from: date) >= 6,
              state.arrivals[day] == nil,
              !state.suppressedDays.contains(day) else { return false }
        state.arrivals[day] = Arrival(day: day, time: date, source: .unlock, timeZoneID: calendar.timeZone.identifier)
        return true
    }

    public static func setManual(in state: inout AttendanceState, at date: Date, now: Date, calendar: Calendar) throws {
        guard date <= now, calendar.isDate(date, inSameDayAs: now) else { throw AttendanceError.invalidTime }
        let day = dayKey(now, calendar: calendar)
        state.arrivals[day] = Arrival(day: day, time: date, source: .manual, timeZoneID: calendar.timeZone.identifier)
        state.suppressedDays.remove(day)
    }

    public static func skipToday(in state: inout AttendanceState, now: Date, calendar: Calendar) {
        let day = dayKey(now, calendar: calendar)
        state.arrivals.removeValue(forKey: day)
        state.suppressedDays.insert(day)
    }

    public static func departure(for arrival: Arrival, settings: WorkSettings) -> Date {
        arrival.time.addingTimeInterval(TimeInterval(settings.workMinutes + settings.breakMinutes) * 60)
    }

    public static func remainingMinutes(until departure: Date, now: Date) -> Int {
        max(0, Int(ceil(departure.timeIntervalSince(now) / 60)))
    }
}

public struct StateStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public static var standard: StateStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return StateStore(url: base.appendingPathComponent("AfterSix/state.json"))
    }

    public func load() throws -> AttendanceState {
        guard FileManager.default.fileExists(atPath: url.path) else { return AttendanceState() }
        let state = try JSONDecoder().decode(AttendanceState.self, from: Data(contentsOf: url))
        guard state.version == 1, state.settings.isValid,
              state.arrivals.allSatisfy({ key, value in
                  key == value.day && value.time.timeIntervalSince1970.isFinite
                  && TimeZone(identifier: value.timeZoneID) != nil
              }) else { throw AttendanceError.invalidState }
        return state
    }

    public func save(_ state: AttendanceState) throws {
        guard state.version == 1, state.settings.isValid else { throw AttendanceError.invalidSettings }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
