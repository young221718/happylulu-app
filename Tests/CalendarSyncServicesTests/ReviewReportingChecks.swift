import Foundation
import CalendarSyncCore
@testable import CalendarSyncServices

func testAmbiguousPairPreservesProtectionAndJournal(pending: Bool) async throws {
    try await withStore { store in
        try await configured(store, enabled: true)
        let source = sample("ambiguous-d")
        let target = sample("ambiguous-g")
        var state = try await store.load()
        let first = CalendarMapping(id: "d-only", daouEventID: source.id, googleEventID: nil, baseline: nil)
        let second = CalendarMapping(id: "g-only", daouEventID: nil, googleEventID: target.id, baseline: nil,
            protectedSources: pending ? nil : [.google])
        state.mappings[first.id] = first
        state.mappings[second.id] = second
        state.conflicts[first.id] = SyncConflict(mappingID: first.id, reason: .initialPairAmbiguous,
            baseline: nil, daou: .present(source), google: .present(target))
        if pending {
            state.pendingOperations[second.id] = PendingSyncOperation(id: second.id,
                operation: .update(mappingID: second.id, target: .google, targetEventID: target.id,
                    expectedVersion: target.version, content: source.content), newBaseline: .content(source.content))
        }
        try await store.save(state)
        let google = FakeProvider(side: .google, events: [target])
        let coordinator = SyncCoordinator(store: store,
            daou: FakeProvider(side: .daou, events: [source]), google: google)
        var rejected = false
        do { try await coordinator.resolveConflict(mappingID: first.id, prefer: .daou) }
        catch { rejected = true }
        let writes = await google.writes
        let latest = try await store.load()
        require(rejected && writes == 0, "ambiguous collapse must preserve the other mapping's protection/journal")
        require(latest.mappings[second.id] != nil, "rejected collapse retains both mappings")
        require(latest.pendingOperations.count == (pending ? 1 : 0), "rejected collapse retains the uncertain journal")
    }
}

func testRunSummaryDistinguishesPreviewFromAppliedRun() async throws {
    try await withStore { store in
        try await configured(store, enabled: true)
        let coordinator = SyncCoordinator(store: store,
            daou: FakeProvider(side: .daou, events: [sample("report-source")]),
            google: FakeProvider(side: .google))
        let preview = try await coordinator.run(allowWrites: false)
        let previewJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preview)) as! [String: Any]
        require(previewJSON["mode"] as? String == "preview", "preview summary must identify plans rather than completed writes")
        require(preview.completed == 0 && preview.toGoogle == 1, "preview never reports a planned copy as completed")
        let applied = try await coordinator.run(allowWrites: true)
        let appliedJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(applied)) as! [String: Any]
        require(appliedJSON["mode"] as? String == "sync", "applied run summary must identify actual execution")
        require(applied.completed == 1, "applied summary reports the acknowledged write")
    }
}

func testRunSummaryExplainsExcludedEvents() async throws {
    try await withStore { store in
        try await configured(store, enabled: true)
        var source = sample("report-excluded", title: "확인할 일정")
        source.exclusion = .other("alarmLocation")
        let result = try await SyncCoordinator(store: store,
            daou: FakeProvider(side: .daou, events: [source]),
            google: FakeProvider(side: .google)).run(allowWrites: false)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as! [String: Any]
        let issues = json["issues"] as? [[String: Any]] ?? []
        require(issues.contains { $0["title"] as? String == source.content.title &&
            $0["reason"] as? String == "alarmLocation" && $0["side"] as? String == "daou" },
            "excluded event must retain its title, side, and concrete reason for local review")
        require(result.excluded == 1 && result.completed == 0, "excluded review cannot count as a completed write")
    }
}

