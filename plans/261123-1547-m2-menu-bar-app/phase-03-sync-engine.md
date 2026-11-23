---
phase: 3
title: "Sync engine"
status: pending
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
- Thư viện Realtime theo câu trả lời câu hỏi 2. Đề xuất: `supabase-swift`, chỉ sản phẩm `Realtime`, ghim phiên bản chính xác trong `Package.swift`.

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

- Một kết nối duy nhất (NFR-5), kênh `postgres_changes` sự kiện `INSERT` trên `public.events`, dùng URL Supabase và khoá publishable từ `AppConfig`. Nội dung payload bị bỏ qua; chỉ dùng như tín hiệu.
- Kết nối lại khi rớt, lùi dần tới tối đa 60 giây; mỗi lần vào trạng thái đã đăng ký thì kích hoạt `sync()`.
- Đóng kết nối khi máy sắp ngủ (`willSleepNotification`), mở lại khi thức.
- Giao thức `ChangeSignal` (một `AsyncStream<Void>`) để engine test được không cần mạng.

**Ghép vào app** (`App/SyncWiring.swift`, chữ ký từ Phase 1): dựng `APIClient`, `RealtimeSignal`, `SyncEngine` từ `AppEnvironment`, đăng ký các thông báo hệ thống. Không cần nối gì với popup vì hai bên gặp nhau qua kho.

**Log** (`os.Logger`, subsystem `local.oswidget.app`, category `sync`): `sync.start`, `sync.applied seq=<a>..<b> new=<n>`, `sync.reconcile items=<n>`, `sync.queue_sent id=<id> status=<code>`, `sync.auth_failed`, `realtime.state <state>`. Không ghi token, không ghi nội dung mục ngoài `id`.

## Files to Create / Modify

Đường dẫn tương đối với `apps/macos/`.

- Create: `OSWidgetKit/Sources/OSWidgetKit/Sync/APIClient.swift`, `OSWidgetKit/Sources/OSWidgetKit/Sync/HTTPTransport.swift`, `OSWidgetKit/Sources/OSWidgetKit/Sync/SyncEngine.swift`, `OSWidgetKit/Sources/OSWidgetKit/Sync/RealtimeSignal.swift`, `OSWidgetKit/Sources/OSWidgetKit/Sync/Triggers.swift` (wake, sleep, mạng, poll)
- Create: `OSWidgetKit/Tests/OSWidgetKitTests/SyncEngineTests.swift`, `OSWidgetKit/Tests/OSWidgetKitTests/APIClientTests.swift`
- Modify: `OSWidgetKit/Package.swift` (thêm phụ thuộc Realtime, ghim phiên bản), `App/SyncWiring.swift`

## Tasks & Steps

- [ ] `HTTPTransport` và `APIClient`, test với transport giả: header đúng, đường dẫn và query đúng, giải mã fixture của Phase 2.
- [ ] `SyncEngine` với transport và tín hiệu giả; viết test trước cho từng tình huống trong bảng.
- [ ] `RealtimeSignal` với thư viện đã chọn; thử bằng tay với Supabase thật: publish một mục bằng `os-widget publish`, thấy log `realtime.state` và một vòng `sync.applied`.
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

## Verification

- `cd apps/macos/OSWidgetKit && swift test` pass.
- `xcodebuild … build` của app thành công với phụ thuộc mới.
- Thử bằng tay trên một máy, app đã nhập cấu hình: `os-widget publish --source m2-test --title "thử sync" --summary "phase 3" --ttl 3600` (với `OS_WIDGET_SERVER` và `OS_WIDGET_PUBLISH_TOKEN`) làm xuất hiện `sync.applied` trong `log stream --predicate 'subsystem == "local.oswidget.app"'` trong vài giây; tắt Wi-Fi 1 phút rồi bật lại thì có một vòng sync ngay khi có mạng.
- `lsof -i -n -P | grep OSWidget` khi chạy ổn định chỉ có một kết nối WebSocket tới Supabase.

## Risk Assessment

- Realtime `postgres_changes` cần RLS cho phép `anon` đọc `events`; migration đã có chính sách này. Nếu không nhận được `INSERT`, kiểm publication bằng truy vấn trong migration (chỉ đọc) và dừng hỏi; không sửa schema trong M2.
- Thư viện Realtime đổi API giữa các bản: ghim phiên bản chính xác; mọi chỗ gọi thư viện nằm trong `RealtimeSignal.swift`, nên đổi sang WebSocket tự viết chỉ chạm một file.
- Đồng hồ máy lệch không ảnh hưởng đồng bộ vì cursor là `seq` của server; chỉ ảnh hưởng hết hạn mục (so `expires_at` với giờ máy), chấp nhận.
- Poll 5 phút trên hai máy là khoảng 576 request mỗi ngày cộng request theo tín hiệu, xa dưới 100.000 (NFR-3).

## Rollback

Bỏ phụ thuộc Realtime khỏi `Package.swift`, xoá `Sync/` và test của phase, trả `SyncWiring.swift` về khung rỗng của Phase 1. Kho và hàng đợi của Phase 2 không đổi.
