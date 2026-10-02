import SwiftUI
import AfterSixCore

// The explicit type alias selects the macOS 13-compatible property wrapper,
// avoiding the SDK 27 State macro that requires an Xcode-only compiler plugin.
private typealias LocalState<Value> = SwiftUI.State<Value>

private enum ManualModeChoice: String, CaseIterable {
    case automatic, normal, morningHalf, afternoonHalf

    var label: String {
        switch self {
        case .automatic: "자동 판단"
        case .normal: "일반 근무"
        case .morningHalf: "오전 반차"
        case .afternoonHalf: "오후 반차"
        }
    }

    var selectedMode: WorkdayMode? {
        switch self {
        case .automatic: nil
        case .normal: .normal
        case .morningHalf: .morningHalf
        case .afternoonHalf: .afternoonHalf
        }
    }

    static func from(_ mode: WorkdayMode) -> Self {
        switch mode {
        case .normal: .normal
        case .morningHalf: .morningHalf
        case .afternoonHalf: .afternoonHalf
        }
    }
}

struct PanelView: View {
    @ObservedObject var model: AppModel
    let onOpenSettings: () -> Void
    @LocalState private var editing = false
    @LocalState private var editTime = Date()
    @LocalState private var editMode = ManualModeChoice.automatic
    @LocalState private var editDay = ""
    @LocalState private var confirmSkip = false
    private let accent = Color(red: 0.16, green: 0.48, blue: 0.42)

    var body: some View {
        VStack(spacing: 0) {
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
                    lastUnlockStatus
                }
                .padding(20)
            }
            Divider()
            HStack {
                Button { onOpenSettings() } label: {
                    Label("설정", systemImage: "gearshape")
                }
                Spacer()
                Button("종료") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 364, height: 470)
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
                Text(model.isSkipped ? "오늘 자동 기록을 쉬고 있어요." : "일반·오후 반차 08:00~10:00, 오전 반차 13:00~15:00")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text("이미 출근했다면 아래에서 시각을 입력해 주세요.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let arrival = model.arrival {
                let reason = arrival.modeSource == .manual ? "직접 지정" :
                    (model.detectedModeToday == arrival.mode && arrival.mode != .normal ? "캘린더 인식" : "출근 시각 자동 인식")
                Label("\(arrival.mode.label) · \(reason)", systemImage: "calendar.badge.clock")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
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
                     note: model.departure.map {
                         if model.arrival?.mode != .normal { return "반차 · 휴게 없이 4시간" }
                         return model.calendar.isDate($0, inSameDayAs: model.now) ? "휴게시간 포함" : "다음 날 · 휴게 포함"
                     } ?? "출근 후 계산")
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
                editMode = model.arrival?.modeSource == .manual
                    ? ManualModeChoice.from(model.arrival!.mode) : .automatic
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
            Picker("근무 유형", selection: $editMode) {
                ForEach(ManualModeChoice.allCases, id: \.self) { choice in
                    Text(choice.label).tag(choice)
                }
            }.pickerStyle(.menu)
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
                    if let date = model.calendar.date(bySettingHour: components.hour!, minute: components.minute!, second: 0, of: start),
                       model.saveManual(date, selectedMode: editMode.selectedMode) {
                        editing = false
                    }
                }.controlSize(.small).buttonStyle(.borderedProminent)
            }
            Text("일반·오후 반차 08:00~10:00, 오전 반차 13:00~15:00. 미래 시각은 저장하지 않아요.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private var lastUnlockStatus: some View {
        Text(model.state.lastUnlockAt.map { "최근 잠금 해제 감지 · \($0.formatted(.dateTime.month().day().hour().minute()))" }
             ?? "잠금 해제 감지 대기 중 · 일반 08~10시, 오전 반차 13~15시")
            .font(.system(size: 10)).foregroundStyle(.tertiary)
    }
}
