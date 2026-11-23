import Foundation
import Testing
@testable import OSWidgetKit

@Suite("AppConfig")
struct AppConfigTests {
    private func withTemporaryDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "local.oswidget.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test func startsEmpty() {
        withTemporaryDefaults { defaults in
            let config = AppConfig(defaults: defaults)
            #expect(config.workerURL == nil)
            #expect(config.supabaseURL == nil)
            #expect(config.supabasePublishableKey == nil)
            #expect(!config.isComplete)
        }
    }

    @Test func roundTripsThroughUserDefaults() {
        withTemporaryDefaults { defaults in
            let config = AppConfig(defaults: defaults)
            config.workerURL = URL(string: "https://worker.example.dev")
            config.supabaseURL = URL(string: "https://project.supabase.co")
            config.supabasePublishableKey = "sb_publishable_example"

            let reread = AppConfig(defaults: defaults)
            #expect(reread.workerURL == URL(string: "https://worker.example.dev"))
            #expect(reread.supabaseURL == URL(string: "https://project.supabase.co"))
            #expect(reread.supabasePublishableKey == "sb_publishable_example")
            #expect(reread.isComplete)
        }
    }

    @Test func nilOrBlankValuesRemoveTheKey() {
        withTemporaryDefaults { defaults in
            let config = AppConfig(defaults: defaults)
            config.supabasePublishableKey = "key"
            config.supabasePublishableKey = "   "
            #expect(config.supabasePublishableKey == nil)
            config.workerURL = URL(string: "https://worker.example.dev")
            config.workerURL = nil
            #expect(config.workerURL == nil)
            #expect(defaults.object(forKey: AppConfig.Key.workerURL) == nil)
        }
    }

    @Test(arguments: [
        ("https://worker.example.dev", true),
        ("  http://localhost:8787  ", true),
        ("http://127.0.0.1:8787", true),
        ("http://[::1]:8787", true),
        ("http://worker.example.dev", false),
        ("http://192.168.1.10:8787", false),
        ("worker.example.dev", false),
        ("ftp://worker.example.dev", false),
        ("https://", false),
        ("", false),
    ])
    func acceptsHTTPSOrLoopbackHTTPWithAHost(text: String, accepted: Bool) {
        #expect((AppConfig.parseServerURL(text) != nil) == accepted)
    }
}

@Suite("StoreLocation")
struct StoreLocationTests {
    private func temporaryBase() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "oswidget-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test func createsAMissingDirectoryThatIsWritable() throws {
        let base = temporaryBase().appending(path: "nested", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: base.deletingLastPathComponent()) }

        let directory = try StoreLocation(baseDirectory: base).directory()

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        let probe = directory.appending(path: "probe.json")
        try Data("{}".utf8).write(to: probe, options: .atomic)
        #expect(try Data(contentsOf: probe) == Data("{}".utf8))
    }

    @Test func reusesAnExistingDirectory() throws {
        let base = temporaryBase()
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: base.appending(path: "existing.txt"))

        let directory = try StoreLocation(baseDirectory: base).directory()

        #expect(directory == base)
        #expect(try Data(contentsOf: base.appending(path: "existing.txt")) == Data("keep".utf8))
    }

    @Test func appGroupWithoutAnIdentifierFails() {
        // The test runner's bundle has no AppGroupID key, so no container is ever looked up.
        #expect(throws: StoreLocationError.missingAppGroupID) {
            try StoreLocation.appGroup(bundle: Bundle(for: BundleMarker.self))
        }
    }
}

private final class BundleMarker {}
