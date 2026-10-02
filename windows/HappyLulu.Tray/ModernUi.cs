using System.ComponentModel;
using System.Drawing;
using System.Drawing.Drawing2D;

namespace HappyLulu.Tray;

internal static class UiPalette
{
    public static readonly Color Page = Color.FromArgb(247, 250, 249);
    public static readonly Color Card = Color.White;
    public static readonly Color MintWash = Color.FromArgb(232, 246, 240);
    public static readonly Color Mint = Color.FromArgb(32, 112, 99);
    public static readonly Color MintDeep = Color.FromArgb(24, 88, 79);
    public static readonly Color Ink = Color.FromArgb(28, 49, 45);
    public static readonly Color Muted = Color.FromArgb(77, 99, 93);
    public static readonly Color Border = Color.FromArgb(220, 233, 227);
    public static readonly Color Warning = Color.FromArgb(143, 78, 25);
}

internal sealed class RoundedCard : Panel
{
    public Color Surface { get; }

    public RoundedCard(Color surface)
    {
        Surface = surface;
        BackColor = surface;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
    }

    protected override void OnPaintBackground(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.Clear(Parent?.BackColor ?? UiPalette.Page);
        using GraphicsPath path = RoundedPath(new RectangleF(0.5f, 0.5f, Width - 1, Height - 1), 17);
        using var brush = new SolidBrush(Surface);
        using var border = new Pen(UiPalette.Border);
        e.Graphics.FillPath(brush, path);
        e.Graphics.DrawPath(border, path);
    }

    internal static GraphicsPath RoundedPath(RectangleF bounds, float radius)
    {
        float diameter = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }
}

internal sealed class MintProgressTrack : Control
{
    private double fraction;

    [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public double Fraction
    {
        get => fraction;
        set
        {
            fraction = Math.Clamp(value, 0, 1);
            AccessibleDescription = $"{fraction:P0}";
            Invalidate();
        }
    }

    public MintProgressTrack()
    {
        Height = 9;
        AccessibleRole = AccessibleRole.ProgressBar;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using GraphicsPath track = RoundedCard.RoundedPath(new RectangleF(0, 0, Width, Height), Height / 2f);
        using var baseBrush = new SolidBrush(UiPalette.Border);
        e.Graphics.FillPath(baseBrush, track);
        float filled = (float)(Width * fraction);
        if (filled < Height) return;
        using GraphicsPath fill = RoundedCard.RoundedPath(new RectangleF(0, 0, filled, Height), Height / 2f);
        using var fillBrush = new SolidBrush(UiPalette.Mint);
        e.Graphics.FillPath(fillBrush, fill);
    }
}
