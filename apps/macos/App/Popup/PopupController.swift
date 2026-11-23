import AppKit

/// Shows new items in a non-activating panel under the menu bar icon.
///
/// `anchor` returns the icon's frame on screen and `isListOpen` whether the item list is showing; both
/// come from `MenuBarController`. The panel itself does not exist yet.
@MainActor
final class PopupController {
    private let environment: AppEnvironment
    private let anchor: () -> NSRect?
    private let isListOpen: () -> Bool

    init(env: AppEnvironment, anchor: @escaping () -> NSRect?, isListOpen: @escaping () -> Bool) {
        environment = env
        self.anchor = anchor
        self.isListOpen = isListOpen
    }
}
