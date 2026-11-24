import Foundation

/// What another process can read from the store: the items, with every queued user action already
/// applied, and the event cursor.
public struct StoreContents: Sendable, Hashable {
    public let items: [Item]
    public let cursor: Int64?

    public init(items: [Item], cursor: Int64?) {
        self.items = items
        self.cursor = cursor
    }
}

/// Reads `store.json` without ever writing it, for a process other than the app (the widget).
///
/// It never creates the directory, writes, or deletes anything. The app replaces the file atomically,
/// so a read sees either the previous or the next version, never a partial one.
public enum StoreReader {
    /// The store in `location`, or `nil` when there is no file or it cannot be decoded.
    public static func read(location: StoreLocation) -> StoreContents? {
        let url = StoreFile.url(in: location.baseDirectory)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            Log.store.notice("store.reader_failed reason=missing")
            return nil
        } catch {
            Log.store.error("store.reader_failed reason=unreadable error=\(String(describing: error), privacy: .public)")
            return nil
        }
        do {
            let file = try StoreFile.decode(data)
            return StoreContents(items: file.items, cursor: file.cursor)
        } catch {
            Log.store.error("store.reader_failed reason=corrupt")
            return nil
        }
    }
}
