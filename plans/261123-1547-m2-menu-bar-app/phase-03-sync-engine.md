---
phase: 3
title: "Sync engine"
status: completed
priority: P1
effort: "6h"
dependencies: [2]
---

# Phase 3: Sync engine

## Goal

App giữ kho cục bộ khớp với server: đồng bộ đầu bằng `GET /items`, bắt kịp bằng `GET /events?since=` theo trang, nhận tín hiệu Realtime trên bảng `events`, poll dự phòng, bắt kịp sau khi máy thức dậy hoặc có mạng lại, đối chiếu định kỳ, và gửi hàng đợi thao tác.

## Context

- Không phụ thuộc thử nghiệm A hay B.
- Giao thức: architecture §5. API: architecture §4.1. Realtime: bảng `events` nằm trong publication `supabase_realtime`, khoá anon (publishable) chỉ có `select` trên `events` cùng chính sách RLS `anon can read events` (`supabase/migrations/20261123000000_access_realtime_cleanup.sql`).
- Supabase không phát lại sự kiện Realtime bị lỡ; tín hiệu chỉ là gợi ý, nguồn chân lý là `GET /events`.
- Làm song song được với Phase 4 và 5 sau khi Phase 2 xong; chỉ sửa file trong bảng sở hữu của plan.md.
- Client Realtime tự viết theo giao thức Phoenix của Supabase trên `URLSessionWebSocketTask`, không dùng `supabase-swift` (operator trả lời câu hỏi 2, 2026-11-23). Package không có phụ thuộc ngoài.

## Requirements

**API client** (`Sync/APIClient.swift`):

- `getItems() -> (seq, [Item])`, `getEvents(since:limit:) -> [ServerEvent]`, `patchRead(id:read:) -> Int` (mã trạng thái), `delete(id:) -> Int`. Header `Authorization: Bearer <token client>` lấy từ Keychain mỗi lần gọi (đổi token trong cài đặt có hiệu lực ngay). Timeout 15 giây.
- Giao thức `HTTPTransport` để test thay bằng bản giả; bản thật dùng `URLSession`.
- `id` đưa vào đường dẫn đúng như server trả.

**Engine** (`Sync/SyncEngine.swift`, `actor`):

- Một vòng `sync()` không bao giờ chạy chồng: tín hiệu tới khi đang chạy chỉ đặt cờ "cần chạy lại", vòng hiện tại xong thì chạy thêm đúng một lần.
- Thứ tự trong một vòng: gửi hàng đợi, rồi fetch.
  - Cursor `nil` (lần đầu hoặc kho hỏng): `GET /items`, `replaceAll`, không popup.
  - Có cursor: gọi `GET /events?since=<max(0, cursor - 20)>` (lùi 20 để bắt khe hở thứ tự commit, architecture §5), lặp trang khi nhận đủ 100 sự kiện, mỗi trang gọi `apply(events:)`. Gom mục mới của mọi trang trong vòng rồi gọi `store.announce(_:)` một lần ở cuối vòng (bỏ qua khi rỗng); popup ở Phase 5 quan sát thông báo này.
- Đối chiếu bằng `GET /items` + `replaceAll` khi: `lastFullSyncAt` cũ hơn 6 giờ; hoặc máy thức dậy sau khi ngủ quá 24 giờ (bao trùm trường hợp ngoại tuyến lâu hơn 30 ngày giữ sự kiện, architecture §5). Đối chiếu chạy sau bước fetch sự kiện, nên mục mới vẫn được popup.
- Gửi hàng đợi: lần lượt từng thao tác, xử lý theo `outcome(for:)` của Phase 2. Gặp 401 hoặc 403: dừng gửi trong vòng này, ghi log `sync.auth_failed`. Gặp lỗi mạng hoặc 5xx: dừng, thử lại ở vòng sau.
- Thử lại khi lỗi: lùi dần 2, 4, 8 … tối đa 60 giây cho lỗi mạng hoặc 5xx; không lùi dần khi tín hiệu mới tới.
- Kích hoạt `sync()` khi: app khởi động; tín hiệu Realtime; Realtime kết nối lại; `NSWorkspace.didWakeNotification`; `NWPathMonitor` chuyển sang `satisfied`; người dùng thao tác (đã đọc, xoá) để gửi hàng đợi ngay; poll dự phòng mỗi 5 phút (architecture §8: vài phút là đủ thưa). Khi không có token hoặc URL thì không chạy và ghi log một lần.

