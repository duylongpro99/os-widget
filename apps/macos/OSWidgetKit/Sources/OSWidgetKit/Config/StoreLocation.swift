import Foundation

/// The single place that knows where the local store lives.
///
/// The app uses the App Group container named by the `AppGroupID` key of its `Info.plist`, so a widget
/// signed with the same team can read the same files. Tests pass their own base directory and never
/// touch the real container.
public struct StoreLocation: Sendable, Equatable {
    public static let appGroupInfoKey = "AppGroupID"

    public let baseDirectory: URL

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    /// The App Group container of the running app.
    public static func appGroup(bundle: Bundle = .main, fileManager: FileManager = .default) throws(StoreLocationError) -> StoreLocation {
        guard let groupID = bundle.object(forInfoDictionaryKey: appGroupInfoKey) as? String,
              !groupID.isEmpty, !groupID.hasPrefix("$(")
        else { throw .missingAppGroupID }
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            throw .containerUnavailable(groupID)
        }
        return StoreLocation(baseDirectory: container)
    }

    /// Returns the store directory, creating it when it does not exist yet.
    public func directory(fileManager: FileManager = .default) throws -> URL {
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        return baseDirectory
    }
}

public enum StoreLocationError: Error, Equatable {
    /// `Info.plist` has no usable `AppGroupID` value.
    case missingAppGroupID
    /// The system returned no container for the group, usually because the entitlement is missing.
    case containerUnavailable(String)
}
