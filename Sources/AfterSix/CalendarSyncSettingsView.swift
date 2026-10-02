import AppKit
import SwiftUI
import CalendarSyncCore
import CalendarSyncServices

// Use the macOS 13-compatible wrapper with the Command Line Tools compiler.
private typealias LocalState<Value> = SwiftUI.State<Value>

struct CalendarSyncSettingsView: View {
    @ObservedObject var model: CalendarSyncModel
    @LocalState private var serverAddressCopied = false
    private let accent = Color(red: 0.16, green: 0.48, blue: 0.42)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                accountSetup
                calendarSelection
                previewSection
                conflictSection
                statusSection
            }
            .padding(28)
        }
        .frame(minWidth: 620, minHeight: 680)
        .tint(accent)
        .onAppear { model.prepareForDisplay() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("HappyLulu Calendar", systemImage: "calendar.badge.clock")
                .font(.title.bold())
            Text("Mac에 연결된 다우오피스와 Google의 일정 추가·수정을 약 1시간마다 양쪽으로 맞춥니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var accountSetup: some View {
        GroupBox("1. 계정 연결") {
            VStack(alignment: .leading, spacing: 12) {
                Text("로그인은 macOS 인터넷 계정에서 처리합니다. HappyLulu는 Google 또는 다우오피스 비밀번호를 받지 않아요.")
                    .font(.subheadline)
                HStack {
                    Button("인터넷 계정 열기") { model.openInternetAccounts() }
                        .buttonStyle(.borderedProminent)
                    Button(model.calendarAccessReady ? "캘린더 목록 새로고침" : "캘린더 연결 허용") { model.refreshCalendars() }
                        .disabled(model.isRunning)
                    Button("권한 설정 열기") { model.openCalendarPrivacy() }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Google: 계정 추가에서 Google을 선택하면 웹 로그인 창이 열립니다.")
                    Text("다우오피스: 기타 계정 → CalDAV를 선택합니다.")
                    HStack(spacing: 10) {
                        Text("서버: lululab.daouoffice.com")
                            .font(.system(size: 12, design: .monospaced))
                        Button("서버 주소 복사") {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            serverAddressCopied = pasteboard.setString("lululab.daouoffice.com", forType: .string)
                        }
                        .buttonStyle(.bordered)
                        if serverAddressCopied {
                            Label("복사됨", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(accent)
                        }
                    }
                    Text("회사 이메일과 비밀번호는 macOS 인터넷 계정 화면에 직접 입력합니다.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if model.calendarAccessReady {
                    Label("Mac 캘린더 접근 허용됨", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .textSelection(.enabled)
        }
    }

    private var calendarSelection: some View {
        GroupBox("2. 동기화할 캘린더 선택") {
            VStack(alignment: .leading, spacing: 12) {
                if model.calendars.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 30)).foregroundStyle(.secondary)
                        Text("Google·CalDAV 계정의 캘린더가 아직 없습니다").font(.headline)
                        Text("계정을 추가한 뒤 캘린더 연결 허용을 눌러 주세요.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 130)
                } else {
                    Picker("다우오피스 캘린더", selection: $model.selectedDaouCalendar) {
                        Text("선택하세요").tag("")
                        ForEach(model.calendars) { calendar in
                            Text("\(calendar.accountName) · \(calendar.title)").tag(calendar.id)
                        }
                    }
                    .disabled(model.isRunning || model.pairLocked)
                    Picker("Google 캘린더", selection: $model.selectedGoogleCalendar) {
                        Text("선택하세요").tag("")
                        ForEach(model.calendars) { calendar in
                            Text("\(calendar.accountName) · \(calendar.title)").tag(calendar.id)
                        }
                    }
                    .disabled(model.isRunning || model.pairLocked)
                    Text("처음에는 양쪽에 빈 테스트 캘린더를 하나씩 만들어 선택하는 것을 권장합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("선택한 캘린더가 각각 다우오피스와 Google 계정에 연결된 것을 확인했어요.",
                           isOn: $model.accountsConfirmed)
                        .font(.caption)
                        .disabled(model.isRunning || (model.pairLocked && model.accountsConfirmed))
                    Text("macOS가 서버 주소를 공개하지 않아 계정 이름으로 확인해야 합니다. 서로 다른 두 계정의 캘린더를 선택해 주세요.")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.pairLocked {
                        Text("연결 기록을 보존하기 위해 동기화를 시작한 캘린더 선택은 고정됩니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("첫 동기화 미리보기") { model.runPreview() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!selectionReady || model.isRunning)
                    Button("캘린더 새로고침") { model.refreshCalendars() }
                        .disabled(model.isRunning)
                    if model.isRunning { ProgressView().controlSize(.small) }
                }
                Text("조회되지 않는 일정은 보류합니다. 현재 버전은 일정 삭제를 상대 캘린더에 자동으로 반영하지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if let preview = model.preview {
            GroupBox("3. 미리보기") {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Google에 반영 \(preview.toGoogle)건 · 다우에 반영 \(preview.toDaou)건")
                    Text("중복 의심·충돌 \(preview.conflicts)건 · 보류 \(preview.held)건 · 지원 제외 \(preview.excluded)건")
                    Text("미리보기는 시스템 캘린더를 변경하지 않습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        if model.enabled {
                            Button("지금 동기화") { model.syncNow() }
                            Button("일시 중지") { model.setPaused(true) }
                        } else {
                            Button("양방향 동기화 시작") { model.beginSync() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .disabled(model.isRunning || !selectionReady)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
        }
    }

    @ViewBuilder
    private var conflictSection: some View {
        if !model.conflicts.isEmpty {
            GroupBox("확인이 필요한 일정") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.conflicts, id: \.mappingID) { conflict in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(conflictTitle(conflict)).font(.system(size: 12, weight: .semibold))
                            Text("다우: \(eventTitle(conflict.daou))")
                            Text("Google: \(eventTitle(conflict.google))")
                            HStack {
                                Button("다우 내용 적용") { model.resolveConflict(conflict, prefer: .daou) }
                                Button("Google 내용 적용") { model.resolveConflict(conflict, prefer: .google) }
                            }
                            .disabled(model.isRunning || !model.enabled || model.lastSuccessAt == nil)
                        }
                        .font(.caption)
                        if conflict.mappingID != model.conflicts.last?.mappingID { Divider() }
                    }
                    Text("미리보기를 확인하고 동기화를 시작한 뒤 선택할 수 있습니다. 선택한 내용을 상대 캘린더에 즉시 반영하며, 직전에 최신 버전을 다시 확인합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let last = model.lastSuccessAt {
                Text("마지막 성공: \(last.formatted(date: .abbreviated, time: .shortened))")
            }
            if let next = model.nextRunAt, model.enabled {
                Text("다음 실행: \(next.formatted(date: .abbreviated, time: .shortened))")
            }
            if let message = model.message {
                Text(message).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption)
    }

    private var selectionReady: Bool {
        !model.selectedDaouCalendar.isEmpty &&
        !model.selectedGoogleCalendar.isEmpty &&
        model.selectedDaouCalendar != model.selectedGoogleCalendar
        && model.accountsConfirmed
        && selectedAccountIDsDiffer
    }

    private var selectedAccountIDsDiffer: Bool {
        guard let daou = model.calendars.first(where: { $0.id == model.selectedDaouCalendar }),
              let google = model.calendars.first(where: { $0.id == model.selectedGoogleCalendar }) else { return false }
        return daou.accountID != google.accountID
    }

    private func eventTitle(_ observation: CalendarObservation) -> String {
        switch observation {
        case .present(let event): event.content.title
        case .confirmedDeleted: "삭제됨"
        case .absent: "없음"
        case .unavailable: "조회할 수 없음"
        }
    }

    private func conflictTitle(_ conflict: SyncConflict) -> String {
        switch conflict.reason {
        case .simultaneousEdits: "양쪽에서 모두 수정됨"
        case .editVersusDeletion: "한쪽 수정 · 한쪽 삭제"
        case .initialPairAmbiguous: "처음 연결할 중복 의심 일정"
        }
    }
}
