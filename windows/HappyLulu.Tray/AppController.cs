using HappyLulu.Core;
using Microsoft.Win32;

namespace HappyLulu.Tray;

internal sealed class AppController
{
    private readonly StateStore? store;
    private AttendanceState state = new();
    private bool writable;
    public string? Error { get; private set; }
    public AttendanceState State => state;
    public string DataPath => store?.Path ?? "";
    public event Action? Changed;

    public AppController()
    {
        try
        {
            store = StateStore.Standard();
            state = store.Load();
            writable = true;
        }
        catch (Exception ex)
        {
            // The original file remains untouched. A failed load never starts a new history.
            Error = Words.T("기록 파일을 읽지 못해 저장을 중지했습니다: ",
                            "Could not read attendance; saving is disabled: ") + ex.Message;
        }
    }

    public bool Apply(Action<AttendanceState> change)
    {
        if (!writable || store is null) return false;
        try
        {
            AttendanceState candidate = state.Copy();
            change(candidate);
            store.Save(candidate);
            state = candidate;
            Error = null;
            Changed?.Invoke();
            return true;
        }
        catch (Exception ex)
        {
            Error = ex is ArgumentException
                ? Words.T("오늘의 지난 출근 시각을 입력해 주세요. 일반·오후 반차는 08:00~10:00, 오전 반차는 13:00~15:00입니다.",
                          "Enter a past arrival today: 08:00–10:00 for full day/afternoon off, 13:00–15:00 for morning off.")
                : ex.Message;
            Changed?.Invoke();
            return false;
        }
    }

    public void ObservedUnlock(DateTimeOffset at) => Apply(candidate => Attendance.RecordUnlock(candidate, at));
    public bool ManualArrival(DateTimeOffset at, WorkdayMode? mode) =>
        Apply(candidate => Attendance.SetManual(candidate, at, DateTimeOffset.Now, mode));
    public bool SkipToday() => Apply(candidate => Attendance.SkipToday(candidate, DateTimeOffset.Now));
    public bool SetWork(int work, int rest) => Apply(candidate =>
    {
        candidate.Settings.WorkMinutes = work;
        candidate.Settings.BreakMinutes = rest;
    });
    public bool SetRemainingTimeUnit(RemainingTimeUnit unit) => Apply(candidate => candidate.RemainingTimeUnit = unit);
    public bool SetLanguage(UiLanguage language) => Apply(candidate => candidate.Language = language);
}

internal static class StartupRegistration
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "HappyLulu";
    private static string Command => $"\"{Application.ExecutablePath}\"";

    public static bool Enabled()
    {
        using RegistryKey? key = Registry.CurrentUser.OpenSubKey(RunKey);
        return string.Equals(key?.GetValue(ValueName) as string, Command, StringComparison.OrdinalIgnoreCase);
    }

    public static void SetEnabled(bool enabled)
    {
        using RegistryKey key = Registry.CurrentUser.CreateSubKey(RunKey, true)
            ?? throw new InvalidOperationException("Windows startup settings are unavailable.");
        if (enabled) key.SetValue(ValueName, Command, RegistryValueKind.String);
        else key.DeleteValue(ValueName, false);
    }
}
