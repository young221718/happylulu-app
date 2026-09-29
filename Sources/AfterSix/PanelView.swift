import SwiftUI
import ServiceManagement
import AfterSixCore

// The explicit type alias selects the macOS 13-compatible property wrapper,
// avoiding the SDK 27 State macro that requires an Xcode-only compiler plugin.
private typealias LocalState<Value> = SwiftUI.State<Value>

struct PanelView: View {
    @ObservedObject var model: AppModel
    @LocalState private var editing = false
    @LocalState private var editTime = Date()
    @LocalState private var editDay = ""
    @LocalState private var settingsVisible = false
    @LocalState private var historyVisible = false
    @LocalState private var confirmSkip = false
    private let accent = Color(red: 0.16, green: 0.48, blue: 0.42)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                header
                summary
                timeCards
                actions
                if editing { editor }
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                DisclosureGroup("근무시간 및 자동 실행", isExpanded: $settingsVisible) { settings }
                    .font(.system(size: 12, weight: .medium))
                DisclosureGroup("최근 출근 기록", isExpanded: $historyVisible) { history }
                    .font(.system(size: 12, weight: .medium))
                footer
            }
            .padding(22)
        }
        .frame(width: 364, height: 570)
        .tint(accent)
        .onAppear { model.refresh() }
        .confirmationDialog("오늘 출근 기록을 지우고 자동 기록을 쉬겠어요?", isPresented: $confirmSkip) {
            Button("오늘 쉬는 날로 변경", role: .destructive) { model.skipToday(); editing = false }
            Button("취소", role: .cancel) {}
        } message: { Text("오늘은 다시 잠금을 해제해도 자동으로 기록하지 않습니다. 출근 시각을 직접 입력하면 다시 시작합니다.") }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().interpolation(.high).frame(width: 36, height: 36)
                .accessibilityLabel("HappyLulu 웃는 시계")
            VStack(alignment: .leading, spacing: 2) {
                Text("HappyLulu").font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("우리의 하루를 더 즐겁게.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(model.now.formatted(.dateTime.locale(Locale(identifier: "ko_KR")).month().day().weekday(.abbreviated)))
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(model.minutesLeft == nil ? "TODAY" : "TIME TO GO HOME")
                .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.8).foregroundStyle(accent)
            if let minutes = model.minutesLeft {
                Text(minutes == 0 ? "오늘도 수고했어요" : model.duration(minutes))
                    .font(.system(size: 29, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(minutes == 0 ? "오늘의 퇴근 시간이 됐어요." : "퇴근까지 남았어요")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                ProgressView(value: model.progress).padding(.top, 6)
            } else {
                Text(model.isSkipped ? "오늘은 쉬어가요" : "출근 기록 대기")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text(model.isSkipped ? "오늘 자동 기록을 쉬고 있어요." : "오전 6시 이후 첫 잠금 해제를 기다려요.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text("이미 출근했다면 아래에서 시각을 입력해 주세요.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if model.earlyLeaveMinutes > 0 && !model.isSkipped {
                Label("마지막 금요일 · 2시간 조기 퇴근", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 16))
    }

    private var timeCards: some View {
        HStack(spacing: 10) {
            timeCard("출근", time: model.arrival.map { model.timeLabel($0.time) } ?? "—",
                     note: model.arrival.map { $0.source == .unlock ? "잠금 해제 감지" : "직접 입력" } ?? "아직 기록 없음")
            timeCard("퇴근 예정", time: model.departure.map { model.timeLabel($0) } ?? "—",
                     note: model.departure.map { model.calendar.isDate($0, inSameDayAs: model.now) ? "휴게시간 포함" : "다음 날 · 휴게 포함" } ?? "출근 후 계산")
        }
    }

    private func timeCard(_ title: String, time: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(time).font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit()
            Text(note).font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private var actions: some View {
        HStack {
            Button {
                model.refresh()
                editTime = model.arrival?.time ?? model.now
                editDay = Attendance.dayKey(model.now, calendar: model.calendar)
                editing.toggle()
            } label: { Label(model.arrival == nil ? "출근 시각 입력" : "출근 시각 수정", systemImage: "pencil") }
                .buttonStyle(.borderedProminent).controlSize(.small)
            Spacer()
            Button("오늘 쉬는 날") { confirmSkip = true }
                .buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(.secondary)
                .disabled(model.isSkipped)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                DatePicker("오늘 출근", selection: $editTime, displayedComponents: [.hourAndMinute])
                    .datePickerStyle(.field).labelsHidden()
                Spacer()
                Button("취소") { editing = false }.controlSize(.small)
                Button("저장") {
                    model.refresh()
                    guard editDay == Attendance.dayKey(model.now, calendar: model.calendar) else {
                        model.errorMessage = "날짜가 바뀌었습니다. 입력 창을 다시 열어 주세요."
                        editing = false
                        return
                    }
                    let components = model.calendar.dateComponents([.hour, .minute], from: editTime)
                    let start = model.calendar.startOfDay(for: model.now)
                    if let date = model.calendar.date(bySettingHour: components.hour!, minute: components.minute!, second: 0, of: start), model.saveManual(date) {
                        editing = false
                    }
                }.controlSize(.small).buttonStyle(.borderedProminent)
            }
            Text("오늘 시각만 수정할 수 있으며, 미래 시각은 저장하지 않아요.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private var settings: some View {
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
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Text("매달 마지막 금요일에는 퇴근 예정이 2시간 빨라집니다.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Toggle("로그인 시 자동 실행", isOn: Binding(get: { model.loginEnabled }, set: { model.setLoginEnabled($0) }))
                .toggleStyle(.switch).controlSize(.mini)
            Text(model.loginDescription).font(.system(size: 10)).foregroundStyle(.secondary)
            if model.loginStatus == .requiresApproval {
                Button("시스템 설정에서 허용") { SMAppService.openSystemSettingsLoginItems() }
            }
        }
        .font(.system(size: 11)).padding(.top, 12)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 9) {
            let records = model.state.arrivals.values.sorted { $0.day > $1.day }.prefix(7)
            if records.isEmpty {
                Text("아직 저장된 출근 기록이 없어요.").foregroundStyle(.secondary)
            }
            ForEach(Array(records), id: \.day) { record in
                HStack {
                    Text(record.day)
                    Spacer()
                    Text(Attendance.clockLabel(record.time, timeZone: TimeZone(identifier: record.timeZoneID) ?? .current)).monospacedDigit()
                    Image(systemName: record.source == .unlock ? "lock.open" : "pencil").foregroundStyle(.secondary)
                }
            }
        }
        .font(.system(size: 11)).padding(.top, 10)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.state.lastUnlockAt.map { "최근 잠금 해제 감지 · \($0.formatted(.dateTime.month().day().hour().minute()))" }
                 ?? "잠금 해제 감지 대기 중 · 매일 오전 6시부터")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
            HStack {
                Button("기록 폴더") { model.showData() }
                Spacer()
                Button("종료") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
