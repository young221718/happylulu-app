using System.Globalization;

namespace HappyLulu.Core;

// Display-only rounding. Attendance and overtime boundaries use the actual timestamps.
public static class RemainingTimeDisplay
{
    public static string Format(DateTimeOffset departure, DateTimeOffset now, RemainingTimeUnit unit, bool korean)
    {
        double seconds = Math.Max(0, (departure - now).TotalSeconds);
        string Number(double value) => Math.Ceiling(value).ToString("0", CultureInfo.InvariantCulture);
        if (unit == RemainingTimeUnit.Milliseconds) return Number(seconds * 1000) + (korean ? "밀리초" : " ms");
        if (unit == RemainingTimeUnit.Seconds) return Number(seconds) + (korean ? "초" : " s");
        if (unit == RemainingTimeUnit.Minutes) return Number(seconds / 60) + (korean ? "분" : " min");
        if (unit == RemainingTimeUnit.Hours)
        {
            double hours = Math.Ceiling(seconds / 360) / 10;
            return hours.ToString("0.#", CultureInfo.InvariantCulture) + (korean ? "시간" : " h");
        }
        long minutes = (long)Math.Ceiling(seconds / 60);
        return korean ? $"{minutes / 60}시간 {minutes % 60}분" : $"{minutes / 60}h {minutes % 60}m";
    }

    public static int RefreshInterval(RemainingTimeUnit unit, bool countdownActive) =>
        unit == RemainingTimeUnit.Milliseconds && countdownActive ? 100 : 1000;
}
