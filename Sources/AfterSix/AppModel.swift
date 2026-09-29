import AppKit
import Combine
import ServiceManagement
import AfterSixCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: AttendanceState
    @Published private(set) var now = Date()
    @Published var errorMessage: String?
    @Published private(set) var loginStatus = SMAppService.mainApp.status
    let store: StateStore
    private var writable = true
    private var timer: Timer?

    var calendar: Calendar { Calendar.current }
    var arrival: Arrival? { Attendance.today(in: state, now: now, calendar: calendar) }
    var departure: Date? { arrival.map { Attendance.departure(for: $0, settings: state.settings) } }
    var isSkipped: Bool { state.suppressedDays.contains(Attendance.dayKey(now, calendar: calendar)) }
    var minutesLeft: Int? { departure.map { Attendance.remainingMinutes(until: $0, now: now) } }
    var earlyLeaveMinutes: Int {
        if let arrival { return Attendance.earlyLeaveMinutes(for: arrival) }
        return Attendance.earlyLeaveMinutes(on: now, timeZone: calendar.timeZone)
    }
    var progress: Double {
        guard let arrival, let departure else { return 0 }
        return Attendance.progress(from: arrival.time, until: departure, now: now)
    }
    var menuTitle: String {
        guard let minutesLeft else { return isSkipped ? "오늘 쉬는 날" : "출근 대기" }
        return minutesLeft == 0 ? "퇴근 가능" : "퇴근 \(duration(minutesLeft))"
    }
    var loginEnabled: Bool { loginStatus == .enabled || loginStatus == .requiresApproval }
    var loginDescription: String {
        switch loginStatus {
        case .enabled: "로그인 시 자동 실행 켜짐"
        case .requiresApproval: "시스템 설정에서 허용이 필요합니다"
        case .notRegistered: "로그인 시 자동 실행 꺼짐"
        case .notFound: "앱을 응용 프로그램 폴더에서 실행해 주세요"
        @unknown default: "자동 실행 상태 확인 필요"
        }
    }

    init(store: StateStore = .standard) {
        self.store = store
        do { state = try store.load() }
        catch {
            state = AttendanceState()
            writable = false
            errorMessage = "저장된 기록을 불러오지 못했습니다. 원본을 보존했으며 새 기록 저장을 중지했습니다. \(error.localizedDescription)"
        }
    }

    func start() {
        // This notification is used by macOS but is not a documented Apple API.
        // A wake/session-active notification must never be treated as an unlock.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(screenUnlocked(_:)),
            name: Notification.Name("com.apple.screenIsUnlocked"), object: nil,
            suspensionBehavior: .drop
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(woke(_:)), name: NSWorkspace.didWakeNotification, object: nil
        )
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        // Register once; never fight a user's later System Settings choice.
        if writable, !state.didOfferLoginItem {
            setLoginEnabled(true)
        }
    }

    func refresh() {
        now = Date()
        loginStatus = SMAppService.mainApp.status
    }

    @objc private func woke(_ notification: Notification) { refresh() }

    @objc private func screenUnlocked(_ notification: Notification) {
        let receivedAt = Date()
        now = receivedAt
        commit { state in
            Attendance.recordUnlock(in: &state, at: receivedAt, calendar: calendar)
        }
    }

    @discardableResult
    private func commit(_ change: (inout AttendanceState) throws -> Void) -> Bool {
        guard writable else { return false }
        do {
            var updated = state
            try change(&updated)
            try store.save(updated)
            state = updated
            errorMessage = nil
            return true
        } catch {
            errorMessage = "저장하지 못했습니다: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func saveManual(_ date: Date) -> Bool {
        refresh()
        return commit { try Attendance.setManual(in: &$0, at: date, now: now, calendar: calendar) }
    }

    func skipToday() {
        refresh()
        commit { Attendance.skipToday(in: &$0, now: now, calendar: calendar) }
    }

    func updateSettings(work: Int, rest: Int) {
        commit {
            $0.settings.workMinutes = work
            $0.settings.breakMinutes = rest
            guard $0.settings.isValid else { throw AttendanceError.invalidSettings }
        }
    }

    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled && SMAppService.mainApp.status != .enabled && SMAppService.mainApp.status != .requiresApproval {
                try SMAppService.mainApp.register()
            } else if !enabled && SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
        } catch { errorMessage = "자동 실행 설정: \(error.localizedDescription)" }
        loginStatus = SMAppService.mainApp.status
        let applied = enabled ? (loginStatus == .enabled || loginStatus == .requiresApproval) : loginStatus == .notRegistered
        if applied && !state.didOfferLoginItem {
            commit { $0.didOfferLoginItem = true }
        }
    }

    func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)분" }
        if minutes % 60 == 0 { return "\(minutes / 60)시간" }
        return "\(minutes / 60)시간 \(minutes % 60)분"
    }

    func timeLabel(_ date: Date) -> String {
        Attendance.clockLabel(date, timeZone: calendar.timeZone)
    }

    func showData() { NSWorkspace.shared.selectFile(store.url.path, inFileViewerRootedAtPath: "") }
}