**Realtime** (`Sync/RealtimeSignal.swift`):

- Toàn bộ client nằm trong một file. Ba phần:
  - **Message (hàm thuần):** `PhoenixMessage` gồm `topic`, `event`, `payload`, `ref`, `join_ref`, mã hoá và giải mã JSON. Dựng sẵn: `join` (topic `realtime:os-widget-events`, payload `{"config": {"postgres_changes": [{"event": "INSERT", "schema": "public", "table": "events"}]}}`), `heartbeat` (topic `phoenix`, event `heartbeat`, payload rỗng). Phân loại message nhận: `phx_reply` của join với `status: ok` là đã đăng ký; `phx_reply` của heartbeat; `postgres_changes` là tín hiệu; `phx_error`, `phx_close`, hoặc reply `status: error` là lỗi kênh; loại khác (ví dụ `system`, `presence_state`) bỏ qua.
  - **Trạng thái kết nối lại (hàm thuần):** `ReconnectPolicy` trả độ trễ lần thử thứ n: 1, 2, 4, 8 … tối đa 60 giây; đặt lại về 1 sau khi join thành công. Quyết định kết nối lại khi: socket đóng hoặc lỗi; join bị từ chối; heartbeat gửi đi mà không có reply trước heartbeat kế tiếp.
  - **Socket:** URL `wss://<host Supabase>/realtime/v1/websocket?apikey=<khoá publishable>&vsn=1.0.0`, mở bằng `URLSessionWebSocketTask` sau giao thức nhỏ `WebSocketConnection` (`send`, `receive`, `close`) để test thay bằng bản giả. Sau khi mở thì gửi `join`; heartbeat mỗi 25 giây; `ref` tăng dần.
- Một kết nối duy nhất (NFR-5). Nội dung payload `postgres_changes` bị bỏ qua; chỉ dùng như tín hiệu.
- Mỗi lần join thành công thì kích hoạt `sync()` (bắt kịp những gì đã lỡ khi đang rớt); mỗi `postgres_changes` thì kích hoạt `sync()`.
- Đóng kết nối khi máy sắp ngủ (`willSleepNotification`), mở lại khi thức.
- Giao thức `ChangeSignal` (một `AsyncStream<Void>`) để engine test được không cần mạng.

**Ghép vào app** (`App/SyncWiring.swift`, chữ ký từ Phase 1): dựng `APIClient`, `RealtimeSignal`, `SyncEngine` từ `AppEnvironment`, đăng ký các thông báo hệ thống. Không cần nối gì với popup vì hai bên gặp nhau qua kho.

**Log** (`os.Logger`, subsystem `local.oswidget.app`, category `sync`): `sync.start`, `sync.applied seq=<a>..<b> new=<n>`, `sync.reconcile items=<n>`, `sync.queue_sent id=<id> status=<code>`, `sync.auth_failed`, `realtime.state <state>`. Không ghi token, không ghi nội dung mục ngoài `id`.

## Files to Create / Modify

Đường dẫn tương đối với `apps/macos/`.

