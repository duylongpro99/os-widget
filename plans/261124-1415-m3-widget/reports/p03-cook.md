# Báo cáo cook phase 3: chính sách reload và đếm reload

Nhánh `widget-reload-policy` (worktree `/Users/onedayin20902/personal/os-widget-wt/widget-reload-policy`), tách từ main `8e229c3`. Chưa merge.

## Đã làm

| Commit | Nội dung |
|---|---|
| 5464c24 | Ghi câu trả lời operator (D9, D10, D11, mỗi câu nguyên văn "A", 2026-11-24 14:24) và quyết định của giám sát (câu 2 đến 5, và snapshot chỉ khác số chưa đọc vẫn reload) vào `plan.md`: cột trạng thái và mục "Operator answers". Ngưỡng D9 ghi rõ là ngưỡng đạt/trượt của script đếm. |
| bb71106 | `WidgetReloadPolicy` (thuần, không timer, không đồng hồ riêng) và 9 test. |
| 707421c | `scripts/widget-reload-count.sh` và `scripts/testdata/widget-log-sample.ndjson`. |
| 161a103 | Thân `App/Widget/WidgetReloader.swift`. |

## Kiểm

- `swift test`: 158 pass (149 cũ cộng 9 mới). `cargo test --workspace`: 105 pass.
- `xcodegen generate` rồi `xcodebuild -scheme OSWidget -configuration Debug CODE_SIGNING_ALLOWED=NO build` với derivedDataPath ngoài repo: BUILD SUCCEEDED.
- `git grep -n "import WidgetKit" apps/macos/OSWidgetKit`: rỗng.
- `git grep -n "reloadTimelines" apps/macos`: một lệnh gọi, trong `WidgetReloader.swift`; ngoài ra chỉ có một dòng chú thích trong `WidgetKind.swift` (file của phase 1, không sửa).
- Script trên file mẫu in đúng số đã ghi trong đầu script: `requests=7 (first=1 changed=4 trailing=2)`, theo giờ `08:1 09:1 10:4 14:1`, `timelines=9`, `min_gap_ms=5000`, p50=200 p95=8000 max=8000 ms, 1 trong 7 yêu cầu không có timeline trong 5 s, dòng cuối `requests=7 min_gap_ms=5000 within_5s=85.7 timelines=9 verdict=FAIL` (mẫu cố ý có một yêu cầu trễ 8 s). Đầu vào rỗng cho `requests=0 ... verdict=PASS`. `bash -n` và `shellcheck` sạch. `log show` thật chạy được (không có dòng nào vì app chưa chạy bản này).
- Không có test chập chờn.

## Quyết định thiết kế

- `fire(at:)` tự ghi nhận lần reload khi trả `true` (đúng phase file: "coi như đã reload"); `didReload` dành cho đường `.reloadNow`.
- Khi đang chờ hẹn giờ, mọi `offer` chỉ thay snapshot đang chờ và trả `.skip`, kể cả khi bằng snapshot đã reload; `fire` trả `false` nếu cuối cùng nội dung quay về như cũ.
- `reloadsToday` cuộn về 0 ở lần `offer`, `fire` hoặc `didReload` đầu tiên của ngày mới (lịch của máy, tiêm được để test bằng UTC).
- Snapshot dùng `Item` đầy đủ nên "đổi nội dung" gồm cả số chưa đọc, theo quyết định của giám sát. `ItemStore.drain` áp thao tác bằng `createdAt` của thao tác, trùng với phủ hộp thư, nên áp xong không sinh reload thừa.
- Script: PASS cần ≤ 40 yêu cầu, khoảng cách nhỏ nhất ≥ 5000 ms, ≥ 95% yêu cầu có timeline trong 5 s (ghi đè được bằng biến môi trường). Không có yêu cầu nào thì PASS.

## Lệch so với phase file

- Dòng `.schedule` cũng ghi `widget.reload_skipped reason=coalesced` ở mức debug (phase file chỉ nói `.skip`); không ảnh hưởng số đếm.
- Reloader tự gọi `StoreLocation.appGroup()` để biết hộp thư và để quyết định `widget.reload_disabled reason=no_container`, vì `ItemStore` không lộ vị trí (không sửa file của phase khác). Hệ quả: kho trong bộ nhớ mà group container vẫn mở được thì reloader vẫn chạy.
- `WidgetReloader.init` có thêm ba tham số mặc định (chính sách, đồng hồ, hàm gọi reload) để test được sau này; chữ ký `init(env:)` và `start()` giữ nguyên.
- Dòng cuối trailer commit ghi `Claude Sonnet 5.5` (mô hình thật của session) thay cho `Claude Opus 5.5` trong brief.

## Chưa kiểm

- `WidgetReloader` chưa có unit test (nằm ở target app, không có test target) và chưa chạy trong app thật: không cài, không chạy app, đúng phạm vi. Phase 6 kiểm bằng log thật.
