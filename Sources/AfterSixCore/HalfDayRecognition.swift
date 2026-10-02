import Foundation

public enum HalfDayRecognition {
    /// Only explicit morning/afternoon titles count. Conflicting or ambiguous
    /// events leave the choice to the user instead of guessing a work schedule.
    public static func mode(from titles: [String]) -> WorkdayMode? {
        var found = Set<WorkdayMode>()
        for title in titles {
            let compact = title.replacingOccurrences(of: "\\s|[()\\[\\]{}]", with: "", options: .regularExpression)
                .lowercased()
            if compact.contains("취소") || compact.contains("cancel") { continue }
            let morning = compact.contains("오전반차") || compact.contains("반차오전") ||
                compact.contains("morninghalfday") || compact.contains("halfdayam")
            let afternoon = compact.contains("오후반차") || compact.contains("반차오후") ||
                compact.contains("afternoonhalfday") || compact.contains("halfdaypm")
            if morning { found.insert(.morningHalf) }
            if afternoon { found.insert(.afternoonHalf) }
        }
        return found.count == 1 ? found.first : nil
    }
}
