import Foundation
import Observation

/// The local item store observed by the menu bar list and the popup.
///
/// This type only fixes the shape the app is wired against: a main-actor observable object created by
/// `live()`. Items, the action queue and persistence are added inside it without changing that shape.
@MainActor
@Observable
public final class ItemStore {
    public init() {}

    /// The store the running app uses.
    public static func live() -> ItemStore {
        ItemStore()
    }
}
