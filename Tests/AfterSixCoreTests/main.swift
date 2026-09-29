import Foundation

func failure(_ message: String, file: StaticString, line: UInt) -> Never {
    FileHandle.standardError.write(Data("FAIL \(file):\(line): \(message)\n".utf8))
    exit(1)
}
func expectEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) rethrows {
    let a = try lhs(), b = try rhs()
    if a != b { failure("\(a) != \(b)", file: file, line: line) }
}
func expectTrue(_ value: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !value() { failure("Expected true", file: file, line: line) }
}
func expectFalse(_ value: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    if value() { failure("Expected false", file: file, line: line) }
}
func expectNil<T>(_ value: @autoclosure () -> T?, file: StaticString = #filePath, line: UInt = #line) {
    if value() != nil { failure("Expected nil", file: file, line: line) }
}
func expectNotNil<T>(_ value: @autoclosure () -> T?, file: StaticString = #filePath, line: UInt = #line) {
    if value() == nil { failure("Expected non-nil", file: file, line: line) }
}
func expectThrows<T>(_ value: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try value() } catch { return }
    failure("Expected an error", file: file, line: line)
}

let tests = AttendanceTests()
let checks: [(String, () throws -> Void)] = [
    ("06:00 boundary", tests.testBeforeSixIsIgnoredAndExactSixAccepted),
    ("First unlock wins", tests.testLaterUnlockDoesNotReplaceFirstArrival),
    ("New day", tests.testNewDayHasIndependentFirstUnlock),
    ("Work plus break", tests.testDepartureIncludesBreak),
    ("Last Friday across month lengths and year end", tests.testLastFridayAcrossMonthLengthsAndYearEnd),
    ("Early departure countdown and progress", tests.testLastFridayDepartureCountdownAndProgress),
    ("Regular Friday unchanged", tests.testRegularFridayKeepsNormalDeparture),
    ("Early leave recorded timezone", tests.testEarlyLeaveUsesRecordedTimeZone),
    ("Custom and short workdays", tests.testEarlyLeaveWithCustomSettingsAndShortDays),
    ("Manual early leave persistence", tests.testEarlyLeaveManualArrivalPersistsWithoutSchemaChange),
    ("Countdown rounding", tests.testRemainingTimeCeilsAndClamps),
    ("24-hour clock and timezone", tests.testClockLabelsUse24HoursAndRecordedZone),
    ("Manual correction", tests.testManualCorrectionSurvivesLaterUnlock),
    ("Invalid manual dates", tests.testRejectsFutureAndOtherDayWithoutMutation),
    ("Manual early start", tests.testManualEarlyStartIsAllowed),
    ("Day off and resume", tests.testDayOffSuppressesLaterUnlockAndManualResumes),
    ("Day off expires", tests.testDayOffDoesNotSuppressNextDay),
    ("Local calendar day", tests.testLocalDayDoesNotUseUTCDate),
    ("DST elapsed duration", tests.testCountdownUsesElapsedTimeAcrossDST),
    ("Persistence and restart", tests.testPersistenceAndRestartDoNotOverwriteArrival),
    ("No invented arrival", tests.testMissingFileDoesNotInventAttendanceOrWrite),
    ("Corrupt file preserved", tests.testCorruptFileIsPreserved),
    ("Invalid settings", tests.testInvalidSettingsCannotOverwriteFile),
    ("Unknown schema", tests.testUnknownSchemaIsRejected)
]
for (name, run) in checks {
    do { try run(); print("PASS \(name)") }
    catch { failure("\(name): \(error)", file: #filePath, line: #line) }
}
print("\(checks.count) checks passed")
