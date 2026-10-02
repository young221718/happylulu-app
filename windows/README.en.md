# HappyLulu for Windows 1.0.0

HappyLulu runs in the Windows notification area. Left-click its icon for today's arrival, estimated departure, manual entry, and day-off action. Right-click to open the separate Settings window or exit. In Settings, choose System, Korean, or English; the preference is saved locally and the open windows and tray text refresh.

While the app is running, the first actual Windows `SessionUnlock` event in the allowed arrival window is recorded. Full days use 08:00–10:00; a morning off uses 13:00–15:00. An afternoon off can be selected with manual entry. The app does not reconstruct earlier unlocks or treat startup, wake, or a session change alone as an arrival. Day off clears today's arrival and suppresses later unlocks until a manual entry resumes recording.

Records stay in `%LOCALAPPDATA%\HappyLulu\state.json`. If the file cannot be read, the app preserves it and disables saving. Settings includes work and break duration, recent arrivals, and an optional Start with Windows switch. The switch changes the current user's Run registry entry only when selected. If you move the portable executable, set startup again.

Calendar sync and in-app automatic updates are not included in Windows 1.0.0.

## Build and check

Run with the .NET 10 SDK on Windows:

```powershell
dotnet run --project windows/HappyLulu.Checks/HappyLulu.Checks.csproj -c Release
dotnet publish windows/HappyLulu.Tray/HappyLulu.Tray.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:PublishTrimmed=false -p:DebugType=None -p:DebugSymbols=false -o dist/windows/self-contained
dotnet publish windows/HappyLulu.Tray/HappyLulu.Tray.csproj -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true -p:PublishTrimmed=false -p:DebugType=None -p:DebugSymbols=false -o dist/windows/runtime-required
```

`HappyLulu-1.0.0-windows-x64.zip` includes the runtime. The smaller `HappyLulu-1.0.0-windows-x64-runtime-required.zip` requires the **.NET 10 Desktop Runtime x64** on the target PC. Extract either ZIP and run `HappyLulu.exe`. CI builds both ZIPs and checks that the runtime-required ZIP stays below 25 MiB.

Core checks and a successful build do not prove real session unlock detection, tray display, startup after sign-in, or execution with an installed runtime. Verify these on Windows separately.