- Create: `OSWidgetKit/Sources/OSWidgetKit/Sync/APIClient.swift`, `OSWidgetKit/Sources/OSWidgetKit/Sync/HTTPTransport.swift`, `OSWidgetKit/Sources/OSWidgetKit/Sync/SyncEngine.swift`, `OSWidgetKit/Sources/OSWidgetKit/Sync/RealtimeSignal.swift`, `OSWidgetKit/Sources/OSWidgetKit/Sync/Triggers.swift` (wake, sleep, mạng, poll)
- Create: `OSWidgetKit/Tests/OSWidgetKitTests/SyncEngineTests.swift`, `OSWidgetKit/Tests/OSWidgetKitTests/APIClientTests.swift`
- Create: `OSWidgetKit/Tests/OSWidgetKitTests/RealtimeSignalTests.swift`
- Modify: `App/SyncWiring.swift`

## Tasks & Steps

- [ ] `HTTPTransport` và `APIClient`, test với transport giả: header đúng, đường dẫn và query đúng, giải mã fixture của Phase 2.
- [ ] `SyncEngine` với transport và tín hiệu giả; viết test trước cho từng tình huống trong bảng.
- [ ] `RealtimeSignal` tự viết, test trước bằng `WebSocketConnection` giả (bảng `RealtimeSignalTests` dưới); sau đó thử bằng tay với Supabase thật: publish một mục bằng `os-widget publish`, thấy log `realtime.state joined` và một vòng `sync.applied`.
- [ ] `Triggers` cho wake, sleep, mạng, poll.
- [ ] `SyncWiring`.

| Test (`SyncEngineTests`) | Kiểm |
|---|---|
| Đồng bộ đầu | Cursor `nil` gọi `GET /items`, không gọi `GET /events`, không có `announce` |
| Phân trang | Trang 100 sự kiện thì gọi tiếp với `seq` cuối; trang dưới 100 thì dừng |
| Lùi cursor | `since` bằng `cursor - 20`, không âm |
| Không chồng vòng | Ba tín hiệu tới trong khi một vòng đang chạy gây đúng một vòng nữa |
| Mất mạng rồi có mạng (§10.4) | Transport lỗi mạng, ba `item.created` tích lại trên server giả; khi transport hoạt động lại, một vòng đưa đủ ba mục vào kho, không trùng, `announce` được gọi một lần với ba mục |
| Hàng đợi | Thao tác gửi trước fetch; 404 bị bỏ; 503 giữ lại và thử ở vòng sau; 401 dừng gửi và ghi `sync.auth_failed` |
| Đối chiếu | `lastFullSyncAt` cũ hơn 6 giờ thì gọi `GET /items` sau fetch sự kiện; mục bị xoá trên server biến khỏi kho |
| Đã đọc từ máy khác (§10.3) | `item.read` cho mục đang có làm mục thành đã đọc, `unreadCount` giảm |

| Test (`RealtimeSignalTests`) | Kiểm |
|---|---|
| Mã hoá join | JSON có `topic` `realtime:os-widget-events`, `event` `phx_join`, cấu hình `postgres_changes` `INSERT` trên `public.events`, `ref` và `join_ref` |
| Mã hoá heartbeat | Topic `phoenix`, event `heartbeat`, payload rỗng, `ref` tăng |
| Giải mã | `phx_reply` ok của join là đã đăng ký; `postgres_changes` là tín hiệu; `phx_error`, `phx_close`, reply `status: error` là lỗi kênh; `system` và message lạ bị bỏ qua; JSON hỏng bị bỏ qua, không làm sập |
| Lùi dần | Độ trễ 1, 2, 4, 8, 16, 32, 60, 60; join thành công thì về 1 |
| Kết nối lại | Socket giả đóng thì mở lại sau độ trễ; heartbeat không có reply trước nhịp kế tiếp thì đóng và mở lại; join bị từ chối thì mở lại |
| Phát tín hiệu | Join thành công phát một tín hiệu; mỗi `postgres_changes` phát một tín hiệu; heartbeat reply không phát |

## Verification

