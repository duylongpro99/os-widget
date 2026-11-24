/// Widget kind strings shared by the app and the widget extension. The app passes one to
/// `reloadTimelines(ofKind:)` and the extension declares the same one in its configuration, so both
/// sides must read it from here. This file stays free of WidgetKit so the package can back a
/// non-widget desktop view too.
public enum WidgetKind {
    /// The items widget: the newest items with read and delete buttons.
    public static let items = "OSWidgetItems"
}
