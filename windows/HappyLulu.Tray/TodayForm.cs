using System.Drawing;
using HappyLulu.Core;

namespace HappyLulu.Tray;

internal sealed class TodayForm : Form
{
    private readonly AppController controller;
    private readonly Label heading = MakeLabel(20, true);
    private readonly Label arrivalLabel = MakeLabel(10);
    private readonly Label departureLabel = MakeLabel(10);
    private readonly Label noteLabel = MakeLabel(9);
    private readonly Label errorLabel = MakeLabel(9);
    private readonly ProgressBar progress = new() { Width = 340, Height = 16, Maximum = 1000 };
    private readonly Button manualButton = new() { AutoSize = true };
    private readonly Button dayOffButton = new() { AutoSize = true };

    public TodayForm(AppController controller, Action showSettings, Icon appIcon)
    {
        this.controller = controller;
        Text = "HappyLulu";
        Icon = appIcon;
        Font = new Font("Segoe UI", 10);
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(380, 340);
        MinimumSize = new Size(400, 380);
        MaximizeBox = false;

        var content = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown,
            WrapContents = false, AutoScroll = true, Padding = new Padding(16)
        };
        Controls.Add(content);
        content.Controls.Add(heading);
        content.Controls.Add(arrivalLabel);
        content.Controls.Add(departureLabel);
        content.Controls.Add(progress);
        content.Controls.Add(noteLabel);
        errorLabel.ForeColor = Color.DarkOrange;
        content.Controls.Add(errorLabel);
        var actions = new FlowLayoutPanel { Width = 350, Height = 42, FlowDirection = FlowDirection.LeftToRight };
        manualButton.Text = Words.T("출근 시각 입력·수정", "Enter/edit arrival");
        manualButton.Click += (_, _) => ShowManualDialog();
        dayOffButton.Text = Words.T("오늘 쉬는 날", "Day off today");
        dayOffButton.Click += (_, _) => SkipToday();
        actions.Controls.Add(manualButton);
        actions.Controls.Add(dayOffButton);
        content.Controls.Add(actions);
        var settingsButton = new Button { Text = Words.T("설정 열기", "Open settings"), AutoSize = true };
        settingsButton.Click += (_, _) => showSettings();
        content.Controls.Add(settingsButton);
        FormClosing += (_, args) =>
        {
            if (args.CloseReason == CloseReason.UserClosing)
            {
                args.Cancel = true;
                Hide();
            }
        };
        RefreshView();
    }

    private static Label MakeLabel(int size, bool bold = false) => new()
    {
        AutoSize = false, Width = 345, Height = size >= 20 ? 58 : 36,
        Font = new Font("Segoe UI", size, bold ? FontStyle.Bold : FontStyle.Regular)
    };

    public void RefreshView()
    {
        DateTimeOffset now = DateTimeOffset.Now;
        Arrival? arrival = Attendance.Today(controller.State, now);
        bool skipped = controller.State.SuppressedDays.Contains(Attendance.DayKey(now));
        if (arrival is null)
        {
            heading.Text = skipped ? Words.T("오늘은 쉬어가요", "Taking today off")
                                   : Words.T("출근 기록 대기", "Waiting for arrival");
            arrivalLabel.Text = skipped ? Words.T("자동 기록을 쉬고 있어요.", "Automatic recording is paused today.")
                                        : Words.T("실제 세션 잠금 해제를 기다려요.", "Waiting for an actual session unlock.");
            departureLabel.Text = Words.T("출근: —     퇴근 예정: —", "Arrival: —     Estimated leave: —");
            progress.Value = 0;
        }
        else
        {
            DateTimeOffset leave = Attendance.Departure(arrival, controller.State.Settings);
            int left = Attendance.RemainingMinutes(leave, now);
            heading.Text = left == 0 ? Words.T("오늘도 수고했어요", "Time to go home")
                                     : Words.Duration(left) + Words.T(" 남았어요", " to go");
            arrivalLabel.Text = $"{Words.T("출근", "Arrival")}: {arrival.Time:HH:mm} · {Words.Mode(arrival.Mode)} · " +
                (arrival.Source == ArrivalSource.Unlock ? Words.T("잠금 해제", "Unlock") : Words.T("직접 입력", "Manual"));
            departureLabel.Text = $"{Words.T("퇴근 예정", "Estimated leave")}: {leave:HH:mm}";
            progress.Value = (int)Math.Round(Attendance.Progress(arrival, leave, now) * 1000);
        }
        noteLabel.Text = Words.T("일반·오후 반차 08:00–10:00 · 오전 반차 13:00–15:00",
                                "Full day/afternoon off 08:00–10:00 · morning off 13:00–15:00");
        errorLabel.Text = controller.Error ?? "";
        dayOffButton.Enabled = !skipped;
    }

    private void SkipToday()
    {
        var answer = MessageBox.Show(this,
            Words.T("오늘 기록을 지우고 다음 잠금 해제도 기록하지 않을까요?", "Clear today's arrival and skip later unlocks today?"),
            Words.T("오늘 쉬는 날", "Day off today"), MessageBoxButtons.YesNo, MessageBoxIcon.Question);
        if (answer != DialogResult.Yes) return;
        if (!controller.SkipToday()) ShowError();
    }

    private void ShowManualDialog()
    {
        using var dialog = new Form
        {
            Text = Words.T("출근 시각", "Arrival time"), StartPosition = FormStartPosition.CenterParent,
            ClientSize = new Size(340, 180), FormBorderStyle = FormBorderStyle.FixedDialog,
            MaximizeBox = false, MinimizeBox = false, Font = Font
        };
        Arrival? existingArrival = Attendance.Today(controller.State, DateTimeOffset.Now);
        var time = new DateTimePicker
        {
            Format = DateTimePickerFormat.Time, ShowUpDown = true,
            Value = existingArrival?.Time.LocalDateTime ?? DateTime.Now,
            Left = 18, Top = 22, Width = 300
        };
        var mode = new ComboBox { Left = 18, Top = 65, Width = 300, DropDownStyle = ComboBoxStyle.DropDownList };
        mode.Items.AddRange(new object[]
        {
            new ModeChoice(null, Words.T("출근 시각으로 자동 판단", "Infer from arrival time")),
            new ModeChoice(WorkdayMode.Normal, Words.Mode(WorkdayMode.Normal)),
            new ModeChoice(WorkdayMode.MorningHalf, Words.Mode(WorkdayMode.MorningHalf)),
            new ModeChoice(WorkdayMode.AfternoonHalf, Words.Mode(WorkdayMode.AfternoonHalf))
        });
        mode.SelectedIndex = existingArrival?.Mode switch
        {
            WorkdayMode.Normal => 1,
            WorkdayMode.MorningHalf => 2,
            WorkdayMode.AfternoonHalf => 3,
            _ => 0
        };
        var cancel = new Button { Text = Words.T("취소", "Cancel"), Left = 150, Top = 120, Width = 80,
                                  DialogResult = DialogResult.Cancel };
        var save = new Button { Text = Words.T("저장", "Save"), Left = 238, Top = 120, Width = 80 };
        save.Click += (_, _) =>
        {
            DateTime local = DateTime.Today.Add(time.Value.TimeOfDay);
            var at = new DateTimeOffset(local, TimeZoneInfo.Local.GetUtcOffset(local));
            if (controller.ManualArrival(at, ((ModeChoice)mode.SelectedItem!).Mode)) dialog.Close();
            else ShowError();
        };
        dialog.Controls.AddRange(new Control[] { time, mode, cancel, save });
        dialog.CancelButton = cancel;
        dialog.AcceptButton = save;
        dialog.ShowDialog(this);
    }

    private void ShowError() => MessageBox.Show(this, controller.Error ?? Words.T("저장할 수 없어요.", "Could not save."),
        "HappyLulu", MessageBoxButtons.OK, MessageBoxIcon.Warning);

    private sealed record ModeChoice(WorkdayMode? Mode, string Label)
    {
        public override string ToString() => Label;
    }
}