- `cd apps/macos/OSWidgetKit && swift test` pass.
- `xcodebuild … build` của app thành công với phụ thuộc mới.
- Thử bằng tay trên một máy, app đã nhập cấu hình: `os-widget publish --source m2-test --title "thử sync" --summary "phase 3" --ttl 3600` (với `OS_WIDGET_SERVER` và `OS_WIDGET_PUBLISH_TOKEN`) làm xuất hiện `sync.applied` trong `log stream --predicate 'subsystem == "local.oswidget.app"'` trong vài giây; tắt Wi-Fi 1 phút rồi bật lại thì có một vòng sync ngay khi có mạng.
- `lsof -i -n -P | grep OSWidget` khi chạy ổn định chỉ có một kết nối WebSocket tới Supabase.

## Risk Assessment

- Realtime `postgres_changes` cần RLS cho phép `anon` đọc `events`; migration đã có chính sách này. Nếu không nhận được `INSERT`, kiểm publication bằng truy vấn trong migration (chỉ đọc) và dừng hỏi; không sửa schema trong M2.
- Giao thức Realtime của Supabase thay đổi (ví dụ phiên bản `vsn` mới hoặc khoá publishable cần `access_token` trong payload join): mọi chi tiết giao thức nằm trong `RealtimeSignal.swift`. Kiểm bằng tay với Supabase thật ở bước trên; nếu join bị từ chối, ghi nguyên văn reply và thử thêm `access_token` bằng khoá publishable trước khi dừng hỏi. Mất Realtime không làm mất dữ liệu: poll 5 phút vẫn bắt kịp, chỉ trượt NFR-1.
- Đồng hồ máy lệch không ảnh hưởng đồng bộ vì cursor là `seq` của server; chỉ ảnh hưởng hết hạn mục (so `expires_at` với giờ máy), chấp nhận.
- Poll 5 phút là khoảng 288 request mỗi ngày mỗi máy (576 khi Giai đoạn 5 thêm Mac mini) cộng request theo tín hiệu, xa dưới 100.000 (NFR-3).

## Rollback

Xoá `Sync/` và test của phase, trả `SyncWiring.swift` về khung rỗng của Phase 1. Kho và hàng đợi của Phase 2 không đổi.

## Ghi chú

- Quyết định của operator (2026-11-23, khoảng 21:05): "Cook ngay, chưa ký/cài (Đề xuất)". Phase này chỉ kiểm bằng `swift test` và build Debug không ký; app chưa chạy.
- Kiểm Realtime với Supabase thật hoãn tới Phase 6: lúc cook không có khoá publishable (lệnh `supabase projects api-keys` không trả về sau 60 giây, nhiều khả năng chờ đăng nhập), nên chưa có reply join, chưa biết có tín hiệu `INSERT` hay không. Test `liveJoinAndInsert` chạy khi có `OSWIDGET_LIVE_REALTIME=1`, `OSWIDGET_SUPABASE_URL`, `OSWIDGET_SUPABASE_KEY`; nếu join bị từ chối hoặc có message `system` báo lỗi `postgres_changes`, ghi nguyên văn và thử thêm `access_token` như mục rủi ro.
- Hoãn tới Phase 6 (cần app chạy), theo báo cáo cook: `os-widget publish` làm xuất hiện `realtime.state joined` và `sync.applied` trong vài giây; tắt Wi-Fi 1 phút rồi bật lại thì có một vòng sync ngay; `lsof` chỉ thấy một WebSocket tới Supabase; ngủ rồi thức thì socket đóng, mở lại và sync; App Sandbox cho phép `URLSessionWebSocketTask` và `NWPathMonitor` với `network.client` (chỉ xác nhận được trên bản ký).
- Đổi riêng token trong cài đặt nay kích hoạt một vòng sync ngay (`SyncSettings`, so cả token trong Keychain khi `UserDefaults` báo thay đổi); chỉ đổi URL Supabase hoặc khoá mới mở lại Realtime.
- Phase 3 sở hữu kích hoạt sau thao tác người dùng (`QueueWatcher`); Phase 4 và 5 chỉ gọi `markRead`/`delete`.
- Báo cáo: [cook](../reports/cook-261123-m2-p03.md), [review](../reports/review-261123-m2-p03.md).
