# Báo cáo review: Đọc kho, snapshot và hộp thư thao tác

Session `m3-widget-p02-review`, ngày 2026-11-24. Nhánh `widget-snapshot-inbox` (head `d47b3be`, tách từ main `2901e8b`).

## Kết quả

Không có finding nào cần sửa mã; nhánh đã merge vào main bằng `--no-ff` ở commit `1b4be10`, không xung đột với phase 1 (`WidgetKind.swift`) hay các merge M4. Phase 2 đã đánh dấu Completed trong `plan.md` và file phase.

## Đã kiểm

- **`StoreReader` chỉ đọc.** Chỉ gọi `Data(contentsOf:)` trên `location.baseDirectory` (không gọi `StoreLocation.directory()` vốn tạo thư mục), không khoá, không ghi, không xoá. Test `readsWhatTheStoreWroteWithoutChangingTheFile` kiểm nội dung và mtime không đổi; `missingFileReturnsNilAndCreatesNothing` kiểm không tạo thư mục. `ItemStore.save()` vẫn là đường ghi `store.json` duy nhất; `git grep "store.json\|StoreFile"` trong `Sources` chỉ thấy ở `Store/`. Định dạng `StoreFile` giữ nguyên khoá và `version` 1, có fixture tương thích M2.
- **Ghi hộp thư nguyên tử.** `submit` ghi `.tmp-<uuid>.json` trong chính `inbox/` rồi `moveItem` (rename cùng thư mục), xoá file tạm khi lỗi. `contents()` bỏ qua `.tmp-`; file biến mất giữa lúc liệt kê và đọc được bỏ qua, không bị coi là hỏng.
- **Rút idempotent, xoá thắng đã đọc (architecture §5).** `drain` đi qua đúng `enqueue` private của `markRead`/`delete`: mục đã xoá không nhận thao tác nào, đọc sau xoá bị bỏ, xoá sau đọc thay thao tác đọc trong hàng đợi. Rút lại sau khi chết giữa chừng: mục đã đọc bỏ qua "đã đọc", mục đã xoá bỏ qua mọi thứ, nên `items` và `queue` không đổi (test `drainingAgainAfterDyingBeforeRemovalChangesNothing`, cả qua một `ItemStore` nạp lại từ đĩa). Chỉ xoá các file đã liệt kê trong lần rút này, nên file widget ghi thêm trong lúc rút không bị mất.
- **Test đồng thời là thật.** 8 writer trong `Task.detached` ghi song song với vòng rút trên `@MainActor`; kiểm 200 thao tác áp đúng, không file hỏng, hộp thư rỗng, kho nạp lại bằng kho trong bộ nhớ.
- Các quyết định của supervisor (1)–(5) khớp mã: `contents()`/`removeCorrupt`, thời điểm bấm và bỏ qua đọc lặp, file sai tên coi là hỏng, `unreadCount` đếm mọi mục, fixture inline.

## Mutation

1. Bỏ `guard !item.isRead` trong `drain` (rút lại áp "đã đọc" lần hai): `drainingAgainAfterDyingBeforeRemovalChangesNothing` fail với 2 issue. Đã hoàn lại.
2. Bỏ bước rename trong `submit` (ghi thẳng vào `<uuid>.json`): cả 9 test của suite vẫn pass ở 3 lần chạy. File thao tác chỉ khoảng 150 byte, ghi bằng một lần `write`, nên test không quan sát được file dở. Tính nguyên tử chỉ được kiểm bằng đọc mã, không bằng test. Đã hoàn lại.

## Kiểm trên main sau merge

- `swift test` (`apps/macos/OSWidgetKit`): 149 test, 16 suite, pass.
- `cargo test --workspace`: 105 pass (23 + 7 + 26 + 13 + 36; 13 test mới của `crates/envelope` đến từ merge M4).
- `xcodegen generate` rồi `xcodebuild ... -derivedDataPath <scratchpad>/dd-p02r CODE_SIGNING_ALLOWED=NO build`: `BUILD SUCCEEDED`.
- `pgrep -fl "xcodebuild|swift-build"` rỗng.

## Follow-up (không chặn)

- File `.tmp-` sót lại khi widget bị giết giữa lúc ghi không ai dọn (vô hại, đã được supervisor chấp nhận). Phase 5 có thể dọn file `.tmp-` cũ hơn vài phút khi quét.
- Không có test nào bắt được việc bỏ rename (mutation 2). Muốn kiểm bằng test thì cần một điểm tiêm cho bước ghi; chưa đáng làm ở quy mô này.
- `StoreReader` ghi `store.reader_failed reason=missing` ở mức `error`; widget chạy trước lần ghi kho đầu tiên của app sẽ sinh dòng này. Có thể hạ xuống `notice` ở Phase 4 nếu thấy ồn.
- `drain` ghi `store.json` một lần cho mỗi thao tác (qua `enqueue`); không đáng kể với vài lần bấm.

## Câu hỏi chưa giải quyết

Không có.
