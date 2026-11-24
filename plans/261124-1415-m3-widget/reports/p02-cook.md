# Báo cáo cook: Đọc kho, snapshot và hộp thư thao tác

Session `m3-widget-p02-cook`, ngày 2026-11-24. Nhánh `widget-snapshot-inbox`, worktree `/Users/onedayin20902/personal/os-widget-wt/widget-snapshot-inbox`, tách từ main `2901e8b` (main đã đi thêm một commit docs của plan M4 sau `6e04d86`, không đụng mã).

## Kết quả

`OSWidgetKit` có đủ bốn phần của phase: đọc `store.json` chỉ-đọc từ tiến trình khác, `WidgetSnapshot` so sánh được bằng `==`, hộp thư `ActionInbox` để widget ghi thao tác mà không ghi `store.json`, và `ItemStore.drain(_:)` để app rút hộp thư vào kho và hàng đợi M2. Định dạng `store.json` không đổi (vẫn `version` 1, cùng khoá).

| Commit | Nội dung |
|---|---|
| `d91d58f` | Tách `StoreFile` ra `Store/StoreFile.swift`; `ItemStore` dùng lại. 127 test cũ pass không sửa. |
| `7b81b96` | `StoreReader.read(location:) -> StoreContents?` và `StoreReaderTests` (4 test). |
| `d1210ae` | `WidgetAction`, `WidgetSnapshot.make(items:pending:now:limit:)` và `WidgetSnapshotTests` (9 test). |
| `e756773` | `ActionInbox`, `ItemStore.drain(_:)`, `Log.widget` và `ActionInboxTests` (9 test). |

## Kiểm

- `swift test` trong `apps/macos/OSWidgetKit`: 149 test trong 16 suite pass (127 cũ + 22 mới). Ba suite mới chạy lại riêng 5 lần, đều pass; không thấy test chập chờn.
- `cargo test --workspace`: 92 pass (23 + 7 + 26 + 36).
- `xcodegen generate` rồi `xcodebuild -project OSWidget.xcodeproj -scheme OSWidget -configuration Debug -derivedDataPath <scratchpad>/dd-p02 CODE_SIGNING_ALLOWED=NO build`: `BUILD SUCCEEDED`. Project sinh ra nằm trong `.gitignore`.
- `git grep -n "import WidgetKit" apps/macos/OSWidgetKit`: rỗng.
- `git grep -n "store.json\|StoreFile" apps/macos/OSWidgetKit/Sources`: chỉ trong `Store/` (`ItemStore.swift`, `StoreFile.swift`, `StoreReader.swift`).
- Sau khi xong, `pgrep -fl "xcodebuild|swift-build"` rỗng.

Bảng test của phase, theo test:

| Kiểm | Test |
|---|---|
| Đọc chỉ-đọc | `readsWhatTheStoreWroteWithoutChangingTheFile`, `missingFileReturnsNilAndCreatesNothing`, `corruptFileReturnsNilAndIsLeftAlone` |
| Tương thích | `menuBarAppStoreFileStillLoads` (fixture viết tay, có cả hàng đợi dạng `{"read":{"_0":true}}`) |
| Snapshot | `newestFirstCutAtTheLimitKeepingReadItems`, `sameCreationTimeOrdersByIdDescending`, `dropsDeletedAndExpiredAndCountsUnreadBeyondTheLimit`, `noExpiryWhenNoVisibleItemExpires`, `roundTripsThroughJSON` |
| Phủ thao tác | `pendingActionsAreLaidOverTheItems`, `pendingReadKeepsAnEarlierReadTime`, `pendingReadThenDeleteHidesTheItem` |
| So sánh | `equalAcrossTimeAndChangedOnlyByWhatTheWidgetShows` |
| Hộp thư | `submittedActionsArePendingOldestFirst`, `temporaryFilesAreIgnored`, `corruptFilesDoNotBlockOthersAndAreDrained`, `removeSkipsMissingFiles`, `submittingNeverTouchesTheStoreFile` |
| Rút | `drainFollowsTheStoreRulesAndSaves`, `drainedStoreMatchesTheSnapshotShownWhileWaiting` |
| Chết giữa chừng | `drainingAgainAfterDyingBeforeRemovalChangesNothing` |
| Đồng thời | `concurrentWritersWhileDrainingApplyEveryActionOnce` (8 luồng × 25 thao tác cho 200 mục khác nhau, rút liên tục trên `@MainActor`) |

