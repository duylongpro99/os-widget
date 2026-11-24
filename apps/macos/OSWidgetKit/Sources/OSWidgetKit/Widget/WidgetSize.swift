/// The widget sizes the items widget supports and how many rows and lines each one shows. It stays free
/// of WidgetKit so the same numbers can size a non-widget desktop view; the extension maps its widget
/// family onto it.
public enum WidgetSize: String, Sendable, Hashable, CaseIterable {
    case medium
    case large

    /// The most item rows shown. Never more than `WidgetSnapshot.maxItems`.
    public var rowLimit: Int {
        switch self {
        case .medium: 3
        case .large: 6
        }
    }

    /// Detail lines of the first, newest row. The large size gives it more room so a richer compact card
    /// for a new kind fits there.
    public var leadRowLines: Int {
        switch self {
        case .medium: 2
        case .large: 4
        }
    }

    /// Detail lines of every row after the first.
    public var rowLines: Int { 1 }
}
