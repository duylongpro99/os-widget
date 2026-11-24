---
phase: 8
title: "Thẻ vocab đầy đủ và phát âm"
status: completed
priority: P1
effort: "5h"
dependencies: []
---

# Phase 8: Thẻ `vocab` đầy đủ và phát âm

Client. Chạm `apps/macos/OSWidgetKit/`. Không phụ thuộc server mới (dựa trên định dạng body `vocab` ở architecture §3.2 đã có từ M1), nhưng không chạy cùng lúc với cook M3 đang sửa `Cards/CardView.swift` hoặc `Model/Item.swift`.

## Goal

Mục `vocab` hiện bằng thẻ riêng ở popup và danh sách với đủ trường của FR-15, có nút phát âm phát `audio_url` khi có và dùng `AVSpeechSynthesizer` khi không.

## Context

- `Model/Item.swift`: `ItemContent` có `.notification`, `.generic`, `.unknown`; chú thích ghi `vocab` giải mã thành `.unknown` cho tới khi có view.
- `Cards/CardView.swift`: `CardView.Variant`, `CardView.variant(for:)`, `CardHeader`, `CardFooter`, `CardSummary`, `CardMetrics.width` 340.
- `Cards/CardClick.swift`: `onCardClick` gắn `onTapGesture` cho cả thẻ; bấm thẻ đánh dấu đã đọc.
- `Cards/URLPolicy.swift`: `URLPolicy.loadableURL` chỉ nhận `https://` có host.
- Test hiện có `CardsTests.swift` kỳ vọng mục `vocab` trong fixture là `.fallback`; phase này đổi kỳ vọng đó.
- Architecture §6: phát âm chỉ ở popup và danh sách; FR-7: popup mặc định không phát âm thanh.

## Files to Create / Modify

Dưới `apps/macos/OSWidgetKit/`:

- Create: `Sources/OSWidgetKit/Model/VocabContent.swift`
- Modify: `Sources/OSWidgetKit/Model/Item.swift` (case `.vocab(VocabContent)` trong `ItemContent`, nhánh `"vocab"`)
- Create: `Sources/OSWidgetKit/Cards/VocabCardView.swift`
- Create: `Sources/OSWidgetKit/Cards/Pronunciation.swift`
- Modify: `Sources/OSWidgetKit/Cards/CardView.swift` (`Variant.vocab`, nhánh view)
- Modify: `Sources/OSWidgetKit/Cards/CardPreviews.swift` (preview thẻ `vocab` có và không có `audio_url`)
- Create: `Tests/OSWidgetKitTests/VocabTests.swift`
- Modify: `Tests/OSWidgetKitTests/CardsTests.swift` (kỳ vọng `.vocab` thay `.fallback`)
- Modify: `Tests/OSWidgetKitTests/Fixtures/items.json` chỉ khi cần thêm mục `vocab` có `context` và `antonyms`

## Thiết kế

**`VocabContent`** (`Sendable`, `Hashable`): `word`, `ipa`, `pos`, `audioURL: String?`, `meanings: [(definition, examples)]`, `context: String?`, `synonyms`, `antonyms`. Giải mã từ `JSONValue`: thiếu hoặc rỗng một trong `word`, `ipa`, `pos`, hoặc không có nghĩa nào có `definition` → `ItemContent.unknown` (thẻ dự phòng, FR-17). Trường tuỳ chọn sai kiểu bị bỏ qua.

**`VocabCardView`** trong độ rộng `CardMetrics.width`:

1. Hàng đầu: `word` (font lớn, đậm theo trạng thái đọc như `CardHeader`), `ipa` (đơn cách, màu phụ), nhãn `pos`, nút phát âm `speaker.wave.2` (nhãn trợ năng "Phát âm").
2. Nghĩa đánh số, tối đa 3; mỗi nghĩa tối đa 1 ví dụ in nghiêng.
3. Ngữ cảnh (nếu có): khối trích dẫn, tối đa 4 dòng.
4. "Đồng nghĩa" và "Trái nghĩa" (nếu có): danh sách cách nhau bằng dấu phẩy, mỗi dòng tối đa 2 dòng.
5. `CardFooter` như các thẻ khác.

