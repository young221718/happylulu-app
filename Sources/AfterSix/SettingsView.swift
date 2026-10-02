import SwiftUI
import ServiceManagement
import AfterSixCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdater
    @ObservedObject private var language = AppLanguage.shared
    let onOpenCalendarSync: () -> Void
    private let accent = Color(red: 0.16, green: 0.48, blue: 0.42)
    private var selectedLocale: Locale { _ = language.choice; return displayLocale }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("HappyLulu 설정", "HappyLulu Settings")).font(.title.bold())
                    Text(L("근무 시간과 앱 동작을 관리합니다.", "Manage work hours and app behavior."))
                        .foregroundStyle(.secondary)
                }
                generalSection
                workSection
                calendarSection
                updatesSection
                if let error = model.errorMessage {
                    Label(visibleMessage(error), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .frame(minWidth: 580, minHeight: 620)
        .tint(accent)
        .environment(\.locale, selectedLocale)
    }

    private var generalSection: some View {
        GroupBox(L("일반", "General")) {
            VStack(alignment: .leading, spacing: 12) {
                Picker(L("언어", "Language"), selection: Binding(
                    get: { language.choice }, set: { language.select($0) })) {
                    ForEach(LanguageChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                Toggle(L("로그인 시 자동 실행", "Launch at login"), isOn: Binding(
                    get: { model.loginEnabled }, set: { model.setLoginEnabled($0) }))
                    .toggleStyle(.switch)
                Text(model.loginDescription).foregroundStyle(.secondary)
                if model.loginStatus == .requiresApproval {
                    Button(L("시스템 설정에서 허용", "Allow in System Settings")) { SMAppService.openSystemSettingsLoginItems() }
                }
                Divider()
                HStack {
                    Text(L("최근 출근 기록", "Recent arrivals")).font(.headline)
                    Spacer()
                    Button(L("기록 폴더 열기", "Open records folder")) { model.showData() }
                }
                let records = model.state.arrivals.values.sorted { $0.day > $1.day }.prefix(7)
                if records.isEmpty {
                    Text(L("아직 저장된 출근 기록이 없어요.", "No arrivals saved yet.")).foregroundStyle(.secondary)
                }
                ForEach(Array(records), id: \.day) { record in
                    HStack(spacing: 10) {
                        Text(displayDayKey(record.day))
                        if record.mode != .normal {
                            Text(record.mode.displayLabel).foregroundStyle(accent)
                        }
                        Spacer()
                        Text(displayClock(record.time,
                            timeZone: TimeZone(identifier: record.timeZoneID) ?? .current))
                            .monospacedDigit()
                        Image(systemName: record.source == .unlock ? "lock.open" : "pencil")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    private var workSection: some View {
        GroupBox(L("근무", "Work")) {
            VStack(alignment: .leading, spacing: 12) {
                Stepper(L("근무  \(model.duration(model.state.settings.workMinutes))", "Work  \(model.duration(model.state.settings.workMinutes))"), value: Binding(
                    get: { model.state.settings.workMinutes },
                    set: { model.updateSettings(work: $0, rest: model.state.settings.breakMinutes) }
                ), in: 60...960, step: 30)
                Stepper(L("휴게  \(model.duration(model.state.settings.breakMinutes))", "Break  \(model.duration(model.state.settings.breakMinutes))"), value: Binding(
                    get: { model.state.settings.breakMinutes },
                    set: { model.updateSettings(work: model.state.settings.workMinutes, rest: $0) }
                ), in: 0...240, step: 15)
                Text(L("오늘 퇴근 예정에도 바로 반영됩니다. 잠금·절전 중에도 시간이 흘러갑니다.", "Changes affect today’s departure immediately. Time continues while the Mac is locked or asleep."))
                    .foregroundStyle(.secondary)
                Text(L("매달 마지막 금요일에는 퇴근 예정이 2시간 빨라집니다. 반차는 휴게 없이 출근 4시간 뒤 퇴근하며, 마지막 금요일 단축과 중복 적용하지 않아요.", "On the last Friday of each month, departure is 2 hours earlier. A half-day ends 4 hours after arrival with no break or additional Friday reduction."))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    private var calendarSection: some View {
        GroupBox(L("캘린더", "Calendar")) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(L("캘린더 반차 자동 인식", "Detect half-days from calendar"), isOn: Binding(
                    get: { model.state.detectHalfDaysFromCalendar },
                    set: { model.setCalendarHalfDayDetection($0) }))
                    .toggleStyle(.switch)
                Text(L("접근 가능한 모든 캘린더의 '오전 반차'·'오후 반차' 제목을 읽습니다. 공유 캘린더의 다른 사람 반차도 확인해 주세요. 일정이 모호하면 출근 시각으로 판단해요.", "Reads morning and afternoon off titles from all accessible calendars. Check shared calendars for other people’s leave. Ambiguous events fall back to arrival time."))
                    .foregroundStyle(.secondary)
                if model.state.detectHalfDaysFromCalendar {
                    Button(L("반차 일정 다시 확인", "Check half-day events again")) { model.checkCalendarHalfDayNow() }
                }
                if let message = model.calendarHalfDayMessage {
                    Text(visibleMessage(message)).foregroundStyle(.secondary)
                }
                Divider()
                Button { onOpenCalendarSync() } label: {
                    Label(L("HappyLulu Calendar 열기", "Open HappyLulu Calendar"), systemImage: "arrow.up.forward.app")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    private var updatesSection: some View {
        GroupBox(L("업데이트 · \(updater.version)", "Updates · \(updater.version)")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("서명된 업데이트 목록 게시를 준비 중입니다. 현재는 다운로드 사이트에서 앱을 받아 수동으로 교체해 주세요.", "A signed update feed is being prepared. For now, download the app from the website and replace it manually."))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(L("새 버전 자동 확인", "Automatically check for updates"), isOn: Binding(
                    get: { updater.automaticallyChecks },
                    set: { updater.setAutomaticallyChecks($0) }))
                    .disabled(!updater.canCheckForUpdates)
                Text(L("자동 확인을 켜면 1시간마다 새 버전을 찾습니다. 새 버전이 있으면 먼저 업데이트할지 묻고, 업데이트를 선택하면 다운로드·설치 후 필요할 때 앱을 다시 시작합니다.", "When enabled, checks for updates hourly. You will be asked before downloading and installing a new version; the app may restart afterward."))
                    .foregroundStyle(.secondary)
                Button(L("지금 업데이트 확인", "Check for updates now")) { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
                if let error = updater.startupError {
                    Text(visibleMessage(error)).foregroundStyle(.orange)
                }
            }
            .toggleStyle(.switch)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}
