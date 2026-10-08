import AppKit

public enum LoginLaunch {
    /// Apple's Launch Apple Event Constants: only an explicit login-item launch
    /// qualifies. Manual/reopen/service launches and missing events do not.
    public static func isLoginItem(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event, event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
    }
}
