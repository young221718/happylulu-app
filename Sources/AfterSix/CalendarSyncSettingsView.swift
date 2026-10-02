import AppKit
import SwiftUI
import CalendarSyncCore
import CalendarSyncServices

// Use the macOS 13-compatible wrapper with the Command Line Tools compiler.
private typealias LocalState<Value> = SwiftUI.State<Value>

struct CalendarSyncSettingsView: View {
    @ObservedObject var model: CalendarSyncModel
    @ObservedObject private var language = AppLanguage.shared
    @LocalState private var serverAddressCopied = false
    private let accent = Color(red: 0.16, green: 0.48, blue: 0.42)
    private var selectedLocale: Locale { _ = language.choice; return displayLocale }

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
        .environment(\.locale, selectedLocale)
        .onAppear { model.prepareForDisplay() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("HappyLulu Calendar", systemImage: "calendar.badge.clock")
                .font(.title.bold())
            Text(L("Mac에 연결된 다우오피스와 Google의 일정 추가·수정을 약 1시간마다 양쪽으로 맞춥니다.", "Sync added and edited events between Daouoffice and Google accounts connected to your Mac about once an hour."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var accountSetup: some View {
        GroupBox(L("1. 계정 연결", "1. Connect accounts")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("로그인은 macOS 인터넷 계정에서 처리합니다. HappyLulu는 Google 또는 다우오피스 비밀번호를 받지 않아요.", "Sign in through macOS Internet Accounts. HappyLulu does not collect your Google or Daouoffice password."))
                    .font(.subheadline)
                HStack {
                    Button(L("인터넷 계정 열기", "Open Internet Accounts")) { model.openInternetAccounts() }
                        .buttonStyle(.borderedProminent)
                    Button(model.calendarAccessReady ? L("캘린더 목록 새로고침", "Refresh calendars") : L("캘린더 연결 허용", "Allow calendar access")) { model.refreshCalendars() }
                        .disabled(model.isRunning)
                    Button(L("권한 설정 열기", "Open permission settings")) { model.openCalendarPrivacy() }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("Google: 계정 추가에서 Google을 선택하면 웹 로그인 창이 열립니다.", "Google: Select Google under Add Account to open web sign-in."))
                    Text(L("다우오피스: 기타 계정 → CalDAV를 선택합니다.", "Daouoffice: Select Other Account → CalDAV."))
                    HStack(spacing: 10) {
                        Text(L("서버: lululab.daouoffice.com", "Server: lululab.daouoffice.com"))
                            .font(.system(size: 12, design: .monospaced))
                        Button(L("서버 주소 복사", "Copy server address")) {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            serverAddressCopied = pasteboard.setString("lululab.daouoffice.com", forType: .string)
                        }
                        .buttonStyle(.bordered)
                        if serverAddressCopied {
                            Label(L("복사됨", "Copied"), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(accent)
                        }
                    }
                    Text(L("회사 이메일과 비밀번호는 macOS 인터넷 계정 화면에 직접 입력합니다.", "Enter your work email and password directly in macOS Internet Accounts."))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if model.calendarAccessReady {
                    Label(L("Mac 캘린더 접근 허용됨", "Mac calendar access allowed"), systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .textSelection(.enabled)
        }
    }

    private var calendarSelection: some View {
        GroupBox(L("2. 동기화할 캘린더 선택", "2. Select calendars to sync")) {
            VStack(alignment: .leading, spacing: 12) {
                if model.calendars.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 30)).foregroundStyle(.secondary)
                        Text(L("Google·CalDAV 계정의 캘린더가 아직 없습니다", "No Google or CalDAV calendars found")).font(.headline)
                        Text(L("계정을 추가한 뒤 캘린더 연결 허용을 눌러 주세요.", "Add an account, then allow calendar access."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 130)
                } else {
                    Picker(L("다우오피스 캘린더", "Daouoffice calendar"), selection: $model.selectedDaouCalendar) {
                        Text(L("선택하세요", "Select a calendar")).tag("")
                        ForEach(model.calendars) { calendar in
                            Text("\(calendar.accountName) · \(calendar.title)").tag(calendar.id)
                        }
                    }
                    .disabled(model.isRunning || model.pairLocked)
                    Picker(L("Google 캘린더", "Google calendar"), selection: $model.selectedGoogleCalendar) {
                        Text(L("선택하세요", "Select a calendar")).tag("")
                        ForEach(model.calendars) { calendar in
                            Text("\(calendar.accountName) · \(calendar.title)").tag(calendar.id)
                        }
                    }
                    .disabled(model.isRunning || model.pairLocked)
                    Text(L("처음에는 양쪽에 빈 테스트 캘린더를 하나씩 만들어 선택하는 것을 권장합니다.", "We recommend starting with one empty test calendar in each account."))
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle(L("선택한 캘린더가 각각 다우오피스와 Google 계정에 연결된 것을 확인했어요.", "I confirmed the selected calendars belong to the Daouoffice and Google accounts."),
                           isOn: $model.accountsConfirmed)
                        .font(.caption)
                        .disabled(model.isRunning || (model.pairLocked && model.accountsConfirmed))
                    Text(L("macOS가 서버 주소를 공개하지 않아 계정 이름으로 확인해야 합니다. 서로 다른 두 계정의 캘린더를 선택해 주세요.", "macOS does not expose server addresses. Verify account names and select calendars from two different accounts."))
                        .font(.caption).foregroundStyle(.secondary)
                    if model.pairLocked {
                        Text(L("연결 기록을 보존하기 위해 동기화를 시작한 캘린더 선택은 고정됩니다.", "Calendar selection is locked after syncing begins to preserve matching records."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button(L("첫 동기화 미리보기", "Preview first sync")) { model.runPreview() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!selectionReady || model.isRunning)
                    Button(L("캘린더 새로고침", "Refresh calendars")) { model.refreshCalendars() }
                        .disabled(model.isRunning)
                    if model.isRunning { ProgressView().controlSize(.small) }
                }
                Text(L("조회되지 않는 일정은 보류합니다. 현재 버전은 일정 삭제를 상대 캘린더에 자동으로 반영하지 않습니다.", "Unavailable events are held. This version does not automatically mirror deletions."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if let preview = model.preview {
            GroupBox(L("3. 미리보기", "3. Preview")) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(L("Google에 반영 \(preview.toGoogle)건 · 다우에 반영 \(preview.toDaou)건", "To Google: \(preview.toGoogle) · To Daouoffice: \(preview.toDaou)"))
                    Text(L("중복 의심·충돌 \(preview.conflicts)건 · 보류 \(preview.held)건 · 지원 제외 \(preview.excluded)건", "Possible duplicates/conflicts: \(preview.conflicts) · Held: \(preview.held) · Excluded: \(preview.excluded)"))
                    Text(L("미리보기는 시스템 캘린더를 변경하지 않습니다.", "A preview does not change system calendars."))
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        if model.enabled {
                            Button(L("지금 동기화", "Sync now")) { model.syncNow() }
                            Button(L("일시 중지", "Pause")) { model.setPaused(true) }
                        } else {
                            Button(L("양방향 동기화 시작", "Start two-way sync")) { model.beginSync() }
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
            GroupBox(L("확인이 필요한 일정", "Events needing review")) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.conflicts, id: \.mappingID) { conflict in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(conflictTitle(conflict)).font(.system(size: 12, weight: .semibold))
                            Text(L("다우: \(eventTitle(conflict.daou))", "Daouoffice: \(eventTitle(conflict.daou))"))
                            Text("Google: \(eventTitle(conflict.google))")
                            HStack {
                                Button(L("다우 내용 적용", "Use Daouoffice version")) { model.resolveConflict(conflict, prefer: .daou) }
                                Button(L("Google 내용 적용", "Use Google version")) { model.resolveConflict(conflict, prefer: .google) }
                            }
                            .disabled(model.isRunning || !model.enabled || model.lastSuccessAt == nil)
                        }
                        .font(.caption)
                        if conflict.mappingID != model.conflicts.last?.mappingID { Divider() }
                    }
                    Text(L("미리보기를 확인하고 동기화를 시작한 뒤 선택할 수 있습니다. 선택한 내용을 상대 캘린더에 즉시 반영하며, 직전에 최신 버전을 다시 확인합니다.", "After reviewing the preview and starting sync, choose a version. It is applied to the other calendar immediately after checking the latest event."))
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
                Text(L("마지막 성공: \(displayDate(last))", "Last success: \(displayDate(last))"))
            }
            if let next = model.nextRunAt, model.enabled {
                Text(L("다음 실행: \(displayDate(next))", "Next run: \(displayDate(next))"))
            }
            if let message = model.message {
                Text(visibleMessage(message)).foregroundStyle(.orange)
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
        case .confirmedDeleted: L("삭제됨", "Deleted")
        case .absent: L("없음", "Absent")
        case .unavailable: L("조회할 수 없음", "Unavailable")
        }
    }

    private func conflictTitle(_ conflict: SyncConflict) -> String {
        switch conflict.reason {
        case .simultaneousEdits: L("양쪽에서 모두 수정됨", "Edited on both sides")
        case .editVersusDeletion: L("한쪽 수정 · 한쪽 삭제", "Edited on one side · deleted on the other")
        case .initialPairAmbiguous: L("처음 연결할 중복 의심 일정", "Possible duplicate on first sync")
        }
    }
}
