import Foundation
import Testing
@testable import OSWidgetKit

@MainActor
@Suite("Store reader")
struct StoreReaderTests {
    @Test func readsWhatTheStoreWroteWithoutChangingTheFile() throws {
        let dir = TempStoreDirectory()
        defer { dir.remove() }
        let store = ItemStore(location: dir.location, now: TestClock().function)
        store.replaceAll(items: [TestData.item("a"), TestData.item("b", createdSecondsAgo: 30), TestData.item("c", expiresIn: nil)], seq: 42)
        store.markRead("a")
        store.delete("b")

        let before = try Data(contentsOf: dir.storeFile)
        let modifiedBefore = try modificationDate(dir.storeFile)
        let contents = try #require(StoreReader.read(location: dir.location))

        #expect(contents.items == store.items)
        #expect(contents.cursor == 42)
        #expect(contents.items.first { $0.id == "a" }?.isRead == true)
        #expect(contents.items.first { $0.id == "b" }?.isDeleted == true)
        #expect(try Data(contentsOf: dir.storeFile) == before)
        #expect(try modificationDate(dir.storeFile) == modifiedBefore)
    }

    @Test func missingFileReturnsNilAndCreatesNothing() {
        let dir = TempStoreDirectory()
        defer { dir.remove() }
        #expect(StoreReader.read(location: dir.location) == nil)
        #expect(!FileManager.default.fileExists(atPath: dir.url.path(percentEncoded: false)))
    }

    @Test func corruptFileReturnsNilAndIsLeftAlone() throws {
        let dir = TempStoreDirectory()
        defer { dir.remove() }
        try FileManager.default.createDirectory(at: dir.url, withIntermediateDirectories: true)
        let broken = Data("{\"version\": 1, \"items\": [".utf8)
        try broken.write(to: dir.storeFile)

        #expect(StoreReader.read(location: dir.location) == nil)
        #expect(try Data(contentsOf: dir.storeFile) == broken)
    }

    /// A file in the format the installed menu bar app writes, keys spelled out by hand, must keep
    /// loading in both the app's store and the widget's reader.
    @Test func menuBarAppStoreFileStillLoads() throws {
        let dir = TempStoreDirectory()
        defer { dir.remove() }
        try FileManager.default.createDirectory(at: dir.url, withIntermediateDirectories: true)
        try Data(Self.menuBarAppStoreFile.utf8).write(to: dir.storeFile)

        let contents = try #require(StoreReader.read(location: dir.location))
        #expect(contents.cursor == 118)
        #expect(contents.items.map(\.id) == ["01JDX0000000000000000000A1", "01JDX0000000000000000000B2"])
        let first = contents.items[0]
        #expect(first.kind == "notification" && first.priority == "high" && first.url == "https://example.com/a")
        #expect(first.dedupeKey == "deploy-1" && first.readAt == nil && !first.isDeleted)
        #expect(first.expiresAt == ServerJSON.parseDate("2026-11-24T10:00:00.000000Z"))
        #expect(contents.items[1].isRead && contents.items[1].body == nil)

        let store = ItemStore(location: dir.location, now: TestClock().function)
        #expect(store.items == contents.items)
        #expect(store.cursor == 118)
        #expect(store.queue.map(\.itemId) == ["01JDX0000000000000000000B2"])
        #expect(store.queue.first?.operation == .read(true))
        #expect(store.popupSettings == PopupSettings(disabledKinds: ["vocab"], quietMode: true))
        #expect(store.lastFullSyncAt == ServerJSON.parseDate("2026-11-23T09:00:00.000000Z"))
    }

    private func modificationDate(_ url: URL) throws -> Date? {
        try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.modificationDate] as? Date
    }

    private static let menuBarAppStoreFile = """
    {
      "cursor": 118,
      "items": [
        {
          "body": {"message": "Deploy finished"},
          "created_at": "2026-11-23T09:59:00.000000Z",
          "dedupe_key": "deploy-1",
          "deleted_at": null,
          "expires_at": "2026-11-24T10:00:00.000000Z",
          "id": "01JDX0000000000000000000A1",
          "kind": "notification",
          "priority": "high",
          "read_at": null,
          "source": "ci",
          "summary": "main is green",
          "title": "Deploy",
          "url": "https://example.com/a"
        },
        {
          "body": null,
          "created_at": "2026-11-23T09:58:00.000000Z",
          "dedupe_key": null,
          "deleted_at": null,
          "expires_at": null,
          "id": "01JDX0000000000000000000B2",
          "kind": "generic",
          "priority": "normal",
          "read_at": "2026-11-23T09:59:30.000000Z",
          "source": "cli",
          "summary": "a note",
          "title": "Note",
          "url": null
        }
      ],
      "last_full_sync_at": "2026-11-23T09:00:00.000000Z",
      "popup_settings": {"disabled_kinds": ["vocab"], "quiet_mode": true},
      "queue": [
        {
          "createdAt": "2026-11-23T09:59:30.000000Z",
          "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
          "itemId": "01JDX0000000000000000000B2",
          "operation": {"read": {"_0": true}}
        }
      ],
      "version": 1
    }
    """
}