Text là dữ liệu thuần (không render markdown hay HTML).

**Phát âm** (`Pronunciation.swift`):

- `enum PronunciationSource { case audio(URL), speech(String) }` và hàm thuần `choose(word:audioURL:)`: `URLPolicy.loadableURL(audioURL)` khác nil → `.audio`, ngược lại `.speech(word)`.
- `@MainActor final class Pronouncer` dùng chung: `.audio` phát bằng `AVPlayer`; phát lỗi (không tải được, hết thời gian 5 giây) thì đọc bằng `AVSpeechSynthesizer` với giọng `en-US`. Bấm lần nữa khi đang phát thì dừng và phát lại từ đầu.
- Log `os.Logger` category `audio`: `pronounce.play source=audio|speech`, `pronounce.fallback reason=…`; không ghi URL hay từ.
- Chỉ phát khi bấm nút; không tự phát khi popup mở (FR-7).
- Bấm nút không được kích hoạt `tap` của `onCardClick` (không đánh dấu đã đọc). Nếu `Button` trong thẻ vẫn để `onTapGesture` cha chạy, dùng cơ chế chặn tương tự `CardClickGate` và test nó.

## Tasks & Steps

- [ ] `VocabContent` và nhánh `"vocab"` của `ItemContent`; sửa chú thích "vocab decodes to .unknown".
- [ ] `VocabCardView`, `Variant.vocab`, nhánh trong `CardView.body`.
- [ ] `Pronunciation.swift` và preview.
- [ ] `VocabTests.swift`: mục `vocab` của fixture giải mã thành `.vocab` với đúng trường; thiếu `ipa` → `.unknown`; `meanings` rỗng → `.unknown`; `synonyms` sai kiểu bị bỏ, phần còn lại vẫn giải mã; `choose` trả `.audio` cho `https://…mp3`, `.speech` cho `nil`, `http://…`, `https://` không host.
- [ ] Sửa `CardsTests.swift`: mục `vocab` là `.vocab`; tập biến thể của mẫu gồm `.vocab`.
- [ ] Kiểm tay trong Xcode preview: thẻ với từ dài, 3 nghĩa, ngữ cảnh dài không vượt độ rộng.

## Verification

- `swift test` trong `apps/macos/OSWidgetKit` pass (127 test cũ cộng test mới).
- `xcodegen generate` rồi `xcodebuild -project apps/macos/OSWidget.xcodeproj -scheme OSWidget -configuration Debug build` thành công.
- `git grep -n "vocab decodes to" apps/macos` không còn kết quả.

## Risk Assessment

- Thẻ cao hơn popup cho phép: giới hạn số nghĩa, ví dụ và dòng như trên; nếu popup có chiều cao cố định, cuộn trong thẻ thay vì cắt.
- `AVPlayer` trong app sandbox cần quyền mạng: app đã có `com.apple.security.network.client`.
- Giọng `en-US` không có trên máy: `AVSpeechSynthesisVoice(language:)` trả nil thì dùng giọng mặc định.
- Xung đột với cook M3 trên `CardView.swift` và `Item.swift`: supervisor xếp lịch; cook rebase trước khi commit.
- Nếu Phase 4 của M3 đã merge, `CompactCardView.variant(for:)` là `switch` đủ trường hợp trên `ItemContent`, nên thêm `.vocab` làm nó không biên dịch: phase này thêm đúng một dòng `case .vocab: .fallback` vào `Cards/Compact/CompactCardView.swift` (Phase 9 thay bằng bố cục thật). Nếu Phase 4 của M3 chưa merge, cook M3 thêm dòng đó khi rebase.

## Rollback

Revert commit; mục `vocab` quay về thẻ dự phòng.
