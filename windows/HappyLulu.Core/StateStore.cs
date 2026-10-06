using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace HappyLulu.Core;

public sealed class StateStore(string path)
{
    public string Path { get; } = path;
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };

    public static StateStore Standard()
    {
        string appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (string.IsNullOrWhiteSpace(appData))
            throw new InvalidOperationException("Local application data folder is unavailable.");
        return new StateStore(System.IO.Path.Combine(appData, "HappyLulu", "state.json"));
    }

    public AttendanceState Load()
    {
        if (!File.Exists(Path)) return new AttendanceState();
        var state = JsonSerializer.Deserialize<AttendanceState>(File.ReadAllText(Path), JsonOptions)
                    ?? throw new InvalidDataException("Attendance file is empty.");
        Validate(state);
        return state;
    }

    public void Save(AttendanceState state)
    {
        Validate(state);
        string directory = System.IO.Path.GetDirectoryName(Path)
                           ?? throw new InvalidOperationException("Attendance path has no directory.");
        Directory.CreateDirectory(directory);
        string temporary = Path + "." + Guid.NewGuid().ToString("N", CultureInfo.InvariantCulture) + ".tmp";
        try
        {
            File.WriteAllText(temporary, JsonSerializer.Serialize(state, JsonOptions));
            File.Move(temporary, Path, true);
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }

    public static void Validate(AttendanceState state)
    {
        if (state.Version != 1 || state.Settings is null || !state.Settings.IsValid ||
            !Enum.IsDefined(state.Language) || !Enum.IsDefined(state.RemainingTimeUnit) ||
            state.Arrivals is null || state.SuppressedDays is null)
            throw new InvalidDataException("Attendance file has invalid settings or version.");
        foreach (var (key, arrival) in state.Arrivals)
        {
            if (arrival is null || !DateOnly.TryParseExact(key, "yyyy-MM-dd", CultureInfo.InvariantCulture,
                    DateTimeStyles.None, out _) || arrival.Day != key ||
                Attendance.DayKey(arrival.Time) != key ||
                !Enum.IsDefined(arrival.Source) || !Enum.IsDefined(arrival.Mode))
                throw new InvalidDataException("Attendance file has an invalid arrival.");
        }
        foreach (string day in state.SuppressedDays)
            if (!DateOnly.TryParseExact(day, "yyyy-MM-dd", CultureInfo.InvariantCulture,
                    DateTimeStyles.None, out _))
                throw new InvalidDataException("Attendance file has an invalid skipped day.");
    }
}
