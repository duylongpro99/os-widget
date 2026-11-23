import Foundation
import Testing
@testable import OSWidgetKit

@Suite("PopupPolicy")
struct PopupPolicyTests {
    private let now = TestData.now

    private func decide(
        _ items: [Item],
        settings: PopupSettings = .default,
        isListOpen: Bool = false
    ) -> PopupDecision {
        PopupPolicy.decide(items: items, settings: settings, isListOpen: isListOpen, now: now)
    }

    private func low(_ id: String, createdSecondsAgo: TimeInterval = 60) -> Item {
        var item = TestData.item(id, createdSecondsAgo: createdSecondsAgo)
        item.priority = "low"
        return item
    }

    @Test func oneNormalItemShows() {
        let a = TestData.item("a")
        #expect(decide([a]) == .show(newest: a, othersCount: 0))
    }

    @Test func threeItemsAtOnceShowTheNewestWithTwoOthers() {
        let old = TestData.item("old", createdSecondsAgo: 300)
        let newest = TestData.item("newest", createdSecondsAgo: 10)
        let middle = TestData.item("middle", createdSecondsAgo: 100)
        #expect(decide([old, newest, middle]) == .show(newest: newest, othersCount: 2))
    }

    @Test func lowPriorityItemsAreFiltered() {
        let normal = TestData.item("normal", createdSecondsAgo: 100)
        let quiet = low("quiet", createdSecondsAgo: 10)
        #expect(decide([normal, quiet]) == .show(newest: normal, othersCount: 0))
        #expect(decide([low("x"), low("y")]) == .none(reason: .low))
    }

    @Test func disabledKindIsFilteredOtherKindsStillShow() {
        let settings = PopupSettings(disabledKinds: ["vocab"])
        let vocab = TestData.item("v", kind: "vocab", createdSecondsAgo: 10)
        let note = TestData.item("n", kind: "notification", createdSecondsAgo: 100)
        #expect(decide([vocab, note], settings: settings) == .show(newest: note, othersCount: 0))
        #expect(decide([vocab], settings: settings) == .none(reason: .kind))
    }

    @Test func quietModeSuppressesUntilTurnedOff() {
        let a = TestData.item("a")
        #expect(decide([a], settings: PopupSettings(quietMode: true)) == .none(reason: .quiet))
        #expect(decide([a], settings: PopupSettings(quietMode: false)) == .show(newest: a, othersCount: 0))
    }

    @Test func openListSuppresses() {
        let a = TestData.item("a")
        #expect(decide([a], isListOpen: true) == .none(reason: .listOpen))
        #expect(decide([a], settings: PopupSettings(quietMode: true), isListOpen: true) == .none(reason: .listOpen))
    }

    @Test func unknownKindStillShows() {
        let strange = TestData.item("s", kind: "no-such-kind")
        #expect(decide([strange]) == .show(newest: strange, othersCount: 0))
    }

    @Test func readDeletedAndExpiredItemsAreDropped() {
        let read = TestData.item("r", read: true)
        let deleted = TestData.item("d", deleted: true)
        let expired = TestData.item("e", expiresIn: -1)
        #expect(decide([read, deleted, expired]) == .none(reason: .nothingNew))
        #expect(decide([]) == .none(reason: .nothingNew))
    }

    @Test func newestRemainingCandidateGivesTheSuppressReason() {
        let settings = PopupSettings(disabledKinds: ["vocab"])
        let lowItem = low("l", createdSecondsAgo: 10)
        let vocab = TestData.item("v", kind: "vocab", createdSecondsAgo: 100)
        #expect(decide([vocab, lowItem], settings: settings) == .none(reason: .low))
    }

    @Test func mergeWhileShowingReplacesContentAndAddsUpOthers() {
        let a = TestData.item("a", createdSecondsAgo: 100)
        let b = TestData.item("b", createdSecondsAgo: 10)
        let merged = PopupPolicy.merge(current: .show(newest: a, othersCount: 1), incoming: .show(newest: b, othersCount: 0))
        #expect(merged == .show(newest: b, othersCount: 2))
    }

    @Test func mergeCountsIncomingOthers() {
        let a = TestData.item("a")
        let b = TestData.item("b")
        let merged = PopupPolicy.merge(current: .show(newest: a, othersCount: 0), incoming: .show(newest: b, othersCount: 2))
        #expect(merged == .show(newest: b, othersCount: 3))
    }

    @Test func mergeWithNothingShowingTakesIncoming() {
        let b = TestData.item("b")
        #expect(PopupPolicy.merge(current: nil, incoming: .show(newest: b, othersCount: 1)) == .show(newest: b, othersCount: 1))
        #expect(PopupPolicy.merge(current: nil, incoming: .none(reason: .low)) == .none(reason: .low))
    }

    @Test func mergeWithSuppressedIncomingKeepsCurrent() {
        let a = TestData.item("a")
        let current = PopupDecision.show(newest: a, othersCount: 1)
        #expect(PopupPolicy.merge(current: current, incoming: .none(reason: .kind)) == current)
    }

    @Test func mergeDoesNotCountTheShowingItemTwice() {
        let a = TestData.item("a")
        let merged = PopupPolicy.merge(current: .show(newest: a, othersCount: 1), incoming: .show(newest: a, othersCount: 0))
        #expect(merged == .show(newest: a, othersCount: 1))
    }
}

@Suite("PopupCountdown")
struct PopupCountdownTests {
    private let start = TestData.now

    @Test func runsForThirtySeconds() {
        let countdown = PopupCountdown(startingAt: start)
        #expect(countdown.duration == 30)
        #expect(countdown.deadline == start.addingTimeInterval(30))
        #expect(!countdown.isExpired(at: start.addingTimeInterval(29.9)))
        #expect(countdown.isExpired(at: start.addingTimeInterval(30)))
    }

    @Test func pauseStopsTheCountdown() {
        var countdown = PopupCountdown(startingAt: start)
        countdown.pause(at: start.addingTimeInterval(10))
        #expect(countdown.isPaused)
        #expect(countdown.deadline == nil)
        #expect(countdown.remaining(at: start.addingTimeInterval(50)) == 20)
        #expect(!countdown.isExpired(at: start.addingTimeInterval(50)))
    }

    @Test func resumeContinuesWithTheTimeLeft() {
        var countdown = PopupCountdown(startingAt: start)
        countdown.pause(at: start.addingTimeInterval(10))
        countdown.resume(at: start.addingTimeInterval(50))
        #expect(countdown.deadline == start.addingTimeInterval(70))
        #expect(!countdown.isExpired(at: start.addingTimeInterval(69)))
        #expect(countdown.isExpired(at: start.addingTimeInterval(70)))
    }

    @Test func pausingOrResumingTwiceChangesNothing() {
        var countdown = PopupCountdown(startingAt: start)
        countdown.pause(at: start.addingTimeInterval(5))
        countdown.pause(at: start.addingTimeInterval(20))
        #expect(countdown.remaining(at: start.addingTimeInterval(20)) == 25)
        countdown.resume(at: start.addingTimeInterval(20))
        countdown.resume(at: start.addingTimeInterval(40))
        #expect(countdown.deadline == start.addingTimeInterval(45))
    }

    @Test func newItemRestartsFromThirtySeconds() {
        let first = PopupCountdown(startingAt: start)
        let later = start.addingTimeInterval(25)
        #expect(first.remaining(at: later) == 5)
        let restarted = PopupCountdown(startingAt: later)
        #expect(restarted.remaining(at: later) == 30)
    }
}
