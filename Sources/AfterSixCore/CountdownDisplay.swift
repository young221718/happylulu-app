import Foundation

public enum CountdownDisplay: String, CaseIterable, Sendable {
    case milliseconds, seconds, minutes, hours, hoursMinutes

    private static let preferenceKey = "HappyLuluCountdownDisplay"

    public static func saved(in defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: preferenceKey) ?? "") ?? .hoursMinutes
    }

    public func save(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.preferenceKey)
    }

    public var refreshInterval: TimeInterval { self == .milliseconds ? 0.1 : 1 }

    /// Round up to the chosen unit; hours use tenths so a positive remainder stays visible.
    public func text(seconds remaining: TimeInterval, korean: Bool) -> String {
        let seconds = remaining.isFinite ? min(72_000, max(0, remaining)) : 0
        switch self {
        case .milliseconds: return "\(Int(ceil(seconds * 1000)))" + (korean ? "밀리초" : " ms")
        case .seconds: return "\(Int(ceil(seconds)))" + (korean ? "초" : " sec")
        case .minutes: return "\(Int(ceil(seconds / 60)))" + (korean ? "분" : " min")
        case .hours:
            let tenths = Int(ceil(seconds / 360))
            let number = tenths % 10 == 0 ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
            return number + (korean ? "시간" : " hr")
        case .hoursMinutes:
            let minutes = Int(ceil(seconds / 60))
            if minutes < 60 { return "\(minutes)" + (korean ? "분" : " min") }
            let hours = "\(minutes / 60)" + (korean ? "시간" : " hr")
            return minutes % 60 == 0 ? hours : hours + " \(minutes % 60)" + (korean ? "분" : " min")
        }
    }
}
