import Foundation
import Testing
@testable import OSWidgetKit

@Suite("Sync settings")
struct SyncSettingsTests {
    private static let saved = SyncSettings(
        workerURL: URL(string: "https://worker.example"),
        clientToken: "fake-token-a",
        supabaseURL: URL(string: "https://project.example"),
        publishableKey: "fake-key-a"
    )

    @Test func savingTheSameValuesCallsForNothing() {
        #expect(Self.saved.change(to: Self.saved) == .none)
    }

    @Test func aNewTokenAloneCallsForARound() {
        var new = Self.saved
        new.clientToken = "fake-token-b"
        #expect(Self.saved.change(to: new) == .sync)
    }

    @Test func aTokenEnteredForTheFirstTimeCallsForARound() {
        var before = Self.saved
        before.clientToken = nil
        #expect(before.change(to: Self.saved) == .sync)
    }

    @Test func aNewWorkerURLCallsForARound() {
        var new = Self.saved
        new.workerURL = URL(string: "https://other-worker.example")
        #expect(Self.saved.change(to: new) == .sync)
    }

    @Test func aNewSupabaseURLOrKeyReconnectsRealtime() {
        var newURL = Self.saved
        newURL.supabaseURL = URL(string: "https://other-project.example")
        var newKey = Self.saved
        newKey.publishableKey = "fake-key-b"
        newKey.clientToken = "fake-token-b"
        #expect(Self.saved.change(to: newURL) == .reconnectAndSync)
        #expect(Self.saved.change(to: newKey) == .reconnectAndSync)
    }
}
