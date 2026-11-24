import CoreGraphics

/// When the item list (a popover under the menu bar icon) closes on its own.
///
/// The app is an agent, and asking AppKit to activate it is only a request, so the app may not be
/// active while the list shows. A transient popover then never sees the outside click or the loss
/// of active state it relies on to close. The app closes the list itself instead: when it stops
/// being active, and on any mouse click in another app while the list shows.
public enum ItemListDismissal {
    /// Why the list closed, for the `list.closed reason=…` log line.
    public enum Reason: String, Sendable, Hashable {
        /// The user clicked the menu bar icon while the list showed.
        case icon
        /// The app stopped being the active app.
        case resignActive = "resign_active"
        /// The user clicked in another app.
        case outsideClick = "outside_click"
        /// The status menu opened.
        case menu
    }

    /// Whether a mouse click seen in another app at `location` closes the list. A click on the menu
    /// bar icon itself (`iconFrame`, screen coordinates) does not: the icon's own action toggles the
    /// list, and closing here first would make that action open it again.
    public static func closesList(clickAt location: CGPoint, iconFrame: CGRect?) -> Bool {
        guard let iconFrame else { return true }
        return !iconFrame.contains(location)
    }
}
