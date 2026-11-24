# Báo cáo nghiệm thu Giai đoạn 2: App thanh menu

## Tóm tắt

| Tiêu chí | Kết quả |
|---|---|
| 1. Popup trong 5 giây (PRD §10.1) | PASS, `latency_ms=781` (lần chạy của operator); các lần kiểm không cần operator: 334–650 ms |
| 3a. Đã đọc từ thiết bị khác, giả bằng API (PRD §10.3) | PASS, app áp dụng `item.read` seq 425, operator thấy mục thành đã đọc |
| 3b. Đã đọc từ MacBook sang server (PRD §10.3) | PASS, `GET /items` có `read_at`, `GET /events` có `item.read` seq 427 |
| 4. Mất mạng, ba mục từ máy khác (PRD §10.4) | Hoãn: chưa có máy thứ hai (operator hiện chỉ có MacBook, 2026-11-23) |
| 6. Loại chưa có view (PRD §10.6) | PASS, mục `vocab` hiện `title` và `summary` bằng view dự phòng |
| Focus | Chưa kiểm được: lần chạy 09:05 không có popup vì danh sách mục đang mở (`popup.suppressed reason=list_open`); chờ operator chạy lại |

Còn chờ operator: chạy lại `focus`; đăng xuất rồi đăng nhập lại (app tự chạy, không có icon Dock); để máy ngủ qua đêm (mục publish trong đêm có trong danh sách, có vòng sync sau khi thức); tiêu chí 4 khi có máy thứ hai.

## Môi trường

- Ngày chạy: 2026-11-23 22:40 đến 2026-11-24 09:10 (Asia/Saigon), trên MacBook.
- macOS 27.2.1 (26B131); Xcode 27.2 (27B52); xcodegen 2.48.0.
- Mã app: nhánh `macos-acceptance`, commit `804e582` (mã của `main` 27b582b cộng bản sửa menu Edit, xem Ghi chú). Script nghiệm thu: commit `d3d7d6f`.
- Build Release bằng `xcodebuild -allowProvisioningUpdates`, derived data ngoài repo, copy vào `/Applications/OSWidget.app`. Ký Apple Development của Personal Team `22LZWPB3XL`, dùng lại chứng chỉ có sẵn: số identity ký trước và sau không đổi (một Apple Development), không chứng chỉ nào được tạo hay thu hồi.
- `codesign --verify --deep --strict` đạt. Entitlement: `app-sandbox`, `network.client`, `application-groups` = `22LZWPB3XL.os-widget` (thêm `get-task-allow` như mọi bản ký Apple Development).
- Đồng hồ: `sntp time.apple.com` lệch +0,0017 s (2026-11-23 22:42) và −0,00005 s (2026-11-24 09:10), không đáng kể so với `latency_ms`.
- Nhánh thử nghiệm A: "A đạt" (ký Personal Team, kho trong group container). Kết quả kiểm ngày 8 của thử nghiệm A (2026-11-30) còn chờ; nhánh có thể đổi khi đó (operator quyết định 2026-11-23 22:35 không chờ).
- WidgetProbe không bị đụng: mtime bundle `1795358837` (22/11 21:47:17) và `Identifier=local.oswidget.probe` giống nhau trước và sau; digest đầu ra `codesign -dvvv` giống nhau.

## Kiểm app đang chạy (không cần operator)

- Chạy dưới dạng `UIElement`, sandboxed, không có icon Dock; mở lần hai (`open -n`) không để lại tiến trình thứ hai. Lần chạy đầu đăng ký mở khi đăng nhập: `login.set enabled=true status=SMAppServiceStatus(rawValue: 1)`.
- Trước khi cấu hình: `sync.not_configured`, `realtime.state not_configured`, không có lỗi `store.location_unavailable`.
- Sau khi operator nhập cấu hình (22:50): `sync.start` → `realtime.state joined` sau 1 s → `sync.reconcile items=0` → `sync.applied seq=373..392`. `store.json` được tạo trong group container `22LZWPB3XL.os-widget`.
- Publish bằng CLI lúc 22:52:13.006: `sync.start` sau 0,39 s (tín hiệu Realtime, không phải poll) → `sync.applied seq=383..403 new=1` → `popup.shown … latency_ms=650`.
- `PATCH /items/{id}` `{"read":true}` bằng token client: `sync.applied` sau dưới 1 s. `DELETE`: `sync.applied` sau dưới 1 s.
- `lsof`: đúng một kết nối TLS tới Supabase (WebSocket Realtime, cùng socket từ lúc join) và một tới Worker.

