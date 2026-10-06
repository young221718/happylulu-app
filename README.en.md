# HappyLulu


The latest version is **Mac 1.5.4 build12**, with extra elapsed minutes after 30 minutes and the meal time threshold two hours after scheduled departure. This does not verify work or approve payment. Selectable countdown units are also included.

[Mac release notes (Korean)](RELEASE-NOTES.md) · [Windows release notes (Korean)](windows/RELEASE-NOTES.md)

[한국어](README.md) · [Website](https://happylulu.cy-choi-lulu.chatgpt.site/en/)

A small local attendance companion for LuluLab colleagues. Your first valid unlock records arrival; the menu bar or system tray shows when you can go home. This is not the company's official attendance or payroll system.

## Get started

**Mac:** download the DMG or ZIP from the website, quit your existing copy, move HappyLulu to Applications and open it. Replacing the app retains the existing `AfterSix` records. Click the smiling clock; enter your arrival manually if you have already arrived. Settings opens in a separate window. Choose System, Korean or English under Language.

**Windows:** see [Windows setup](windows/README.en.md). The initial edition includes a tray, separate settings, manual arrival, half days, local records and Korean/English UI. Calendar sync is currently Mac-only. Mac and Windows do not share attendance records.

On Mac, the first launch attempts login-item registration and may require system approval. Turning it off keeps it off. On Windows, startup is an explicit settings choice.

## Workday rules

| Mode | Arrival window | Default example |
| --- | --- | --- |
| Regular | 08:00–10:00 inclusive of the last minute | 09:00 → 18:00 |
| Afternoon off | 08:00–10:00 inclusive of the last minute | 09:00 → 13:00 |
| Morning off | 13:00–15:00 inclusive of the last minute | 13:00 → 17:00 |

Regular days include eight work hours plus one break hour by default. The last calendar Friday of each month subtracts two hours. Half days always use four hours without breaks or the Friday reduction. Manual workday selection takes priority over inference. Future arrivals are rejected, and later unlocks do not overwrite the day's arrival.

Day off removes today's arrival after confirmation and suspends automatic recording. Saving a manual arrival resumes it. Wake, login or session activation alone does not create an arrival. Closed-app history cannot be reconstructed; an unlock at home may count as arrival.

## Calendar beta on Mac

Add your own Google and CalDAV accounts in macOS Internet Accounts. Use the company's server-copy button in HappyLulu Calendar, and confirm calendars appear in Apple's Calendar app. Select empty test calendars from different accounts, review the initial preview, then enable sync.

Ordinary event additions and edits, including all-day events, are supported. Deletions, recurrence, invitations, reminders and unsupported fields are skipped. Review conflicts and verify changes on both calendar websites. [Full calendar contract and recovery notes (Korean)](CALENDAR.md).

Optional half-day recognition reads all accessible calendar titles. Shared events belonging to someone else may be mistaken for yours. Use a manual mode or turn recognition off when needed.

## Updates and verification

Updates are installed manually. Signed automatic-update activation is paused. Apple notarization and Windows publisher signing are not complete. Intel Mac physical testing is deferred. Follow your company's software policy on managed computers.

Mac records stay in `~/Library/Application Support/AfterSix/state.json`; no attendance telemetry or keyboard/screen collection is added. The Windows storage path and build commands are documented in its own README. Do not delete or replace state files to update the application.

[Validation evidence and remaining device tests (Korean)](VALIDATION.md) · [Update status (Korean)](UPDATES.md).

Countdown display in Settings supports milliseconds, seconds, minutes, hours, and hours/minutes (default). Values round up to the selected unit in both the menu bar and today panel. Milliseconds refresh every 0.1 seconds during the countdown; other modes refresh every second. The choice persists after restart.
