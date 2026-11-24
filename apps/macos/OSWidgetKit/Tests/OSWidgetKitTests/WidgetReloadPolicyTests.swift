import Foundation
import Testing
@testable import OSWidgetKit

@Suite("Widget reload policy")
struct WidgetReloadPolicyTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func policy() -> WidgetReloadPolicy {
        WidgetReloadPolicy(calendar: utc)
    }

    /// A snapshot that differs from every other `tag`.
    private func snapshot(_ tag: Int) -> WidgetSnapshot {
        WidgetSnapshot(items: [TestData.item("i\(tag)")], unreadCount: tag, nextExpiry: nil)
    }

    /// Offers a snapshot and, like the reloader, records a reload when told to reload now.
    private func offer(_ policy: inout WidgetReloadPolicy, _ snapshot: WidgetSnapshot, at time: Date) -> WidgetReloadPolicy.Decision {
        let decision = policy.offer(snapshot, at: time)
        if decision == .reloadNow { policy.didReload(snapshot, at: time) }
        return decision
    }

    @Test func firstOfferAlwaysReloads() {
        var policy = policy()
        let decision1 = offer(&policy, .empty, at: start)
        #expect(decision1 == .reloadNow)
    }

    @Test func sameSnapshotTwiceIsSkipped() {
        var policy = policy()
        let decision1 = offer(&policy, snapshot(1), at: start)
        #expect(decision1 == .reloadNow)
        let decision2 = offer(&policy, snapshot(1), at: start.addingTimeInterval(60))
        #expect(decision2 == .skip)
        #expect(policy.reloadsToday == 1)
    }

    @Test func changeAfterTheIntervalReloadsNow() {
        var policy = policy()
        _ = offer(&policy, snapshot(1), at: start)
        let decision1 = offer(&policy, snapshot(2), at: start.addingTimeInterval(5))
        #expect(decision1 == .reloadNow)
        #expect(policy.reloadsToday == 2)
    }

    @Test func changeInsideTheIntervalSchedulesExactlyOnceAndFiresWithTheLatest() {
        var policy = policy()
        _ = offer(&policy, snapshot(1), at: start)
        let due = start.addingTimeInterval(5)

        let decision1 = offer(&policy, snapshot(2), at: start.addingTimeInterval(0.5))

        #expect(decision1 == .schedule(at: due))
        let decision2 = offer(&policy, snapshot(3), at: start.addingTimeInterval(1))
        #expect(decision2 == .skip)
        let decision3 = offer(&policy, snapshot(4), at: start.addingTimeInterval(2))
        #expect(decision3 == .skip)
        let fired1 = policy.fire(at: due)
        #expect(fired1)
        #expect(policy.lastReloaded == snapshot(4))
        #expect(policy.lastReloadAt == due)
        #expect(policy.reloadsToday == 2)
        #expect(!policy.isWaiting)
    }

    @Test func changingBackWhileWaitingDoesNotReload() {
        var policy = policy()
        _ = offer(&policy, snapshot(1), at: start)
        _ = offer(&policy, snapshot(2), at: start.addingTimeInterval(1))
        let decision1 = offer(&policy, snapshot(1), at: start.addingTimeInterval(2))
        #expect(decision1 == .skip)
        let fired1 = policy.fire(at: start.addingTimeInterval(5))
        #expect(!fired1)
        #expect(policy.reloadsToday == 1)
        #expect(policy.lastReloaded == snapshot(1))
    }

    @Test func aFiredWaitCountsFromTheFireTime() {
        var policy = policy()
        _ = offer(&policy, snapshot(1), at: start)
        _ = offer(&policy, snapshot(2), at: start.addingTimeInterval(1))
        let fired1 = policy.fire(at: start.addingTimeInterval(5))
        #expect(fired1)
        let decision1 = offer(&policy, snapshot(3), at: start.addingTimeInterval(6))
        #expect(decision1 == .schedule(at: start.addingTimeInterval(10)))
    }

    @Test func burstOfFiftyChangesInTwelveSecondsReloadsAtMostFourTimes() {
        var policy = policy()
        var reloadTimes: [Date] = []
        var dueAt: Date?
        let count = 50
        let step = 12.4 / Double(count - 1)

        for index in 0..<count {
            let time = start.addingTimeInterval(Double(index) * step)
            if let due = dueAt, due <= time {
                if policy.fire(at: due) { reloadTimes.append(due) }
                dueAt = nil
            }
            switch policy.offer(snapshot(index), at: time) {
            case .reloadNow:
                policy.didReload(snapshot(index), at: time)
                reloadTimes.append(time)
            case .schedule(let due):
                dueAt = due
            case .skip:
                break
            }
        }
        if let due = dueAt, policy.fire(at: due) { reloadTimes.append(due) }

        #expect(reloadTimes.count <= 4)
        #expect(reloadTimes.count >= 3)
        #expect(zip(reloadTimes, reloadTimes.dropFirst()).allSatisfy { $1.timeIntervalSince($0) >= 5 })
        #expect(policy.lastReloaded == snapshot(count - 1))
    }

    @Test func reloadsTodayResetsAfterMidnight() {
        var policy = policy()
        let lateEvening = utc.date(from: DateComponents(year: 2027, month: 1, day: 10, hour: 23, minute: 59, second: 50))!
        _ = offer(&policy, snapshot(1), at: lateEvening)
        _ = offer(&policy, snapshot(2), at: lateEvening.addingTimeInterval(6))
        #expect(policy.reloadsToday == 2)

        // Midnight passes with no change: the count reads as a new day on the next offer.
        let decision1 = policy.offer(snapshot(2), at: lateEvening.addingTimeInterval(20))
        #expect(decision1 == .skip)
        #expect(policy.reloadsToday == 0)
        let decision2 = offer(&policy, snapshot(3), at: lateEvening.addingTimeInterval(21))
        #expect(decision2 == .reloadNow)
        #expect(policy.reloadsToday == 1)
    }

    @Test func durationSecondsKeepsTheFraction() {
        #expect(Duration.milliseconds(2500).seconds == 2.5)
    }
}