## Đầu ra `scripts/acceptance-server.sh`

Chạy lại 2026-11-24 08:40, token và khoá lấy từ Keychain vào biến môi trường, không in ra. Lần chạy 2026-11-23 22:51 trượt tiêu chí 6 vì mục Keychain của khoá publishable lưu sai giá trị (6 ký tự); operator lưu lại thì đạt.

```text
run acceptance-20261124T084019-26059 against https://os-widget.longdaobk17.workers.dev
starting at seq 405
PASS 1 CLI publish 4460f948-3f59-4ac0-9d99-3bdb5cc0786f appears in GET /events as item.created with its item
PASS 2 invalid envelopes: no title -> 400 {"field":"","message":"missing field `title`"}; vocab without definition -> 400 {"field":"body.meanings[0]","message":"missing field `definition`"}; kind weather -> 400 {"field":"kind","message":"unknown kind `weather`, expected one of notification, vocab, generic"}
PASS 3 dedupe: first 201, second 200, same id 8acf6891-9f6e-4b23-af25-b78828bbfd19, one item.created
PASS 4 read/unread/delete on 80aa798c-a256-4281-a287-d5eb4ebad4b5: 204 with item.read, item.unread, item.deleted; repeats add no event; PATCH after delete 404
PASS 5 tokens: none -> 401, client token on POST /items -> 403, publish token on GET /events -> 403, wrong token -> 401
PASS 6 anon key: events -> 200 array, items -> 401 no rows, rpc/purge_old_rows -> 401 rejected
PASS limit: since=0&limit=500 -> 200 with 97 events (max 100), limit=0 -> 400
PASS default ttl: expires_at - created_at = 604800s (7 days = 604800s)
checks failed: 0
exit 0
```

## Đầu ra `scripts/acceptance-menu-bar.sh`

Operator chạy 2026-11-24 khoảng 09:03–09:05, lần lượt `1`, `3`, `6`, `focus` (tiêu chí 4 bỏ ra vì chưa có máy thứ hai). Đã bỏ các dòng nhắc và lặp lại; câu trả lời `y/n` của operator nằm trong dòng PASS/FAIL tương ứng.

```text
== 1. Popup within 5 seconds
published ee4b41e5-ac6c-48e6-ae9e-85d83361c1b3; waiting for popup.shown
log:  id=ee4b41e5-ac6c-48e6-ae9e-85d83361c1b3 others=0 latency_ms=781
PASS 1 popup shown for ee4b41e5-ac6c-48e6-ae9e-85d83361c1b3, latency_ms=781 (<= 5000)
cleanup: DELETE /items/ee4b41e5-ac6c-48e6-ae9e-85d83361c1b3 -> 204

== 3a. Read on another device (simulated by the API) reaches this Mac
log:  seq=405..425 new=0
PASS 3a PATCH read (seq 425) applied by the app; operator saw the item turn read
== 3b. Read on this Mac reaches the server
PASS 3b GET /items read_at set and GET /events item.read seq 427 for 7622dac1-1639-432d-b5e0-cf9f1426d37e
cleanup: DELETE /items/b228bc42-45ea-48c2-9da9-db66ac8132e1 -> 204
cleanup: DELETE /items/7622dac1-1639-432d-b5e0-cf9f1426d37e -> 204

== 6. Unknown kind shows title and summary
PASS 6 vocab item f9421d38-c83d-4e88-b99d-241c011d6390 shown with title and summary by the fallback view
cleanup: DELETE /items/f9421d38-c83d-4e88-b99d-241c011d6390 -> 204

== Focus. The popup does not take focus from TextEdit
FAIL focus: no popup.shown for 517ba3f3-76a9-4f00-a368-eac5985fd929 within 30 s
cleanup: DELETE /items/517ba3f3-76a9-4f00-a368-eac5985fd929 -> 204
```

