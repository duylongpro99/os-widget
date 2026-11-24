import Foundation

/// A directory of widget actions waiting for the app, next to the store file.
///
/// The widget writes each action as its own `<uuid>.json`: first to a `.tmp-` file in the same
/// directory, then renamed into place. A rename within one directory is atomic and every name is
/// unique, so any number of writers and the app reading at the same time need no lock, and a reader
/// never sees half a file. Only the app removes files, after it has applied them to the store.
public struct ActionInbox: Sendable {
    public static let directoryName = "inbox"
    static let temporaryPrefix = ".tmp-"

    public let directory: URL

    public init(location: StoreLocation) {
        directory = location.baseDirectory.appending(path: Self.directoryName, directoryHint: .isDirectory)
    }

    /// The actions in the inbox and the files that could not be read as one.
    public struct Contents: Sendable, Hashable {
        /// Oldest first.
        public let actions: [WidgetAction]
        /// File names that are not a valid action. `ItemStore.drain` removes them.
        public let corrupt: [String]
    }

    /// Writes `action` to the inbox, creating the directory when needed.
    public func submit(_ action: WidgetAction) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try ServerJSON.makeEncoder().encode(action)
        let temporary = directory.appending(path: "\(Self.temporaryPrefix)\(action.id.uuidString).json")
        do {
            try data.write(to: temporary)
            try fileManager.moveItem(at: temporary, to: fileURL(for: action.id))
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    /// The actions waiting in the inbox, oldest first. Unreadable files are skipped.
    public func pending() -> [WidgetAction] {
        contents().actions
    }

    /// Reads every finished action file. Files still being written (`.tmp-`) and other names are
    /// ignored; a `.json` file that does not decode, or whose name is not its own id, is reported as
    /// corrupt so it cannot block the inbox.
    public func contents() -> Contents {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        } catch {
            return Contents(actions: [], corrupt: [])
        }
        let decoder = ServerJSON.makeDecoder()
        var actions: [WidgetAction] = []
        var corrupt: [String] = []
        for name in names where name.hasSuffix(".json") && !name.hasPrefix(Self.temporaryPrefix) {
            guard let data = try? Data(contentsOf: directory.appending(path: name)) else {
                // Removed since the listing: already applied by an earlier drain.
                continue
            }
            if let action = try? decoder.decode(WidgetAction.self, from: data), name == Self.fileName(for: action.id) {
                actions.append(action)
            } else {
                Log.widget.error("widget.inbox_corrupt name=\(name, privacy: .public)")
                corrupt.append(name)
            }
        }
        actions.sort { $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id.uuidString < $1.id.uuidString }
        return Contents(actions: actions, corrupt: corrupt.sorted())
    }

    /// Removes the files of the given actions. Files already gone are skipped.
    public func remove(_ ids: [UUID]) {
        for id in ids {
            try? FileManager.default.removeItem(at: fileURL(for: id))
        }
    }

    /// Removes files reported as corrupt by `contents()`.
    public func removeCorrupt(_ names: [String]) {
        for name in names where !name.contains("/") {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appending(path: Self.fileName(for: id))
    }

    private static func fileName(for id: UUID) -> String {
        "\(id.uuidString).json"
    }
}
