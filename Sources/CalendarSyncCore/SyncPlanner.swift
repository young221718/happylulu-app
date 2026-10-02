import Foundation

public enum SyncDecision: Codable, Equatable, Sendable {
    /// Both sides already agree; persist this baseline without a remote write.
    case settled(SyncBaseline)
    /// Persist the operation before applying it, then persist newBaseline only
    /// after the provider acknowledges the conditional write.
    case operation(SyncOperation, newBaseline: SyncBaseline)
    case conflict(SyncConflict)
    case held(SyncHoldReason)
}

public enum SyncPlanner {
    public static func plan(
        mapping: CalendarMapping,
        daou: CalendarObservation,
        google: CalendarObservation
    ) -> SyncDecision {
        guard isComplete(daou), isComplete(google) else {
            return .held(.incompleteObservation)
        }

        for (side, observation) in [(CalendarSide.daou, daou), (.google, google)] {
            guard case let .present(event) = observation else { continue }
            if let mappedID = mapping.eventID(on: side), mappedID != event.id {
                return .held(.identityMismatch)
            }
            if let exclusion = event.exclusion {
                return .held(.excludedEvent(exclusion))
            }
        }

        if mapping.baseline != nil,
           (mapping.daouEventID == nil || mapping.googleEventID == nil) {
            return .held(.incompleteMapping)
        }

        switch mapping.baseline {
        case nil:
            return planInitial(mapping: mapping, daou: daou, google: google)
        case .deleted:
            if isDeleted(daou) && isDeleted(google) { return .settled(.deleted) }
            return .held(.tombstoneResurrection)
        case let .content(previous):
            return planMapped(mapping: mapping, previous: previous, daou: daou, google: google)
        }
    }

    private static func planInitial(
        mapping: CalendarMapping,
        daou: CalendarObservation,
        google: CalendarObservation
    ) -> SyncDecision {
        switch (daou, google) {
        case let (.present(source), .absent) where mapping.googleEventID == nil:
            return .operation(.create(mappingID: mapping.id, target: .google, sourceEventID: source.id, content: source.content), newBaseline: .content(source.content))
        case let (.absent, .present(source)) where mapping.daouEventID == nil:
            return .operation(.create(mappingID: mapping.id, target: .daou, sourceEventID: source.id, content: source.content), newBaseline: .content(source.content))
        case (.present, .present):
            return .conflict(SyncConflict(mappingID: mapping.id, reason: .initialPairAmbiguous, baseline: nil, daou: daou, google: google))
        case (.absent, .absent):
            return .held(.unverifiedAbsence)
        default:
            return .held(.unverifiedAbsence)
        }
    }

    private static func planMapped(
        mapping: CalendarMapping,
        previous: CalendarEventContent,
        daou: CalendarObservation,
        google: CalendarObservation
    ) -> SyncDecision {
        if isAbsent(daou) || isAbsent(google) { return .held(.unverifiedAbsence) }

        switch (daou, google) {
        case let (.present(d), .present(g)):
            if d.content == g.content { return .settled(.content(d.content)) }
            let daouChanged = d.content != previous
            let googleChanged = g.content != previous
            if daouChanged && !googleChanged {
                guard !g.version.isEmpty else { return .held(.missingVersion) }
                return .operation(.update(mappingID: mapping.id, target: .google, targetEventID: g.id, expectedVersion: g.version, content: d.content), newBaseline: .content(d.content))
            }
            if googleChanged && !daouChanged {
                guard !d.version.isEmpty else { return .held(.missingVersion) }
                return .operation(.update(mappingID: mapping.id, target: .daou, targetEventID: d.id, expectedVersion: d.version, content: g.content), newBaseline: .content(g.content))
            }
            return conflict(.simultaneousEdits, mapping: mapping, daou: daou, google: google)
        case let (.confirmedDeleted, .present(g)):
            if g.content != previous { return conflict(.editVersusDeletion, mapping: mapping, daou: daou, google: google) }
            guard !g.version.isEmpty else { return .held(.missingVersion) }
            return .operation(.delete(mappingID: mapping.id, target: .google, targetEventID: g.id, expectedVersion: g.version), newBaseline: .deleted)
        case let (.present(d), .confirmedDeleted):
            if d.content != previous { return conflict(.editVersusDeletion, mapping: mapping, daou: daou, google: google) }
            guard !d.version.isEmpty else { return .held(.missingVersion) }
            return .operation(.delete(mappingID: mapping.id, target: .daou, targetEventID: d.id, expectedVersion: d.version), newBaseline: .deleted)
        case (.confirmedDeleted, .confirmedDeleted):
            return .settled(.deleted)
        default:
            return .held(.incompleteObservation)
        }
    }

    private static func conflict(
        _ reason: SyncConflictReason,
        mapping: CalendarMapping,
        daou: CalendarObservation,
        google: CalendarObservation
    ) -> SyncDecision {
        .conflict(SyncConflict(mappingID: mapping.id, reason: reason, baseline: mapping.baseline, daou: daou, google: google))
    }

    private static func isAbsent(_ observation: CalendarObservation) -> Bool {
        if case .absent = observation { return true }
        return false
    }

    private static func isDeleted(_ observation: CalendarObservation) -> Bool {
        if case .confirmedDeleted = observation { return true }
        return false
    }

    private static func isComplete(_ observation: CalendarObservation) -> Bool {
        if case .unavailable = observation { return false }
        return true
    }
}