func testCoordinatorPersistsInvitationProtection() async throws {
    try await withStore { store in
        try await configured(store, enabled: true)
        var source = sample("protected-original")
        source.protectedSource = true
        let daou = FakeProvider(side: .daou, events: [source])
        let google = FakeProvider(side: .google)
        let coordinator = SyncCoordinator(store: store, daou: daou, google: google)
        _ = try await coordinator.run(allowWrites: false)
        var state = try await store.load()
        require(state.mappings.values.first?.protectedSources?.contains(.daou) == true,
                "invitation source protection must persist with its mapping")
        // Losing attendees from a later snapshot must never erase protection.
        source.protectedSource = nil
        await daou.replace(source)
        _ = try await coordinator.run(allowWrites: true)
        state = try await store.load()
        require(state.mappings.values.first?.protectedSources?.contains(.daou) == true,
                "source protection survives later observations and copy receipts")
    }
}

func testConflictCannotWriteProtectedInvitation() async throws {
    try await withStore { store in
        try await configured(store, enabled: true)
        let source = sample("protected-original")
        let mirror = sample("mirror", title: "Mirror changed")
        var state = try await store.load()
        let mapping = CalendarMapping(id: "protected-pair", daouEventID: source.id,
            googleEventID: mirror.id, baseline: .content(source.content), protectedSources: [.daou])
        state.mappings[mapping.id] = mapping
        state.conflicts[mapping.id] = SyncConflict(mappingID: mapping.id, reason: .simultaneousEdits,
            baseline: mapping.baseline, daou: .present(source), google: .present(mirror))
        try await store.save(state)
        let daou = FakeProvider(side: .daou, events: [source])
        let coordinator = SyncCoordinator(store: store, daou: daou,
            google: FakeProvider(side: .google, events: [mirror]))
        var rejected = false
        do { try await coordinator.resolveConflict(mappingID: mapping.id, prefer: .google) }
        catch CalendarCodecError.unsupportedEvent { rejected = true }
        require(rejected, "manual conflict resolution must reject a write to the protected invitation origin")
        let writes = await daou.writes
        let latest = try await store.load()
        require(writes == 0 && latest.pendingOperations.isEmpty,
                "protected conflict creates neither a write nor a journal")
    }
}

func testPendingRecoveryCannotWriteProtectedInvitation() async throws {
    try await withStore { store in
        try await configured(store, enabled: true)
        let source = sample("protected-original")
        let mirror = sample("mirror", title: "Mirror changed")
        var state = try await store.load()
        let mapping = CalendarMapping(id: "protected-pair", daouEventID: source.id,
            googleEventID: mirror.id, baseline: .content(source.content), protectedSources: [.daou])
        state.mappings[mapping.id] = mapping
        state.pendingOperations[mapping.id] = PendingSyncOperation(id: mapping.id,
            operation: .update(mappingID: mapping.id, target: .daou, targetEventID: source.id,
                expectedVersion: source.version, content: mirror.content), newBaseline: .content(mirror.content))
        try await store.save(state)
        let daou = FakeProvider(side: .daou, events: [source])
        let result = try await SyncCoordinator(store: store, daou: daou,
            google: FakeProvider(side: .google, events: [mirror])).run(allowWrites: true)
        let writes = await daou.writes
        require(writes == 0 && result.held == 1, "recovery cannot replay a protected-source write")
        require((try await store.load()).pendingOperations[mapping.id] != nil,
                "blocked recovery preserves its unresolved journal")
    }
}

func testSuccessfulPreviewKeepsFailureHistory() async throws {
    try await withStore { store in
        try await configured(store, enabled: true)
        let daou = FakeProvider(side: .daou)
        let google = FakeProvider(side: .google)
        let coordinator = SyncCoordinator(store: store, daou: daou, google: google)
        await google.setFetchError(CalendarHTTPError.httpStatus(401, retryAfter: nil))
        do { _ = try await coordinator.run(allowWrites: true) } catch {}
        let failed = try await store.load()
        require(failed.lastFailureCode == "http:401" && failed.lastFailureAt != nil,
                "authentication failure must retain a dated reason")
        await google.setFetchError(nil)
        _ = try await coordinator.run(allowWrites: false)
        let refreshed = try await store.load()
        require(refreshed.lastFailureCode == failed.lastFailureCode && refreshed.lastFailureAt == failed.lastFailureAt,
                "a successful preview must not erase the cause of a prior pause")
        require(!refreshed.configuration.enabled && refreshed.pauseReason == "authenticationRequired",
                "a preview preserves the pause and its cause")
    }
}
