import AppKit

// A disposable app, separate from HappyLulu and its attendance/preferences.
@MainActor
final class ProbeDelegate: NSObject, NSApplicationDelegate {
    var observed = false
    func applicationWillFinishLaunching(_ notification: Notification) {
        observed = LoginLaunch.isLoginItem(NSAppleEventManager.shared().currentAppleEvent)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        observed = observed || LoginLaunch.isLoginItem(NSAppleEventManager.shared().currentAppleEvent)
        let args = CommandLine.arguments
        let output = URL(fileURLWithPath: args[args.firstIndex(of: "--result")! + 1])
        do { try String(observed).write(to: output, atomically: true, encoding: .utf8) }
        catch { exit(2) }
        NSApplication.shared.terminate(nil)
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
if let index = CommandLine.arguments.firstIndex(of: "--launch") {
    let args = CommandLine.arguments
    let bundle = URL(fileURLWithPath: args[index + 1])
    let output = args[index + 2]
    let kind = args[index + 3]
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.createsNewApplicationInstance = true
    configuration.arguments = ["--result", output]
    if kind != "manual" {
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication), targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(enumCode: kind == "login" ? OSType(keyAELaunchedAsLogInItem) : OSType(keyAELaunchedAsServiceItem)),
                       forKeyword: AEKeyword(keyAEPropData))
        configuration.appleEvent = event
    }
    NSWorkspace.shared.openApplication(at: bundle, configuration: configuration) { _, error in
        if let error { fputs("Probe launch failed: \(error.localizedDescription)\n", stderr); exit(2) }
        exit(0)
    }
    application.run()
} else {
    let delegate = ProbeDelegate()
    application.delegate = delegate
    application.run()
}