## Khác với file phase và lý do

1. **`pending()` cộng thêm `contents()` và `removeCorrupt(_:)`.** Phase yêu cầu `pending() -> [WidgetAction]` mà vẫn trả danh sách file hỏng cho `drain`. Giữ đúng chữ ký `pending()` cho provider; `contents()` trả `actions` và `corrupt`, `drain` dùng nó rồi gọi `remove(_:)` và `removeCorrupt(_:)`.
2. **`drain` ghi thao tác với thời điểm bấm, và bỏ qua "đã đọc" cho mục đã đọc.** `drain` đi qua đúng hàm xếp hàng private mà `markRead` và `delete` dùng (cùng quy tắc gộp, mục đã xoá không nhận thao tác, xoá thắng đã đọc), chỉ khác là `createdAt` của thao tác lấy từ lúc bấm trên widget thay cho giờ của app. Lý do: kho sau khi rút bằng đúng snapshot widget đã hiện trong lúc chờ (test `drainedStoreMatchesTheSnapshotShownWhileWaiting`), nên Phase 3 không reload thừa một lần sau mỗi lần rút. Bỏ qua "đã đọc" cho mục đã đọc làm cho việc rút lại sau khi chết giữa chừng không thêm thao tác mới vào hàng đợi (nếu gọi thẳng `markRead`, hàng đợi đổi `id` và gửi lại). `drain` trả số thao tác thật sự đổi kho.
3. **File có tên không trùng `id` bên trong bị coi là hỏng.** `remove(_ ids:)` xoá theo `<id>.json`; một file đặt sai tên sẽ không bao giờ bị xoá và được áp lại mãi, nên `drain` xoá nó như file hỏng.
4. **"Đổi mục thứ 7 thì không" chỉ đúng khi không đổi số chưa đọc.** `unreadCount` đếm mọi mục hiển thị (theo yêu cầu của phase và câu hỏi 2: số chưa đọc ở đầu widget), nên đánh dấu đã đọc một mục thứ 7 đang chưa đọc làm snapshot khác (chỉ `unreadCount`). Test kiểm: sửa nội dung mục thứ 7 hoặc xoá mục thứ 7 đã đọc thì snapshot bằng nhau; đọc mục thứ 7 chưa đọc thì `items` giữ nguyên, `unreadCount` giảm 1. Phase 3 nên coi đó là thay đổi cần reload vì số trên widget đổi.
5. **Fixture tương thích viết ngay trong `StoreReaderTests.swift`**, không thêm file vào `Tests/OSWidgetKitTests/Fixtures/`, vì bảng sở hữu file không giao thư mục đó cho phase này.
6. **Thêm nhỏ:** `StoreContents` (kiểu trả về của `StoreReader`, đặt trong `StoreReader.swift`), `WidgetSnapshot.empty`, `ActionInbox.directory` và `ActionInbox.directoryName` công khai để Phase 5 theo dõi thư mục. `WidgetAction` mã hoá khoá dạng `item_id`, `created_at`, `operation` là `mark_read` hoặc `delete`.

Không sửa file nào ngoài bảng sở hữu của phase (ngoài `Model/Item.swift` chỉ thêm `Log.widget`, đúng như file phase ghi).

## Giới hạn còn lại

- File `.tmp-` do widget chết giữa lúc ghi sẽ nằm lại trong `inbox/`; không ảnh hưởng kết quả (bị bỏ qua) nhưng không ai dọn. Có thể thêm dọn file `.tmp-` cũ ở Phase 5 nếu cần.
- Ghi thật từ extension vào group container chưa kiểm (Phase 6, cần entitlement của Phase 1).
- Bước journal tự động của cook không chạy vì brief giới hạn phạm vi ghi của session này.

## Câu hỏi chưa giải quyết

Không có.
