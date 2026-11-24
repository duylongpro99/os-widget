import Foundation
import SwiftUI

public extension View {
    /// Click handling for a card. A click on the card runs `tap`. A click on a link inside the card
    /// (a `link` block or a markdown link) runs `link` with that URL instead, and only when
    /// `URLPolicy.isOpenable` accepts it; the same click never also runs `tap`. A control inside the card
    /// that calls the environment's `cardControlClicked` keeps its click from running `tap` the same way.
    func onCardClick(
        tap: @escaping @MainActor () -> Void,
        link: @escaping @MainActor (URL) -> Void
    ) -> some View {
        modifier(CardClickModifier(tap: tap, link: link))
    }
}

/// Tells a click on a card apart from a click on a link inside it. Links open through the environment's
/// `OpenURLAction`, which may run before or after the card's tap gesture for the same click, so the tap
/// is deferred to the next main-actor turn and dropped when a link opened within `linkWindow` of it.
@MainActor
final class CardClickGate {
    static let linkWindow: TimeInterval = 0.5

    private var lastLinkAt: TimeInterval?

    func linkOpened(at time: TimeInterval) {
        lastLinkAt = time
    }

    /// A button or other control inside the card handled the click at `time`; the card's tap is dropped
    /// for it like for a link.
    func controlClicked(at time: TimeInterval) {
        lastLinkAt = time
    }

    func allowsTap(at time: TimeInterval) -> Bool {
        guard let lastLinkAt else { return true }
        return abs(time - lastLinkAt) > Self.linkWindow
    }
}

public extension EnvironmentValues {
    /// Called by a control inside a card when it handles a click, so the card's own tap does not also run
    /// for that click. Outside `onCardClick` it does nothing.
    var cardControlClicked: @MainActor @Sendable () -> Void {
        get { self[CardControlClickedKey.self] }
        set { self[CardControlClickedKey.self] = newValue }
    }
}

private struct CardControlClickedKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable () -> Void = {}
}

private struct CardClickModifier: ViewModifier {
    let tap: @MainActor () -> Void
    let link: @MainActor (URL) -> Void
    @State private var gate = CardClickGate()

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard URLPolicy.isOpenable(url) else { return .discarded }
                gate.linkOpened(at: ProcessInfo.processInfo.systemUptime)
                link(url)
                return .handled
            })
            .environment(\.cardControlClicked) { [gate] in
                gate.controlClicked(at: ProcessInfo.processInfo.systemUptime)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                let time = ProcessInfo.processInfo.systemUptime
                Task { @MainActor in
                    if gate.allowsTap(at: time) {
                        tap()
                    }
                }
            }
    }
}
