import Foundation
import AfterSixCore

final class AttendanceTests {
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return value
    }
    func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: text + "+09:00")!
    }

    func testBeforeSixIsIgnoredAndExactSixAccepted() {
        var state = AttendanceState()
        expectFalse(Attendance.recordUnlock(in: &state, at: date("2026-09-28T05:59:59"), calendar: calendar))
        expectTrue(state.arrivals.isEmpty)
        expectTrue(Attendance.recordUnlock(in: &state, at: date("2026-09-28T06:00:00"), calendar: calendar))
        expectEqual(state.arrivals.count, 1)
    }

    func testLaterUnlockDoesNotReplaceFirstArrival() {
        var state = AttendanceState()
        let first = date("2026-09-28T08:47:12")
        Attendance.recordUnlock(in: &state, at: first, calendar: calendar)
        expectFalse(Attendance.recordUnlock(in: &state, at: date("2026-09-28T13:00:00"), calendar: calendar))
        expectEqual(state.arrivals["2026-09-28"]?.time, first)
        expectEqual(state.lastUnlockAt, date("2026-09-28T13:00:00"))
    }

    func testNewDayHasIndependentFirstUnlock() {
        var state = AttendanceState()
        Attendance.recordUnlock(in: &state, at: date("2026-09-28T08:47:00"), calendar: calendar)
        expectNil(Attendance.today(in: state, now: date("2026-09-29T05:00:00"), calendar: calendar))
        expectFalse(Attendance.recordUnlock(in: &state, at: date("2026-09-29T05:00:00"), calendar: calendar))
        expectTrue(Attendance.recordUnlock(in: &state, at: date("2026-09-29T09:00:00"), calendar: calendar))
        expectEqual(state.arrivals.count, 2)
    }

    func testDepartureIncludesBreak() {
        var state = AttendanceState()
        Attendance.recordUnlock(in: &state, at: date("2026-09-28T08:47:00"), calendar: calendar)
        let departure = Attendance.departure(for: state.arrivals["2026-09-28"]!, settings: state.settings)
        expectEqual(departure, date("2026-09-28T17:47:00"))
        expectEqual(Attendance.remainingMinutes(until: departure, now: date("2026-09-28T15:12:00")), 155)
    }

    func testRemainingTimeCeilsAndClamps() {
        let end = date("2026-09-28T17:47:00")
        expectEqual(Attendance.remainingMinutes(until: end, now: end.addingTimeInterval(-1)), 1)
        expectEqual(Attendance.remainingMinutes(until: end, now: end), 0)
        expectEqual(Attendance.remainingMinutes(until: end, now: end.addingTimeInterval(3600)), 0)
    }

    func testClockLabelsUse24HoursAndRecordedZone() {
        let sample = date("2026-09-28T17:55:00")
        expectEqual(Attendance.clockLabel(sample, timeZone: calendar.timeZone), "17:55")
        expectEqual(Attendance.clockLabel(sample, timeZone: TimeZone(secondsFromGMT: 0)!), "08:55")
        expectEqual(Attendance.clockLabel(date("2026-09-28T00:05:00"), timeZone: calendar.timeZone), "00:05")
    }

    func testManualCorrectionSurvivesLaterUnlock() throws {
        var state = AttendanceState()
        let now = date("2026-09-28T12:00:00")
        Attendance.recordUnlock(in: &state, at: now, calendar: calendar)
        try Attendance.setManual(in: &state, at: date("2026-09-28T08:30:00"), now: now, calendar: calendar)
        Attendance.recordUnlock(in: &state, at: date("2026-09-28T13:00:00"), calendar: calendar)
        expectEqual(state.arrivals["2026-09-28"]?.time, date("2026-09-28T08:30:00"))
        expectEqual(state.arrivals["2026-09-28"]?.source, .manual)
    }

    func testRejectsFutureAndOtherDayWithoutMutation() throws {
        var state = AttendanceState()
        let original = state
        let now = date("2026-09-28T12:00:00")
        expectThrows(try Attendance.setManual(in: &state, at: date("2026-09-28T13:00:00"), now: now, calendar: calendar))
        expectThrows(try Attendance.setManual(in: &state, at: date("2026-09-27T09:00:00"), now: now, calendar: calendar))
        expectEqual(state, original)
    }

    func testManualEarlyStartIsAllowed() throws {
        var state = AttendanceState()
        try Attendance.setManual(in: &state, at: date("2026-09-28T05:30:00"), now: date("2026-09-28T12:00:00"), calendar: calendar)
        expectNotNil(state.arrivals["2026-09-28"])
    }

    func testDayOffSuppressesLaterUnlockAndManualResumes() throws {
        var state = AttendanceState()
        let now = date("2026-09-28T12:00:00")
        Attendance.recordUnlock(in: &state, at: now, calendar: calendar)
        Attendance.skipToday(in: &state, now: now, calendar: calendar)
        expectFalse(Attendance.recordUnlock(in: &state, at: now, calendar: calendar))
        expectNil(state.arrivals["2026-09-28"])
        try Attendance.setManual(in: &state, at: now, now: now, calendar: calendar)
        expectNotNil(state.arrivals["2026-09-28"])
        expectFalse(state.suppressedDays.contains("2026-09-28"))
    }

    func testDayOffDoesNotSuppressNextDay() {
        var state = AttendanceState()
        Attendance.skipToday(in: &state, now: date("2026-09-28T12:00:00"), calendar: calendar)
        expectTrue(Attendance.recordUnlock(in: &state, at: date("2026-09-29T08:00:00"), calendar: calendar))
    }

    func testLocalDayDoesNotUseUTCDate() {
        var state = AttendanceState()
        Attendance.recordUnlock(in: &state, at: date("2026-09-28T06:00:00"), calendar: calendar)
        expectNotNil(state.arrivals["2026-09-28"])
        expectNil(state.arrivals["2026-09-27"])
    }

    func testCountdownUsesElapsedTimeAcrossDST() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = ISO8601DateFormatter().date(from: "2026-03-08T00:00:00-08:00")!
        let record = Arrival(day: "2026-03-08", time: start, source: .manual, timeZoneID: cal.timeZone.identifier)
        let end = Attendance.departure(for: record, settings: WorkSettings())
        expectEqual(end.timeIntervalSince(start), 9 * 3600)
        expectEqual(cal.component(.hour, from: end), 10)
    }

    func testPersistenceAndRestartDoNotOverwriteArrival() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AfterSix-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = StateStore(url: folder.appendingPathComponent("state.json"))
        var original = AttendanceState()
        Attendance.recordUnlock(in: &original, at: date("2026-09-28T08:47:00"), calendar: calendar)
        try store.save(original)
        var loaded = try store.load()
        expectEqual(loaded, original)
        expectFalse(Attendance.recordUnlock(in: &loaded, at: date("2026-09-28T15:00:00"), calendar: calendar))
        expectEqual(loaded.arrivals, original.arrivals)
        let mode = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? Int
        expectEqual(mode, 0o600)
    }

    func testMissingFileDoesNotInventAttendanceOrWrite() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AfterSix-missing-\(UUID().uuidString)/state.json")
        let state = try StateStore(url: url).load()
        expectTrue(state.arrivals.isEmpty)
        expectFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testCorruptFileIsPreserved() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AfterSix-corrupt-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data("not valid json".utf8)
        try data.write(to: url)
        expectThrows(try StateStore(url: url).load())
        try expectEqual(try Data(contentsOf: url), data)
    }

    func testInvalidSettingsCannotOverwriteFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AfterSix-invalid-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = StateStore(url: folder.appendingPathComponent("state.json"))
        let state = AttendanceState()
        try store.save(state)
        var bad = state
        bad.settings.workMinutes = -1
        expectThrows(try store.save(bad))
        try expectEqual(try store.load(), state)
    }

    func testUnknownSchemaIsRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AfterSix-schema-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var state = AttendanceState()
        state.version = 99
        try JSONEncoder().encode(state).write(to: url)
        expectThrows(try StateStore(url: url).load())
    }
}
