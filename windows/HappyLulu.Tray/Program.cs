using System.Globalization;
using System.Security.Principal;
using HappyLulu.Core;

namespace HappyLulu.Tray;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        string user = WindowsIdentity.GetCurrent().User?.Value ?? Environment.UserName;
        using var instance = new Mutex(true, @"Local\HappyLulu-" + user, out bool firstInstance);
        if (!firstInstance)
        {
            MessageBox.Show(Words.T("HappyLulu가 이미 실행 중입니다. 알림 영역 아이콘을 확인해 주세요.",
                                    "HappyLulu is already running. Check the notification area."),
                            "HappyLulu", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        Application.Run(new TrayContext());
    }
}

internal static class Words
{
    public static UiLanguage Preference { get; set; } = UiLanguage.System;
    public static bool Korean => Preference == UiLanguage.Korean ||
        (Preference == UiLanguage.System && CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "ko");
    public static string T(string korean, string english) => Korean ? korean : english;
    public static string Mode(WorkdayMode mode) => mode switch
    {
        WorkdayMode.Normal => T("일반 근무", "Full day"),
        WorkdayMode.MorningHalf => T("오전 반차", "Morning off"),
        WorkdayMode.AfternoonHalf => T("오후 반차", "Afternoon off"),
        _ => throw new ArgumentOutOfRangeException(nameof(mode))
    };
    public static string Duration(int minutes) => Korean
        ? $"{minutes / 60}시간 {minutes % 60}분"
        : $"{minutes / 60}h {minutes % 60}m";
}
