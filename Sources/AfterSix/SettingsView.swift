import SwiftUI
import ServiceManagement
import AfterSixCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdater
    let onOpenCalendarSync: () -> Void
    private let accent = Color(red: 0.16, green: 0.48, blue: 0.42)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("HappyLulu 설정").font(.title.bold())
                    Text("근무 시간과 앱 동작을 관리합니다.")
                        .foregroundStyle(.secondary)
                }
                generalSection
                workSection
                calendarSection
                updatesSection
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .frame(minWidth: 580, minHeight: 620)
        .tint(accent)
    }

    private var generalSection: some View {
        GroupBox("일반") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("로그인 시 자동 실행", isOn: Binding(
                    get: { model.loginEnabled }, set: { model.setLoginEnabled($0) }))
                    .toggleStyle(.switch)
                Text(model.loginDescription).foregroundStyle(.secondary)
                if model.loginStatus == .requiresApproval {
                    Button("시스템 설정에서 허용") { SMAppService.openSystemSettingsLoginItems() }
                }
                Divider()
                HStack {
                    Text("최근 출근 기록").font(.headline)
                    Spacer()
                    Button("기록 폴더 열기") { model.showData() }
                }
                let records = model.state.arrivals.values.sorted { $0.day > $1.day }.prefix(7)
                if records.isEmpty {
                    Text("아직 저장된 출근 기록이 없어요.").foregroundStyle(.secondary)
                }
                ForEach(Array(records), id: \.day) { record in
                    HStack(spacing: 10) {
                        Text(record.day)
                        if record.mode != .normal {
                            Text(record.mode.label).foregroundStyle(accent)
                        }
                        Spacer()
                        Text(Attendance.clockLabel(record.time,
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
        GroupBox("근무") {
            VStack(alignment: .leading, spacing: 12) {
                Stepper("근무  \(model.duration(model.state.settings.workMinutes))", value: Binding(
                    get: { model.state.settings.workMinutes },
                    set: { model.updateSettings(work: $0, rest: model.state.settings.breakMinutes) }
                ), in: 60...960, step: 30)
                Stepper("휴게  \(model.duration(model.state.settings.breakMinutes))", value: Binding(
                    get: { model.state.settings.breakMinutes },
                    set: { model.updateSettings(work: model.state.settings.workMinutes, rest: $0) }
                ), in: 0...240, step: 15)
                Text("오늘 퇴근 예정에도 바로 반영됩니다. 잠금·절전 중에도 시간이 흘러갑니다.")
                    .foregroundStyle(.secondary)
                Text("매달 마지막 금요일에는 퇴근 예정이 2시간 빨라집니다. 반차는 휴게 없이 출근 4시간 뒤 퇴근하며, 마지막 금요일 단축과 중복 적용하지 않아요.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    private var calendarSection: some View {
        GroupBox("캘린더") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("캘린더 반차 자동 인식", isOn: Binding(
                    get: { model.state.detectHalfDaysFromCalendar },
                    set: { model.setCalendarHalfDayDetection($0) }))
                    .toggleStyle(.switch)
                Text("접근 가능한 모든 캘린더의 '오전 반차'·'오후 반차' 제목을 읽습니다. 공유 캘린더의 다른 사람 반차도 확인해 주세요. 일정이 모호하면 출근 시각으로 판단해요.")
                    .foregroundStyle(.secondary)
                if model.state.detectHalfDaysFromCalendar {
                    Button("반차 일정 다시 확인") { model.checkCalendarHalfDayNow() }
                }
                if let message = model.calendarHalfDayMessage {
                    Text(message).foregroundStyle(.secondary)
                }
                Divider()
                Button { onOpenCalendarSync() } label: {
                    Label("HappyLulu Calendar 열기", systemImage: "arrow.up.forward.app")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    private var updatesSection: some View {
        GroupBox("업데이트 · \(updater.version)") {
            VStack(alignment: .leading, spacing: 12) {
                Text("서명된 업데이트 목록 게시를 준비 중입니다. 현재는 다운로드 사이트에서 앱을 받아 수동으로 교체해 주세요.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("새 버전 자동 확인", isOn: Binding(
                    get: { updater.automaticallyChecks },
                    set: { updater.setAutomaticallyChecks($0) }))
                    .disabled(!updater.canCheckForUpdates)
                Text("자동 확인을 켜면 1시간마다 새 버전을 찾습니다. 새 버전이 있으면 먼저 업데이트할지 묻고, 업데이트를 선택하면 다운로드·설치 후 필요할 때 앱을 다시 시작합니다.")
                    .foregroundStyle(.secondary)
                Button("지금 업데이트 확인") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
                if let error = updater.startupError {
                    Text(error).foregroundStyle(.orange)
                }
            }
            .toggleStyle(.switch)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}
