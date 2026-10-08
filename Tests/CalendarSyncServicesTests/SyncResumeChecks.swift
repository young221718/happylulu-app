import Foundation
import CalendarSyncCore
import CalendarSyncServices

func pausedSystemState() -> CalendarSyncState {
    var state = CalendarSyncState()
    state.configuration.daouBaseURL = "eventkit"
    state.configuration.daouCalendarURL = "daou-calendar"
    state.configuration.googleCalendarID = "google-calendar"
    state.configuration.systemAccountsConfirmed = true
    state.configuration.previewAccepted = true
    state.pairKey = "eventkit|daou-calendar|google-calendar"
    state.lastSuccessAt = Date(timeIntervalSince1970: 1_700_000_000)
    state.lastPreview = SyncRunSummary()
    return state
}

func testSuccessfulLegacySystemSyncCanResumeAfterFreshPreview() async throws {
    try await withStore { store in
        var state = pausedSystemState()
        try await store.save(state)
        let daou = FakeProvider(side: .daou, events: [sample("resume-event")])
        let google = FakeProvider(side: .google)
        let coordinator = SyncCoordinator(store: store, daou: daou, google: google)
        _ = try await coordinator.run(allowWrites: false)
        state = try await store.load()
        require(state.initialPreviewFingerprint == nil,
                "established sync does not receive a first-cycle fingerprint")
        require(state.canBeginSystemSync(reviewedPairKey: "eventkit|daou-calendar|google-calendar"),
                "freshly reviewed successful same-pair sync must be resumable without a first-cycle fingerprint")
        let resumedAt = Date(timeIntervalSince1970: 1_800_000_000)
        try state.beginSystemSync(reviewedPairKey: state.pairKey, now: resumedAt)
        require(state.configuration.enabled && state.configuration.previewAccepted && state.nextRunAt == resumedAt,
                "explicit resume enables sync and replaces an old schedule")
        try await store.save(state)
        let applied = try await coordinator.run(allowWrites: true)
        let resumedGoogleCount = await google.count()
        require(applied.completed == 1 && resumedGoogleCount == 1,
                "resumed legacy sync applies a new event through the coordinator")
        _ = try await coordinator.run(allowWrites: true)
        require(await google.count() == 1, "resuming preserves duplicate prevention")
    }
}

func testResumeRequiresFreshSamePairReview() throws {
    var state = pausedSystemState()
    require(state.hasReviewableSystemPreview, "previous successful preview remains visible while paused")
    for reviewedPair in [nil, "eventkit|other-calendar|google-calendar"] as [String?] {
        require(!state.canBeginSystemSync(reviewedPairKey: reviewedPair),
                "old or different-pair review cannot resume sync")
        do {
            try state.beginSystemSync(reviewedPairKey: reviewedPair)
            require(false, "resume must require fresh review of the selected pair")
        } catch SyncCoordinatorError.previewRequired {}
        require(!state.configuration.enabled, "rejected resume leaves sync paused")
    }
    state.configuration.googleCalendarID = "replacement-calendar"
    require(!state.canBeginSystemSync(reviewedPairKey: "eventkit|daou-calendar|replacement-calendar"),
            "a successful session cannot authorize a different calendar pair")
}

func testInitialSystemStartStillRequiresFingerprint() throws {
    var state = pausedSystemState()
    state.lastSuccessAt = nil
    require(!state.hasReviewableSystemPreview, "legacy first-run counts alone are not an accepted preview")
    require(!state.canBeginSystemSync(reviewedPairKey: state.pairKey),
            "fresh review alone cannot replace the initial snapshot fingerprint")
    state.initialPreviewFingerprint = "observed-snapshot"
    require(state.canBeginSystemSync(reviewedPairKey: nil),
            "first sync can begin with a persisted snapshot for coordinator verification")
    state.configuration.systemAccountsConfirmed = false
    require(!state.canBeginSystemSync(reviewedPairKey: state.pairKey),
            "unconfirmed account pairs cannot begin sync")
}
