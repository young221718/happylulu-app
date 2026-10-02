using HappyLulu.Core;

int checks = 0;
void Check(bool condition, string name)
{
    if (!condition) throw new Exception($"FAIL: {name}");
    checks++;
}

DateTimeOffset At(int year, int month, int day, int hour, int minute) =>
    new(year, month, day, hour, minute, 0, TimeSpan.FromHours(9));

var state = new AttendanceState();
var first = At(2026, 10, 2, 8, 30);
Check(Attendance.RecordUnlock(state, first), "first observed unlock records arrival");
Check(!Attendance.RecordUnlock(state, At(2026, 10, 2, 9, 0)), "second unlock does not overwrite first");
Check(Attendance.Today(state, first)?.Time == first, "first arrival retained");
Check(state.LastUnlockAt == At(2026, 10, 2, 9, 0), "last actual unlock retained");
Check(Attendance.Departure(state.Arrivals[Attendance.DayKey(first)], state.Settings) ==
      At(2026, 10, 2, 17, 30), "ordinary day includes work and break");
Check(Attendance.RecordUnlock(state, At(2026, 10, 30, 8, 30)) &&
      Attendance.Departure(state.Arrivals["2026-10-30"], state.Settings) == At(2026, 10, 30, 15, 30),
      "last Friday shortens normal day by two hours");
Check(Attendance.RemainingMinutes(At(2026, 10, 2, 15, 30), At(2026, 10, 2, 15, 29)) == 1,
      "remaining minute rounds up");
Check(!Attendance.RecordUnlock(state, At(2026, 10, 3, 7, 59)), "early unlock is not an arrival");
Check(Attendance.RecordUnlock(state, At(2026, 10, 3, 13, 30)), "afternoon unlock infers morning half day");
Check(Attendance.Today(state, At(2026, 10, 3, 14, 0))?.Mode == WorkdayMode.MorningHalf,
      "morning half day mode persisted");
Check(Attendance.Departure(state.Arrivals["2026-10-03"], state.Settings) == At(2026, 10, 3, 17, 30),
      "half day ends four hours after arrival without break");
Attendance.SkipToday(state, At(2026, 10, 3, 14, 0));
Check(!Attendance.RecordUnlock(state, At(2026, 10, 3, 14, 15)), "day off suppresses later unlocks");
Attendance.SetManual(state, At(2026, 10, 3, 13, 15), At(2026, 10, 3, 14, 20), WorkdayMode.MorningHalf);
Check(!state.SuppressedDays.Contains("2026-10-03"), "manual entry resumes after day off");
Attendance.SetManual(state, At(2026, 10, 4, 9, 0), At(2026, 10, 4, 9, 30), WorkdayMode.AfternoonHalf);
Check(Attendance.Today(state, At(2026, 10, 4, 9, 30))?.Mode == WorkdayMode.AfternoonHalf,
      "afternoon half day can be selected manually");
bool rejected = false;
try { Attendance.SetManual(state, At(2026, 10, 4, 11, 0), At(2026, 10, 4, 12, 0), null); }
catch (ArgumentException) { rejected = true; }
Check(rejected, "out-of-window manual arrival rejected");
rejected = false;
try { Attendance.SetManual(state, At(2026, 10, 4, 9, 45), At(2026, 10, 4, 9, 30), null); }
catch (ArgumentException) { rejected = true; }
Check(rejected, "future manual arrival rejected");
Check(Attendance.IsLastFriday(At(2026, 10, 30, 9, 0)), "last Friday identified");
Check(!Attendance.IsLastFriday(At(2026, 10, 23, 9, 0)), "ordinary Friday identified");

string root = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "happylulu-checks-" + Guid.NewGuid().ToString("N"));
try
{
    var store = new StateStore(System.IO.Path.Combine(root, "state.json"));
    state.Language = UiLanguage.Korean;
    store.Save(state);
    var loaded = store.Load();
    Check(loaded.Arrivals.Count == state.Arrivals.Count && loaded.SuppressedDays.SetEquals(state.SuppressedDays),
          "local state round trip");
    Check(loaded.Language == UiLanguage.Korean, "language preference round trip");
    string original = File.ReadAllText(store.Path);
    var invalid = loaded.Copy();
    invalid.Settings.WorkMinutes = 0;
    rejected = false;
    try { store.Save(invalid); }
    catch (InvalidDataException) { rejected = true; }
    Check(rejected && File.ReadAllText(store.Path) == original, "invalid state preserves saved file");
    File.WriteAllText(store.Path, "{broken");
    rejected = false;
    try { store.Load(); }
    catch (System.Text.Json.JsonException) { rejected = true; }
    Check(rejected && File.ReadAllText(store.Path) == "{broken", "corrupt state is not rewritten");
}
finally
{
    if (Directory.Exists(root)) Directory.Delete(root, true);
}

Console.WriteLine($"HappyLulu Windows core: {checks} checks passed.");