Chẩn đoán lần `focus` trượt, từ log của app:

```text
09:05:07.628 sync.applied seq=413..433 new=1
09:05:07.651 popup.suppressed reason=list_open
09:05:19.772 sync.queue_sent id=517ba3f3-76a9-4f00-a368-eac5985fd929 status=204
```

Danh sách mục còn mở từ các bước trước (bước 3a yêu cầu mở danh sách), nên app không hiện popup, đúng thiết kế (FR-10c). Mục mới hiện trong danh sách, và đó là thứ operator thấy ("popup vẫn hiện"); 12 giây sau operator thao tác với mục đó trong danh sách. Tiêu chí focus vì vậy chưa được kiểm, không phải lỗi app. Script nay in lý do `popup.suppressed` thay cho chờ hết 30 giây và nhắc đóng danh sách trước (commit `d3d7d6f`).

## Checklist bằng mắt

Operator trả lời (qua session giám sát, 2026-11-24 khoảng 09:05): "tôi làm xong rồi, chỉ có bước này báo fail … nhưng thực tế popup vẫn hiện". Theo câu đó, mục 1–9 được ghi là đạt; session giám sát đã hỏi xác nhận từng mục nhưng chưa có trả lời riêng từng mục.

| # | Mục | Kết quả |
|---|---|---|
| 1 | Bấm liên kết trong thẻ chỉ mở liên kết đó, mục thành đã đọc | Đạt (theo câu trả lời chung) |
| 2 | Bấm icon khi danh sách đang mở thì danh sách đóng | Đạt (theo câu trả lời chung) |
| 3 | Menu chuột phải: dấu tích đúng và đổi khi bấm | Đạt (theo câu trả lời chung) |
| 4 | Giao diện sáng và tối | Đạt (theo câu trả lời chung) |
| 5 | Popup tự đóng sau 30 giây, dừng đếm khi chuột trong popup, tự đóng không đánh dấu đã đọc | Đạt (theo câu trả lời chung) |
| 6 | "+N mục khác" đóng popup và mở danh sách | Đạt (theo câu trả lời chung) |
| 7 | Popup hiện trên app toàn màn hình | Đạt (theo câu trả lời chung) |
| 8 | Panel vừa nội dung sau khi ảnh tải xong | Đạt (theo câu trả lời chung) |
| 9 | Icon trên thanh menu, không có icon Dock | Đạt (theo câu trả lời chung; không có icon Dock cũng xác nhận bằng `lsappinfo`) |
| 10 | Đăng xuất rồi đăng nhập lại: app tự chạy | Chờ operator |
| 11 | Ngủ qua đêm: mục trong đêm có trong danh sách, có sync sau khi thức | Chờ operator |
| 12 | Tiêu chí 4 | Hoãn: chưa có máy thứ hai |

## Ghi chú

- Lỗi tìm thấy khi cấu hình và đã sửa trên nhánh: ô trong cửa sổ Cài đặt không nhận ⌘V. App agent tự dựng `NSApplication` và không có main menu, nên AppKit không có mục menu nào chuyển phím tắt sửa chữ tới ô nhập. Sửa bằng main menu ẩn có menu Edit chuẩn (commit `804e582`); operator nhập được cấu hình sau khi cài lại.
- Quan sát cho review, chưa sửa: số "+N" của popup cộng dồn khi popup còn mở (others=0→4 trong lúc chạy `acceptance-server.sh`) và vẫn đếm cả mục đã bị xoá trong lúc đó (`PopupPolicy.merge`). Khi đổi cấu hình, log có `realtime.state send_failed` rồi `stopped` trước khi join lại trong 1 s, không ảnh hưởng.
- Dòng log mức info của app chỉ giữ trong bộ nhớ một thời gian ngắn; `log show` sau vài phút có thể không còn. Bằng chứng nằm trong đầu ra script lúc chạy.
- Mọi mục thử dùng `source: "acceptance-m2"`, `ttl` 3600 và đã được xoá (204).
