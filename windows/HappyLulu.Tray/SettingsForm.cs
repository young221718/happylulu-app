using System.Drawing;
using HappyLulu.Core;

namespace HappyLulu.Tray;

internal sealed class SettingsForm : Form
{
    private readonly AppController controller;
    private readonly ComboBox language = new() { Width = 250, DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly CheckBox startup = new() { AutoSize = true };
    private readonly Label startupHint = new() { AutoSize = true, MaximumSize = new Size(510, 0) };
    private readonly TextBox dataPath = new() { ReadOnly = true, Width = 500 };
    private readonly NumericUpDown work = new() { Minimum = 60, Maximum = 960, Increment = 30, Width = 120 };
    private readonly NumericUpDown rest = new() { Minimum = 0, Maximum = 240, Increment = 15, Width = 120 };
    private readonly ListView history = new() { Dock = DockStyle.Fill, View = View.Details, FullRowSelect = true };
    private readonly Label error = new() { Dock = DockStyle.Bottom, Height = 48, ForeColor = Color.DarkOrange };
    private bool refreshing;
    private bool settingsLoaded;

    public SettingsForm(AppController controller, Icon appIcon)
    {
        this.controller = controller;
        Text = Words.T("HappyLulu 설정", "HappyLulu Settings");
        Icon = appIcon;
        Font = new Font("Segoe UI", 10);
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(570, 490);
        MinimumSize = new Size(570, 450);
        var tabs = new TabControl { Dock = DockStyle.Fill };
        tabs.TabPages.Add(GeneralPage());
        tabs.TabPages.Add(WorkPage());
        tabs.TabPages.Add(HistoryPage());
        Controls.Add(tabs);
        Controls.Add(error);
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

    private TabPage GeneralPage()
    {
        var page = new TabPage(Words.T("일반", "General"));
        var stack = Stack();
        page.Controls.Add(stack);
        stack.Controls.Add(new Label
        {
            Text = "HappyLulu Windows 1.0.0", Font = new Font(Font, FontStyle.Bold),
            AutoSize = true
        });
        stack.Controls.Add(new Label { Text = Words.T("표시 언어", "Display language"), AutoSize = true });
        language.Items.AddRange(new object[]
        {
            Words.T("시스템 언어", "System language"), "한국어", "English"
        });
        language.SelectedIndexChanged += (_, _) =>
        {
            if (refreshing || language.SelectedIndex < 0) return;
            if (!controller.SetLanguage((UiLanguage)language.SelectedIndex))
            {
                refreshing = true;
                language.SelectedIndex = (int)controller.State.Language;
                refreshing = false;
            }
        };
        stack.Controls.Add(language);
        startup.Text = Words.T("Windows 로그인 시 자동 실행", "Start when signing in to Windows");
        startup.CheckedChanged += (_, _) =>
        {
            if (refreshing) return;
            try
            {
                StartupRegistration.SetEnabled(startup.Checked);
                startupHint.Text = Words.T("자동 실행 설정을 저장했습니다.", "Startup preference saved.");
            }
            catch (Exception ex)
            {
                startupHint.Text = ex.Message;
                SyncStartup();
            }
        };
        stack.Controls.Add(startup);
        startupHint.Text = Words.T("이 앱 파일을 옮기면 자동 실행을 다시 설정해야 합니다.",
                                   "Set startup again if you move this portable app.");
        stack.Controls.Add(startupHint);
        stack.Controls.Add(new Label { Text = Words.T("로컬 기록 파일", "Local attendance file"), AutoSize = true });
        dataPath.Text = controller.DataPath;
        stack.Controls.Add(dataPath);
        stack.Controls.Add(new Label
        {
            Text = Words.T("기록은 이 PC에만 저장됩니다. 창을 열어도 자동 실행 설정은 바뀌지 않습니다.",
                           "Records stay on this PC. Opening Settings does not change startup."),
            AutoSize = true, MaximumSize = new Size(510, 0)
        });
        return page;
    }

    private TabPage WorkPage()
    {
        var page = new TabPage(Words.T("근무", "Work"));
        var stack = Stack();
        page.Controls.Add(stack);
        stack.Controls.Add(new Label { Text = Words.T("근무 시간 (분)", "Work minutes"), AutoSize = true });
        stack.Controls.Add(work);
        stack.Controls.Add(new Label { Text = Words.T("휴게 시간 (분)", "Break minutes"), AutoSize = true });
        stack.Controls.Add(rest);
        var apply = new Button { Text = Words.T("근무 시간 저장", "Save work hours"), AutoSize = true };
        apply.Click += (_, _) =>
        {
            if (!controller.SetWork((int)work.Value, (int)rest.Value))
                MessageBox.Show(this, controller.Error ?? Words.T("저장할 수 없어요.", "Could not save."),
                    "HappyLulu", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        };
        stack.Controls.Add(apply);
        stack.Controls.Add(new Label
        {
            Text = Words.T("일반 근무는 근무·휴게 시간을 더합니다. 매달 마지막 금요일은 2시간 일찍 끝납니다. 반차는 휴게 없이 4시간이며 마지막 금요일 단축과 겹치지 않습니다.",
                           "Full days include work and break. The last Friday ends 2 hours early. Half days last 4 hours without a break or last-Friday reduction."),
            AutoSize = true, MaximumSize = new Size(510, 0)
        });
        return page;
    }

    private TabPage HistoryPage()
    {
        var page = new TabPage(Words.T("최근 기록", "Recent history"));
        history.Columns.Add(Words.T("날짜", "Date"), 125);
        history.Columns.Add(Words.T("출근", "Arrival"), 90);
        history.Columns.Add(Words.T("유형", "Mode"), 145);
        history.Columns.Add(Words.T("기록 방식", "Source"), 130);
        page.Controls.Add(history);
        return page;
    }

    private static FlowLayoutPanel Stack() => new()
    {
        Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown,
        WrapContents = false, AutoScroll = true, Padding = new Padding(20)
    };

    public void RefreshView()
    {
        if (!settingsLoaded)
        {
            SyncStartup();
            refreshing = true;
            language.SelectedIndex = (int)controller.State.Language;
            work.Value = controller.State.Settings.WorkMinutes;
            rest.Value = controller.State.Settings.BreakMinutes;
            refreshing = false;
            settingsLoaded = true;
        }

        history.BeginUpdate();
        try
        {
            history.Items.Clear();
            foreach (Arrival arrival in controller.State.Arrivals.Values.OrderByDescending(a => a.Day).Take(30))
            {
                var item = new ListViewItem(arrival.Day);
                item.SubItems.Add(arrival.Time.ToString("HH:mm"));
                item.SubItems.Add(Words.Mode(arrival.Mode));
                item.SubItems.Add(arrival.Source == ArrivalSource.Unlock
                    ? Words.T("잠금 해제", "Unlock") : Words.T("직접 입력", "Manual"));
                history.Items.Add(item);
            }
        }
        finally { history.EndUpdate(); }
        error.Text = controller.Error ?? "";
    }

    private void SyncStartup()
    {
        refreshing = true;
        try { startup.Checked = StartupRegistration.Enabled(); }
        catch (Exception ex) { startupHint.Text = ex.Message; }
        finally { refreshing = false; }
    }
}
