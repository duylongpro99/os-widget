# Báo cáo review Phase 8: Thẻ `vocab` đầy đủ và phát âm

Session `m4-vocab-p08-review`, ngày 2026-11-24. Nhánh `vocab-card-pronunciation` (head cook `54c19ec`) đã được review,
sửa hai lỗi nhỏ ngay trên nhánh, rồi merge vào `main` bằng `--no-ff` tại `2d1be85`. Phase 8 đã đánh dấu Completed.

## Kết luận

Code đạt yêu cầu phase. Thẻ hiện đủ các trường FR-15, phát âm chỉ chạy khi người dùng bấm nút, và test là test thật.
Review tìm ra hai lỗi, cả hai đã sửa trên nhánh trước khi merge:

| Commit | Lỗi và cách sửa |
|---|---|
| `f654dcf` | Bấm nút phát âm có thể lọt lên `onTapGesture` của thẻ. Khi đó mục bị đánh dấu đã đọc và `item.url` bị mở trong trình duyệt. `CardClick.swift` giờ có giá trị môi trường `cardControlClicked` và hàm `CardClickGate.controlClicked(at:)`. Nút gọi giá trị này trước khi phát, nên cú bấm của thẻ bị bỏ giống như khi bấm link. Có test `cardTapIsDroppedForTheClickHandledByAControl`. |
| `f14decf` | `SystemAudioPlayback` giữ `AVPlayer` và item sau khi phát xong, cho tới lần bấm sau. Giờ có thêm observer `didPlayToEndTime` gọi `stop()`, chỉ khi item đó vẫn là item hiện tại. |

Trước khi sửa, nhánh đã merge `main` (`fcc25cb`) và không có xung đột.

## Câu hỏi nút phát âm và click của thẻ

Đọc code thì không chắc được. Theo luật gesture của SwiftUI, `Button` con thường nhận cú bấm trước `onTapGesture` của
cha, nhưng trên macOS không có gì đảm bảo điều đó, nhất là khi thẻ nằm trong `ScrollView` hoặc `List`. Hậu quả nếu cú
bấm lọt lên cha khá nặng: mục bị đánh dấu đã đọc và trình duyệt mở link của mục. Vì vậy review chọn chặn chủ động bằng
cơ chế `CardClickGate` sẵn có (commit `f654dcf`). Nếu SwiftUI vốn đã không gửi cú bấm lên cha thì chốt chặn này không
làm gì. Phase 10 vẫn nên kiểm tay một lần: bấm nút phát âm trong popup và trong danh sách, mục phải còn chưa đọc và không
có trình duyệt nào mở.

## Các mục đã kiểm

- **Không chặn main actor.** `Pronouncer` chạy trên main actor nhưng chỉ gọi các API không đồng bộ (`AVPlayer.play`,
  `AVSpeechSynthesizer.speak`). Thời hạn chờ dùng `Task.sleep`. Callback KVO được chuyển về main bằng `Task`.
- **Giải phóng player và synthesizer.** Player được nhả khi phát hết (sau `f14decf`), khi lỗi, khi bị dừng hoặc khi
  bấm lại. Observer KVO và notification được gỡ trong `stop()`. Synthesizer là một instance chung, sống cùng `Pronouncer.shared`.
- **`audio_url` chặt hơn yêu cầu.** Chỉ `https` có host mới được tải (`URLPolicy.loadableURL`). `http`, `file:` và
  `https` không có host đều chuyển sang đọc bằng giọng máy; test `otherAudioURLsFallBackToSpeech` có trường hợp `file:///tmp/a.mp3`.
- **Log không chứa từ hay URL.** Chỉ có `pronounce.play source=…` và `pronounce.fallback reason=…`, với `reason` là
  mã cố định (`load`, `play`, `timeout`).
- **Test timeout không còn phụ thuộc thời gian.** Bộ test chạy 3 lần liên tiếp đều pass (184 test).
- **Trường FR-15.** word, ipa, pos và nút phát âm ở hàng đầu; nghĩa đánh số (tối đa 3, mỗi nghĩa 1 ví dụ); context;
  synonyms; antonyms; footer. Trường tuỳ chọn bị thiếu (`context`, danh sách rỗng) không render view nào, nên không để
  lại khoảng trống. Mọi text đều dùng `Text(verbatim:)`.
- **Không có `import WidgetKit`** trong OSWidgetKit, và không còn chuỗi "vocab decodes to".
- **Thử đột biến.** Bỏ `speech.speak(word)` trong `fallBack` làm hỏng 3 test (`failedAudioIsSpokenOnce`,
  `pronouncingAgainStopsAndRestarts`, `audioThatDoesNotStartInTimeIsSpoken`). Đã hoàn lại code sau khi thử.

## Kiểm tra trên `main` sau merge

- `swift test`: 184 pass.
- `cargo test --workspace`: 187 pass, 0 lỗi.
- `xcodegen generate` rồi `xcodebuild … -derivedDataPath <scratchpad> CODE_SIGNING_ALLOWED=NO build`: BUILD SUCCEEDED.

## Hạn chế

- Chưa phát âm thanh thật và chưa chạy app (đúng brief). `SystemAudioPlayback`, `SystemSpeechPlayback` và chốt chặn
  nút trong thẻ mới chỉ được biên dịch, chưa chạy trên giao diện thật; cần kiểm tay ở Phase 10.
