using System.Drawing;
using System.Drawing.Drawing2D;
using System.Reflection;
using System.Runtime.InteropServices;

namespace HappyLulu.Tray;

internal static class AppIcon
{
    public static Icon Load()
    {
        using Stream image = Assembly.GetExecutingAssembly().GetManifestResourceStream("HappyLulu.Icon.png")
            ?? throw new InvalidOperationException("HappyLulu icon resource is missing.");
        using var source = new Bitmap(image);
        using var scaled = new Bitmap(64, 64);
        using (Graphics graphics = Graphics.FromImage(scaled))
        {
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.DrawImage(source, 0, 0, 64, 64);
        }
        IntPtr handle = scaled.GetHicon();
        try
        {
            using Icon temporary = Icon.FromHandle(handle);
            return (Icon)temporary.Clone();
        }
        finally { DestroyIcon(handle); }
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr handle);
}
