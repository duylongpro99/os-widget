# Báo cáo cook Phase 8: Thẻ `vocab` đầy đủ và phát âm

Session `m4-vocab-p08-cook`, ngày 2026-11-24. Nhánh `vocab-card-pronunciation`, worktree
`/Users/onedayin20902/personal/os-widget-wt/vocab-card-pronunciation`, tách từ `main` tại `934c66c` (đã gồm merge
chính sách reload của widget). Chưa merge vào `main`.

## Kết quả

Mục `vocab` giờ hiện bằng thẻ riêng ở popup và danh sách với đủ trường FR-15, có nút phát âm. Nút phát `audio_url` khi
URL là `https://` có host, và đọc từ bằng `AVSpeechSynthesizer` (giọng `en-US`, không có thì giọng mặc định) khi không có
URL hợp lệ, khi audio lỗi, hoặc khi audio chưa phát sau 5 giây. Bấm lần nữa thì dừng và phát lại từ đầu. Không có gì tự
phát khi popup mở.

## Commit

| Commit | Nội dung |
|---|---|
| `feecb09` | `VocabContent`, `ItemContent.vocab`, nhánh `"vocab"`; bỏ chú thích "vocab decodes to .unknown"; thẻ và widget tạm vẫn dùng dự phòng; test giải mã. Gồm hai thay đổi ngoài danh sách file (xem Sai khác). |
| `6582dee` | `Pronunciation.swift`: `PronunciationSource.choose`, `Pronouncer` với trình phát tiêm vào, `AVPlayer` và `AVSpeechSynthesizer`, log category `audio`; test. |
| `ce40467` | `VocabCardView`, `CardView.Variant.vocab`, preview có và không có `audio_url` (kể cả bản dài); sửa `CardsTests`. |
| `6518a59` | Test timeout của `Pronouncer` chờ kết quả (tối đa 5 giây) thay vì ngủ cố định 300 ms. |

## Kiểm tra

- `swift test`: 183 test pass (168 trên `main` cộng 15 mới), chạy ba lần liên tiếp sau `6518a59`, không có cảnh báo biên dịch.
- `cargo test --workspace`: 151 pass, 0 lỗi.
- `xcodegen generate` rồi `xcodebuild -project OSWidget.xcodeproj -scheme OSWidget -configuration Debug -derivedDataPath <scratchpad> CODE_SIGNING_ALLOWED=NO build`: BUILD SUCCEEDED.
- `git grep -n "import WidgetKit" apps/macos/OSWidgetKit` và `git grep -n "vocab decodes to" apps/macos`: rỗng. Grep secret: rỗng.
- Thay cho xem preview trong Xcode: render `CardPreviewSamples.vocab` và `vocabLong` (từ 45 ký tự, 4 nghĩa, ngữ cảnh dài,
  20 từ đồng nghĩa và trái nghĩa) bằng `ImageRenderer` ra PNG ngoài repo. Thẻ giữ đúng 340 pt, tối đa 3 nghĩa và 1 ví dụ,
  ngữ cảnh 4 dòng, mỗi danh sách 2 dòng. Test `everyCardRendersAtCardWidth` giờ gồm mẫu dài này.

Test mới theo phase file: mục `vocab` của fixture thành `.vocab` đúng trường; thiếu `ipa` (và `word`, `pos`, `meanings`)
thành `.unknown`; `meanings` rỗng hoặc không có `definition` thành `.unknown`; `synonyms` sai kiểu bị bỏ, phần còn lại
vẫn giải mã; `choose` trả `.audio` cho `https://…mp3` và `.speech` cho `nil`, `http://…`, `https://` không host. Thêm:
`Pronouncer` đọc khi không có audio, không đọc khi audio đã phát, đọc đúng một lần khi audio lỗi, đọc khi quá hạn, bấm lại
thì dừng và bỏ sự kiện muộn của lần trước; giới hạn số nghĩa và ví dụ của thẻ.

## Sai khác so với phase file

1. **Hai file ngoài danh sách sở hữu**, đã được supervisor chấp nhận (14:5x) vì `switch` đủ trường hợp buộc phải sửa:
   `Tests/OSWidgetKitTests/ModelDecodingTests.swift` (chỉ test `vocabIsUnknownButKeepsTitleAndSummary`, đổi tên thành
   `vocabDecodesAndKeepsTitleAndSummary`, kỳ vọng `.vocab`, giữ kiểm title, summary, body), và trong
   `CompactCardView.detail(for:)` đổi `case .unknown:` thành `case .vocab, .unknown:` ngoài dòng `case .vocab: .fallback`
   ở `variant(for:)`. Hành vi widget không đổi: mục `vocab` vẫn hiện summary.
   Supervisor muốn hai thay đổi này ở commit riêng; không làm được mà mọi commit vẫn biên dịch, vì `case .vocab` chỉ tồn
   tại sau khi thêm `ItemContent.vocab`. Chúng nằm trong `feecb09` cùng phần thêm case đó.
2. **`Fixtures/items.json` không sửa.** Test cần `context`, `antonyms` và `audio_url` dùng body dựng trong test.
3. **Hàng đầu thẻ xuống hai dòng khi từ dài** (`ViewThatFits`): khi một hàng không đủ chỗ, `ipa` và `pos` xuống dòng thứ
   hai thay vì bị ép mất.
4. **Thời hạn 5 giây** tính tới khi `AVPlayerItem` sẵn sàng phát (`readyToPlay`); lỗi trong khi phát
   (`failedToPlayToEndTime`) cũng chuyển sang đọc.

## Hạn chế chưa kiểm

- **Bấm nút phát âm có kích hoạt `onCardClick` (đánh dấu đã đọc) không** chưa kiểm được bằng tay, vì brief không cho chạy
  app. Nút là `Button` kiểu `.borderless`; theo cách SwiftUI xử lý gesture, nút con nhận cú bấm trước `onTapGesture` của
  cha. Nếu kiểm tay cho thấy thẻ vẫn bị đánh dấu đã đọc, cách sửa là cho nút báo cho `CardClickGate` như liên kết, việc này
  phải sửa `Cards/CardClick.swift` (ngoài danh sách file của phase 8). Nên kiểm ở Phase 10.
- Chưa phát âm thanh thật (đúng brief); `SystemAudioPlayback` và `SystemSpeechPlayback` chỉ được biên dịch, chưa chạy.
