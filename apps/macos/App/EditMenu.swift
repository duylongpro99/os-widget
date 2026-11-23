import AppKit

/// The app's main menu, never shown because the app is an agent (`LSUIElement`).
///
/// AppKit routes ⌘X, ⌘C, ⌘V, ⌘A, ⌘Z and ⇧⌘Z to text fields through the main menu's key equivalents,
/// so without an Edit menu the fields in the settings window could not cut, copy or paste.
@MainActor
enum EditMenu {
    static func makeMainMenu() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let main = NSMenu()
        // The first item of a main menu is the application menu; the Edit menu has to come after it.
        main.addItem(NSMenuItem(title: "OS Widget", action: nil, keyEquivalent: ""))
        main.items[0].submenu = NSMenu(title: "OS Widget")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}
