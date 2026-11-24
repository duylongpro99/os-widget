import SwiftUI
import WidgetKit

/// Entry point of the widget extension. It declares every widget the extension offers.
@main
struct OSWidgetWidgetBundle: WidgetBundle {
    var body: some Widget {
        ItemsWidget()
    }
}
