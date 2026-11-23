---
title: "M2: App thanh menu"
description: "Hoàn thành Giai đoạn 2 của roadmap: app agent trên thanh menu macOS với sync engine (Realtime, cursor, poll dự phòng), kho cục bộ và hàng đợi thao tác, popup không kích hoạt, danh sách và view thẻ; kiểm bằng tiêu chí 1, 3, 4, 6 của PRD §10 và quy tắc không cướp focus."
status: pending
priority: P1
effort: 28h
branch: main
tags: [feature, macos, swift, sync, ui]
blockedBy: []
blocks: []
created: 2026-11-23
---

# M2: App thanh menu

## Overview

Hoàn thành Giai đoạn 2 của [roadmap](../../docs/roadmap.md#giai-đoạn-2-app-thanh-menu) trên server đã nghiệm thu ở [plan M1](../261123-0159-m1-server/plan.md). Kết thúc plan này, một app agent trên thanh menu chạy khi đăng nhập trên MacBook và Mac mini, nhận mục mới qua tín hiệu Realtime và `GET /events`, hiện popup không kích hoạt trong vòng 5 giây, giữ danh sách mục với dấu báo chưa đọc, và đồng bộ đã đọc và xoá giữa hai máy kể cả khi mất mạng.

Thiết kế theo [architecture.md](../../docs/architecture.md) §4.1 (API), §5 (giao thức đồng bộ), §6 (client macOS), §7 (bảo mật). Yêu cầu theo [prd.md](../../docs/prd.md) FR-5 đến FR-10c, FR-14, FR-16 đến FR-23, NFR-1, NFR-5, NFR-6. Mẫu project lấy từ app thử nghiệm `spikes/widget-probe/` (XcodeGen, Personal Team, App Group, panel không kích hoạt của thử nghiệm C).

## Preconditions

Mã chỉ bắt đầu khi đủ các điều kiện sau. Phase nào chưa đủ điều kiện thì không mở.

1. **Kết quả kiểm ngày 8 của thử nghiệm A (2026-11-30) đã ghi vào** `plans/261122-0754-m0-kiem-chung-worker-rust/reports/a-c-results.md` và hàng A của `docs/roadmap.md`. Quyết định của operator (2026-11-23): viết plan song song với đo B, mã chỉ bắt đầu sau kết quả A ngày 8. Kết quả A chọn nhánh ở mục "Nhánh theo kết quả thử nghiệm" bên dưới trước khi mở Phase 1.
2. Thử nghiệm C đã đạt ngày 1 (panel `.nonactivatingPanel` mở bằng `orderFrontRegardless()` không lấy focus khỏi TextEdit). Phase 5 dựng popup trên đúng cấu hình đó.
3. Thử nghiệm B không chặn M2 (Giai đoạn 2 không có widget), nhưng kết quả B nên có trước khi đóng M2 để Phase 6 ghi điều Giai đoạn 3 phải đổi.
4. Worker `https://os-widget.longdaobk17.workers.dev` vẫn qua `scripts/acceptance-server.sh` (8/8 ngày 2026-11-23). Operator có token client, URL Supabase và khoá publishable (`sb_publishable_...`) để nhập vào app.
5. Xcode 27.2 và xcodegen 2.48.0 như khi làm app thử nghiệm (a-c-results.md, mục Môi trường).

## Nhánh theo kết quả thử nghiệm

| Kết quả | Thay đổi trong M2 | Phase bị ảnh hưởng |
|---|---|---|
| A đạt (app còn chạy ngày 8, widget vẫn đọc App Group) | Theo plan: ký Personal Team `22LZWPB3XL`, kho cục bộ nằm trong group container `22LZWPB3XL.os-widget` để widget Giai đoạn 3 đọc được. | Không |
| A thất bại vì app không mở được sau khoảng 7 ngày (chữ ký hoặc profile hết hạn) | App Group vẫn giữ (ngày 1 đã chạy). Thêm `scripts/build-install-macos.sh` để build lại và cài lại bằng một lệnh, Phase 6 ghi chu kỳ build lại vào architecture §9; hoặc chuyển sang tài khoản trả phí: đổi `DEVELOPMENT_TEAM` ở một chỗ duy nhất trong `project.yml`, App Group đổi theo Team ID mới, kho cục bộ cũ bỏ đi và app đồng bộ lại từ đầu bằng `GET /items` (server là nguồn chân lý). Operator chọn một trong hai (câu hỏi 4). | 1, 6 |
| A thất bại vì App Group không còn đọc được sau 7 ngày, app vẫn chạy | Bỏ entitlement `application-groups`; `StoreLocation` trả thư mục Application Support trong container của app thay cho group container. Giai đoạn 3 cho widget lấy ảnh chụp từ app qua HTTP trên localhost (architecture §6). Mọi thứ khác trong M2 giữ nguyên. | 1, 2 |
| B tốt | M2 không đổi. | Không |
| B kém (widget trễ nhiều hoặc ít lượt làm mới mỗi ngày) | M2 không đổi vì không có widget. Giai đoạn 3 phải thay widget bằng cửa sổ SwiftUI ở tầng desktop: cửa sổ đó dùng lại view thẻ và kho trong `OSWidgetKit`, đọc kho trực tiếp trong tiến trình app nên không cần App Group. M2 giữ đường cho cả hai: view thẻ và kho nằm trong package dùng chung, không mã nào trong M2 gọi `WidgetCenter`. | Không (Phase 2 và 4 giữ ràng buộc này) |

Phase có thiết kế phụ thuộc thử nghiệm: Phase 1 (A: ký và entitlement), Phase 2 (A: vị trí kho), Phase 5 (C: cấu hình panel, đã đạt), Phase 6 (A: quy trình cài trên hai máy; B: ghi chú cho Giai đoạn 3).

## Done means

Điều kiện hoàn thành của roadmap Giai đoạn 2, kiểm trên MacBook và Mac mini bằng `scripts/acceptance-menu-bar.sh` (phần tự động) và checklist trong Phase 6 (phần cần mắt người):

1. **PRD §10.1.** Một lệnh `os-widget publish` từ máy khác làm popup hiện trên MacBook trong 5 giây. Đo bằng dòng log `popup.shown` của app, ghi độ trễ từ `created_at` của mục tới lúc panel hiện.
2. **PRD §10.3.** Đánh dấu đã đọc trên MacBook làm mục đó thành đã đọc trên Mac mini.
3. **PRD §10.4.** Tắt mạng MacBook, publish ba mục, bật mạng lại: cả ba mục hiện đủ trong danh sách, không trùng.
4. **PRD §10.6.** Một mục có `kind` lạ vẫn hiện `title` và `summary`. Server từ chối `kind` ngoài ba loại, nên kiểm đầu-cuối bằng mục `vocab` (M2 chưa có view `vocab`, Giai đoạn 4 mới có) cùng unit test với một chuỗi `kind` không tồn tại.
5. **Quy tắc focus.** Popup tự mở khi đang gõ trong TextEdit không lấy focus: ký tự gõ tiếp vẫn vào TextEdit, `lsappinfo front` trước và sau khi popup hiện cùng là TextEdit.

Thêm: `swift test` của package `OSWidgetKit` pass; app build được bằng `xcodebuild`; architecture §6 và roadmap Giai đoạn 2 ghi đúng những gì đã làm.

### Ánh xạ yêu cầu sang phase

| Yêu cầu | Phase |
|---|---|
| Roadmap: app agent với icon thanh menu, chạy khi đăng nhập | 1 (agent, `LSUIElement`), 4 (icon, `SMAppService`) |
| Roadmap: sync engine gồm tín hiệu Realtime, fetch theo cursor, poll dự phòng, bắt kịp sau khi ngủ hoặc mất mạng | 3 |
| Roadmap: kho cục bộ và hàng đợi thao tác | 2 (kho, hàng đợi, quy tắc áp dụng), 3 (gửi hàng đợi) |
| Roadmap: popup tự mở, tự đóng sau 30 giây; gộp nhiều mục; bật tắt theo loại và chế độ yên lặng | 5 (cài đặt theo loại và chế độ yên lặng lưu ở Phase 2, nút bật tắt ở menu Phase 4) |
| Roadmap: danh sách mục, dấu báo chưa đọc, đã đọc và xoá | 4 |
| Roadmap: view `notification`, `generic` và dự phòng cho loại lạ | 2 (giải mã chịu lỗi), 4 (view) |
| PRD §10.1 (popup trong 5 giây) | 3, 5, 6 |
| PRD §10.3 (đã đọc đồng bộ sang máy kia) | 2, 3, 4, 6 |
| PRD §10.4 (mất mạng, ba mục, không trùng) | 2, 3, 6 |
| PRD §10.6 (`kind` lạ hiện `title` và `summary`) | 2, 4, 6 |
| Popup không cướp focus | 5, 6 |

## Phases

| # | Phase | Status | Phụ thuộc thử nghiệm |
|---|-------|--------|---|
| 1 | [Xcode project, package dùng chung và cấu hình](./phase-01-xcode-project-va-cau-hinh.md) | Pending | A |
| 2 | [Mô hình, kho cục bộ và hàng đợi thao tác](./phase-02-kho-cuc-bo-va-hang-doi.md) | Pending | A (vị trí kho) |
| 3 | [Sync engine](./phase-03-sync-engine.md) | Pending | Không |
| 4 | [Thanh menu, danh sách và view thẻ](./phase-04-thanh-menu-danh-sach-va-the.md) | Pending | Không |
| 5 | [Popup panel](./phase-05-popup-panel.md) | Pending | C (đã đạt) |
| 6 | [Cài hai máy, nghiệm thu và cập nhật tài liệu](./phase-06-nghiem-thu-va-tai-lieu.md) | Pending | A, B (chỉ ghi chú) |

Thứ tự: Phase 1 trước tiên. Phase 2 cần 1. Sau Phase 2, ba phase 3, 4, 5 làm song song được vì sở hữu file tách rời (bảng dưới). Phase 5 cần cả mỏ neo icon do Phase 4 cung cấp khi ghép nối, nhưng hợp đồng giữa hai bên đã cố định ở Phase 1. Phase 6 cần tất cả.

```text
1 ──> 2 ──┬──> 3 ──┐
          ├──> 4 ──┼──> 6
          └──> 5 ──┘
```

### Sở hữu file

Đường dẫn tương đối với `apps/macos/`. Mọi file dưới đây do plan này tạo.

| Phase | Sở hữu (tạo hoặc sửa) |
|---|---|
| 1 | `project.yml`, `App/Info.plist`, `App/App.entitlements`, `App/AppDelegate.swift`, `App/AppEnvironment.swift`, `App/Settings/SettingsWindow.swift`, các file khung rỗng `App/MenuBar/MenuBarController.swift`, `App/Popup/PopupController.swift`, `App/SyncWiring.swift`, `OSWidgetKit/Sources/OSWidgetKit/Store/ItemStore.swift` (chỉ chữ ký, giao cho phase sau), `OSWidgetKit/Package.swift`, `OSWidgetKit/Sources/OSWidgetKit/Config/*`, `README.md` của `apps/macos/`; ở gốc repo: `.gitignore` (thêm `apps/macos/*.xcodeproj/`) |
| 2 | `OSWidgetKit/Sources/OSWidgetKit/Model/*`, `OSWidgetKit/Sources/OSWidgetKit/Store/*`, `OSWidgetKit/Tests/OSWidgetKitTests/{Model,Store,Queue}*`, `OSWidgetKit/Tests/OSWidgetKitTests/Fixtures/*` |
| 3 | `OSWidgetKit/Sources/OSWidgetKit/Sync/*`, `OSWidgetKit/Tests/OSWidgetKitTests/Sync*`, `App/SyncWiring.swift`, `OSWidgetKit/Package.swift` (chỉ thêm phụ thuộc Realtime) |
| 4 | `App/MenuBar/*`, `App/LaunchAtLogin.swift`, `OSWidgetKit/Sources/OSWidgetKit/Cards/*`, `OSWidgetKit/Tests/OSWidgetKitTests/Cards*` |
| 5 | `App/Popup/*`, `OSWidgetKit/Sources/OSWidgetKit/Popup/PopupPolicy.swift`, `OSWidgetKit/Tests/OSWidgetKitTests/PopupPolicy*` |
| 6 | `scripts/acceptance-menu-bar.sh`, `scripts/build-install-macos.sh` (chỉ khi nhánh A thất bại cần), `plans/261123-1547-m2-menu-bar-app/reports/acceptance.md`, `docs/architecture.md`, `docs/roadmap.md` |

`App/AppDelegate.swift` và `App/AppEnvironment.swift` do Phase 1 sở hữu; `AppDelegate` chỉ gọi ba điểm nối có chữ ký cố định (`SyncWiring.start`, `MenuBarController`, `PopupController`), nên Phase 3, 4, 5 không phải sửa cùng một file. Nếu một phase cần đổi chữ ký điểm nối, phase đó dừng và báo thay vì sửa `AppDelegate.swift`.

## Scope Challenge

- Có sẵn: server năm endpoint và hai token đã deploy; bảng `events` trong publication Realtime với khoá anon chỉ đọc `events`; app thử nghiệm làm mẫu cho XcodeGen, App Group và panel không kích hoạt; CLI `os-widget publish` và script nghiệm thu server để publish mục thử.
- Phạm vi: đúng sáu gạch đầu dòng và điều kiện hoàn thành của roadmap Giai đoạn 2. Giữ nguyên phạm vi (HOLD).
- Độ phức tạp: 6 phase theo lớp (project, kho, đồng bộ, UI danh sách, popup, nghiệm thu); khoảng 30 file Swift mới, một package Swift cục bộ, một phụ thuộc ngoài (client Realtime, câu hỏi 2).

## Out of scope

- Widget extension, bố cục rút gọn, nút trong widget, yêu cầu làm mới WidgetKit (Giai đoạn 3).
- View `vocab` đầy đủ và phát âm (Giai đoạn 4). Ở M2 mục `vocab` hiện bằng view dự phòng.
- Báo lỗi rõ ràng trên UI khi server không phản hồi hoặc token sai, hướng dẫn cài đặt, tích hợp bên gửi thật, theo dõi hạn mức (Giai đoạn 5). M2 chỉ ghi log các lỗi này.
- Mọi thay đổi server, schema hoặc API; Cloudflare và Supabase không bị đụng tới.
- Nút "bỏ đọc" trên UI (PRD chỉ yêu cầu đã đọc và xoá); app vẫn áp dụng sự kiện `item.unread` tới từ nơi khác.

## Constraints

- Swift 6, SwiftUI, AppKit cho `NSStatusItem` và `NSPanel`; deployment target macOS 26 như app thử nghiệm.
- Project sinh bằng XcodeGen từ `apps/macos/project.yml`; `.xcodeproj` không commit (như `spikes/widget-probe/`).
- Team ID chỉ đặt ở một chỗ (`DEVELOPMENT_TEAM` trong `project.yml`); App Group suy ra từ nó (`$(TeamIdentifierPrefix)os-widget`), như app thử nghiệm.
- App Sandbox bật, cấp thêm `com.apple.security.network.client`.
- Token client chỉ nằm trong Keychain; URL Worker, URL Supabase và khoá publishable lưu trong `UserDefaults` của app. Không commit token hay khoá nào.
- Nội dung từ bên gửi là dữ liệu (architecture §7): markdown không render HTML thô, liên kết chỉ mở khi người dùng bấm, ảnh chỉ tải qua `https://` và phải có host.
- Không mã nào trong M2 gọi `WidgetCenter`; không chạm app WidgetProbe đã cài và các khoá `lastWrite`, `reloadLog` của nó trong group container.
- Không làm hỏng `cargo test --workspace` và `scripts/acceptance-server.sh`.

## Stop and ask only if

- Kết quả A ngày 8 rơi vào nhánh thất bại và operator chưa chọn giữa build lại định kỳ và tài khoản trả phí.
- Panel ở cấu hình cuối cùng lấy focus trong kiểm thủ công, dù đã giữ đúng cờ của thử nghiệm C.
- Realtime với khoá publishable không nhận được `INSERT` trên `events` (chính sách RLS hoặc publication không như architecture §4.3 mô tả).
- Một tiêu chí chỉ đạt được nếu đổi API hoặc schema của architecture §4.
- Mac mini không sẵn sàng để kiểm tiêu chí §10.3 (câu hỏi 1).

## Câu hỏi cần operator trả lời

Gửi qua session giám sát `m0-supervisor`; plan chưa coi câu nào là đã chốt.

| # | Câu hỏi | Đề xuất | Phase bị ảnh hưởng |
|---|---|---|---|
| 1 | Cài app lên cả MacBook và Mac mini ngay trong M2 để kiểm tiêu chí §10.3 và §10.4, thay vì đợi Giai đoạn 5? | Có. §10.3 cần hai máy thật; dùng script giả làm máy thứ hai không chứng minh được popup và danh sách ở máy kia. | 6 |
| 2 | Client Realtime: dùng thư viện `supabase-swift` (chỉ sản phẩm `Realtime`, ghim phiên bản) hay tự viết WebSocket theo giao thức Phoenix của Supabase? | Dùng `supabase-swift` sản phẩm `Realtime`. Tự viết phải tự lo heartbeat, join, kết nối lại; thư viện chính thức theo kịp thay đổi giao thức. Đổi lại là một phụ thuộc ngoài. | 3 |
| 3 | Chế độ yên lặng kéo dài bao lâu? | Menu có ba lựa chọn: 1 giờ, đến 8:00 sáng hôm sau, đến khi tắt. Trạng thái lưu bền qua lần khởi động lại. | 2, 4, 5 |
| 4 | Nếu A ngày 8 cho thấy app không mở được sau khoảng 7 ngày: build lại định kỳ bằng một script hay chuyển sang tài khoản Apple trả phí? | Build lại định kỳ bằng `scripts/build-install-macos.sh` trong M2; quyết định tài khoản trả phí khi làm bản iPhone (roadmap "Sau này" cũng cần tài khoản trả phí). | 1, 6 |
| 5 | Popup tự mở bật mặc định cho mọi loại, kể cả `vocab` (Giai đoạn 4 gửi mỗi giờ)? | Bật cho mọi loại; người dùng tắt từng loại ở menu (FR-10c). Mục `vocab` có thể gửi với `priority: low` nếu cần yên hơn. | 2, 5 |
| 6 | Gỡ app WidgetProbe trước khi cài app M2 không? Hai app dùng chung group container `22LZWPB3XL.os-widget`. | Giữ WidgetProbe tới khi B đo xong và operator tự gỡ. App M2 dùng tên file riêng (`store.json`) nên không đụng dữ liệu của WidgetProbe. | 1, 6 |

## Validation Log

Chưa có phiên validate. Câu trả lời của operator cho bảng trên sẽ được ghi ở đây kèm phase bị ảnh hưởng.

<!-- slug: m2-menu-bar-app -->
