#if DEBUG
import SwiftUI

/// A kind with no view at all, shaped like the `weather` item of the test fixtures.
private let weatherSample = Item(
    id: "preview-weather", kind: "weather", source: "weather-cron",
    title: "Hà Nội 18°C", summary: "Trời nhiều mây, chiều có mưa nhỏ",
    body: .object(["temp_c": .number(18), "condition": .string("cloudy")]),
    createdAt: CardPreviewSamples.created
)

private struct CompactPreviewList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CompactCardView(item: CardPreviewSamples.notification, lines: 4)
            CompactCardView(item: CardPreviewSamples.generic)
            CompactCardView(item: CardPreviewSamples.vocab, lines: 1)
            CompactCardView(item: weatherSample, lines: 1)
        }
        .padding()
        .frame(width: 300)
    }
}

#Preview("Compact notification") { CompactCardView(item: CardPreviewSamples.notification).padding().frame(width: 300) }
#Preview("Compact generic, read") { CompactCardView(item: CardPreviewSamples.generic).padding().frame(width: 300) }
#Preview("Compact vocab fallback") { CompactCardView(item: CardPreviewSamples.vocab).padding().frame(width: 300) }
#Preview("Compact weather fallback") { CompactCardView(item: weatherSample).padding().frame(width: 300) }
#Preview("Compact all") { CompactPreviewList() }
#Preview("Compact all, dark") { CompactPreviewList().preferredColorScheme(.dark) }
#endif
