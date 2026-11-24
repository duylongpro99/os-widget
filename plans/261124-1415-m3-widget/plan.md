---
title: "M3: Widget"
description: "Hoàn thành Giai đoạn 3 của roadmap: widget extension WidgetKit cỡ vừa và cỡ lớn đọc kho dùng chung, mục mới nhất trên cùng, bố cục rút gọn theo loại, nút đã đọc và xoá qua AppIntent ghi vào hộp thư thao tác, app chỉ reload khi nội dung widget đổi (gộp ≥ 5 s, ghi log để đếm); kiểm bằng PRD §10.2, đã đọc từ widget lên server, và số reload trong một ngày dùng thật."
status: pending
priority: P1
effort: 22h
branch: main
tags: [feature, macos, swift, widget, widgetkit]
blockedBy: []
blocks: []
created: 2026-11-24
---

# M3: Widget

## Overview

Hoàn thành Giai đoạn 3 của [roadmap](../../docs/roadmap.md#giai-đoạn-3-widget) trên app thanh menu đã nghiệm thu ở [plan M2](../261123-1547-m2-menu-bar-app/plan.md). Kết thúc plan này, app `OSWidget` trên MacBook nhúng một widget extension WidgetKit có cỡ vừa và cỡ lớn. Widget đọc kho `store.json` trong group container, hiện các mục mới nhất với mục mới nhất trên cùng, mỗi loại một bố cục rút gọn (loại chưa có bố cục hiện `title` và `summary`), và có nút đã đọc và xoá ngay trên từng mục. App yêu cầu WidgetKit làm mới chỉ khi nội dung widget đổi, không quá một lần mỗi 5 giây, và ghi log mỗi lần yêu cầu để đếm được số lần làm mới trong một ngày dùng thật.

Thiết kế theo [architecture.md](../../docs/architecture.md) §6 (đặc biệt "App thanh menu đã làm" và "Chia sẻ dữ liệu giữa app và widget"), §9 (rủi ro). Yêu cầu theo [prd.md](../../docs/prd.md) FR-11 đến FR-13, FR-18 đến FR-20, NFR-2, §10 tiêu chí 2. Số đo theo [kết quả thử nghiệm B](../261122-0754-m0-kiem-chung-worker-rust/reports/b-results.md) (reload được cho phép vẽ lại sau p50 66 ms; gọi dồn bị throttle, chronod chạy lại khoảng mỗi 5 s; ngân sách reload khi app chạy nền chưa đo). Mẫu widget extension, App Group và reload lấy từ `spikes/widget-probe/` (chỉ đọc).

## Preconditions

1. M2 đã đóng (main `2f7bf2e`): `cargo test --workspace` 92 pass, `swift test` trong `apps/macos/OSWidgetKit` 127 pass, app `OSWidget` đang chạy trên MacBook với kho trong group container `22LZWPB3XL.os-widget`.
2. Kết quả kiểm ngày 8 của thử nghiệm A (2026-11-30) **không chặn** việc viết mã. Quyết định của operator cho M2 (2026-11-23 22:35): "chúng ta không thể chời tới ngày 30/11 để tiếp tục, để note lại đó đến ngày sẽ kiểm tra lại, cứ move on". M3 theo nhánh "A đạt"; bảng dưới ghi phase nào đổi nếu A trượt.
3. Worker `https://os-widget.longdaobk17.workers.dev` vẫn qua `scripts/acceptance-server.sh`. Operator có token publish và token client cho script nghiệm thu.
4. Xcode 27.2 và xcodegen 2.48.0 như M2.

## Nhánh theo kết quả thử nghiệm

| Kết quả | Thay đổi trong M3 | Phase bị ảnh hưởng |
|---|---|---|
| A đạt (app và widget probe còn chạy ngày 8, widget vẫn đọc App Group) | Theo plan. | Không |
| A trượt vì app không mở được sau khoảng 7 ngày (chữ ký hết hạn) | App Group giữ nguyên. Theo câu trả lời 4 của M2: thêm `scripts/build-install-macos.sh` build lại và cài lại app (kèm widget nhúng bên trong) bằng một lệnh, mỗi tuần. Phase 6 dùng script đó để cài và ghi vào checklist rằng sau mỗi lần cài lại phải kiểm widget còn trên desktop (thêm lại nếu hệ thống gỡ). Không đổi mã widget. | 1, 6 |
| A trượt vì App Group không còn đọc được sau 7 ngày, app vẫn chạy | Kho app chuyển về Application Support (`StoreLocation`, theo plan M2). Widget không đọc được file của app nữa nên đổi đường vận chuyển, giữ nguyên dữ liệu: app mở một listener HTTP chỉ trên `127.0.0.1` (entitlement `network.server`) trả `WidgetSnapshot` dạng JSON và nhận `WidgetAction` dạng JSON; widget thêm `network.client`, provider gọi `GET /snapshot` thay cho `StoreReader`, intent gọi `POST /actions` thay cho `ActionInbox.submit`. App không chạy thì widget hiện trạng thái "Mở OS Widget" và nút báo lỗi. Hai kiểu `WidgetSnapshot` và `WidgetAction` là hợp đồng không đổi giữa hai nhánh (Phase 2 giữ chúng không biết gì về file); chỉ ba chỗ gọi đổi: provider (Phase 4), intent (Phase 5), `InboxWatcher` (Phase 5). Nhánh này là một plan bổ sung nhỏ mở sau 2026-11-30, không làm trước. | 1, 2, 4, 5, 6 |
| B (đã có): reload được cho phép vẽ lại trong khoảng 0,1 s | Giữ WidgetKit. | Không |
| Đếm một ngày ở Phase 6 cho thấy chronod từ chối hoặc trễ reload vì hết ngân sách nền | Không đổi mã trong M3. Phase 6 ghi số đo vào báo cáo và architecture §9, đề xuất một trong hai: nới khoảng gộp lên 30 s (B không thấy throttle nào khi cách nhau ≥ 30 s), hoặc theo architecture §9 thay widget bằng cửa sổ SwiftUI tầng desktop dùng lại `CompactCardView` và `WidgetSnapshot`. Operator chọn. | 6 (chỉ ghi và đề xuất) |

Phase có thiết kế phụ thuộc thử nghiệm A: Phase 1 (ký, entitlement, nhúng extension), Phase 2 (vị trí hộp thư trong group container), Phase 4 (nguồn dữ liệu của provider), Phase 5 (đường gửi thao tác), Phase 6 (cách cài). Phase 3 không phụ thuộc A: chính sách reload giống nhau ở mọi nhánh.

## Thiết kế ghi giữa hai tiến trình

**Chọn: widget ghi thao tác vào hộp thư, app là tiến trình duy nhất ghi `store.json`.**

- Intent trong widget (chạy trong tiến trình extension) ghi mỗi thao tác thành một file riêng `inbox/<uuid>.json` trong group container: ghi ra file tạm có tiền tố `.tmp-` trong cùng thư mục rồi đổi tên. Đổi tên trong cùng thư mục là nguyên tử, tên file không trùng nhau, nên nhiều lần bấm liên tiếp hay app đang đọc cùng lúc đều không cần khoá.
- Provider của widget đọc `store.json` (chỉ đọc) rồi phủ các thao tác còn trong hộp thư lên trên: mục chờ xoá bị ẩn, mục chờ đọc hiện là đã đọc. Sau khi intent chạy xong WidgetKit tự chạy lại timeline (không do app yêu cầu), nên người dùng thấy kết quả ngay cả khi app đang tắt.
- App theo dõi thư mục `inbox/` (DispatchSource trên thư mục, cộng một lần quét khi khởi động và quét dự phòng mỗi 60 s), áp từng thao tác bằng chính `ItemStore.markRead` và `ItemStore.delete` (nên đi qua đúng quy tắc gộp hàng đợi và "xoá thắng đã đọc" của M2), ghi kho, rồi mới xoá file. Hàng đợi M2 gửi lên server như mọi thao tác khác (`QueueWatcher` kích hoạt vòng sync).
- Mất mạng (FR-20): thao tác nằm trong hàng đợi của kho như M2. App tắt: thao tác nằm trong hộp thư tới lần app chạy tiếp.

Lý do không chọn hai cách còn lại:

- **Hai tiến trình cùng ghi `store.json` với `NSFileCoordinator` hoặc khoá file.** `ItemStore` là đối tượng `@Observable` giữ toàn bộ trạng thái trong bộ nhớ và ghi đè cả file sau mỗi thay đổi; widget ghi vào file thì app phải biết để nạp lại và trộn, nếu không lần ghi kế tiếp của app xoá mất thao tác của widget. Phải thêm nạp lại có điều phối vào mọi đường ghi của kho M2, rủi ro hơn nhiều so với một thư mục chỉ thêm file.
- **AppIntent chạy trong tiến trình app.** Trên macOS, intent của nút widget chạy trong extension; cách đẩy sang app (`openAppWhenRun`, intent dạng foreground) mở hoặc kích hoạt app, trái với app agent không cướp focus, và chưa được kiểm chứng với app `LSUIElement`. Khi app tắt thì nút không làm gì.

Test chứng minh (Phase 2): nhiều luồng ghi thao tác cùng lúc trong khi một vòng lặp liên tục rút hộp thư; mọi thao tác được áp đúng một lần về kết quả, không còn file sót, không lỗi giải mã; rút lại sau khi "chết giữa chừng" (đã áp, chưa xoá file) không đổi kết quả; ghi hộp thư không đụng tới `store.json`. Kiểm hai tiến trình thật ở Phase 6 (bấm nút trên widget khi app chạy và khi app tắt).

## Chính sách reload

- App dựng `WidgetSnapshot` (các mục widget sẽ hiện: tối đa 6 mục hiển thị mới nhất sau khi phủ hộp thư, số mục chưa đọc, thời điểm hết hạn gần nhất) mỗi khi kho đổi, và chỉ yêu cầu `WidgetCenter.shared.reloadTimelines(ofKind:)` khi snapshot khác snapshot đã gửi lần trước. Vòng sync không đổi gì (poll 5 phút không có sự kiện), thao tác chỉ đổi hàng đợi, hay mục nằm ngoài 6 mục đầu đổi trạng thái thì không reload.
- Thời gian tương đối ("5 phút trước") do widget tự vẽ bằng `Text(_:style: .relative)`; mục hết hạn do timeline của widget tự bỏ (`policy: .after(nextExpiry)`). Hai việc này không cần app reload.
- Gộp: không quá một yêu cầu mỗi 5 giây. Thay đổi tới trong 5 giây sau lần trước thì hẹn đúng một lần reload ở mốc 5 giây, lần đó dùng snapshot mới nhất (B: chronod cũng chạy lại khoảng mỗi 5 s khi bị throttle).
- Đếm: mỗi yêu cầu ghi một dòng `widget.reload n_today=<n> reason=<changed|trailing> gap_ms=<ms>` ở mức `notice` (mức được lưu lại trong unified log, khác mức `info` của M2), category `widget`. Extension ghi `widget.timeline family=<medium|large> items=<n> unread=<n> top=<id>` mỗi lần timeline chạy. `scripts/widget-reload-count.sh` đếm hai loại dòng trong một khoảng thời gian (mặc định 24 giờ) và ghép mỗi yêu cầu với lần timeline chạy kế tiếp để biết yêu cầu nào bị trễ hoặc không được phục vụ.

## Done means

Điều kiện hoàn thành của roadmap Giai đoạn 3, kiểm trên MacBook bằng `scripts/acceptance-widget.sh` (phần tự động) và checklist ở Phase 6 (phần cần mắt người):

1. **PRD §10.2.** Một mục publish bằng CLI xuất hiện ở đầu widget (cả cỡ vừa và cỡ lớn) và ở đầu danh sách. Script đo từ dòng `sync.applied … new=<n ≥ 1>` đầu tiên sau lúc publish (dòng này không có id, nên mỗi lần đo chỉ publish một mục) tới dòng `widget.timeline top=<id>`: dưới 5 s (NFR-2); operator xác nhận bằng mắt mục nằm trên cùng ở widget và danh sách.
2. **Đã đọc trong widget đồng bộ sang máy kia, kiểm trên một máy.** Bấm nút đã đọc trên widget thì `GET /items` có `read_at` và `GET /events` có `item.read` cho mục đó (máy thứ hai giả bằng API với token client, như tiêu chí 3b của M2). Xoá tương tự (`item.deleted`). Thêm một lần với mạng tắt rồi bật lại (FR-20). Kiểm bằng Mac mini thật chuyển sang Giai đoạn 5, như M2.
3. **Số lần làm mới trong một ngày dùng thật nằm dưới mức đo được ở thử nghiệm B.** Chạy `scripts/widget-reload-count.sh` trên 24 giờ dùng thật với widget trên desktop. Ngưỡng đề xuất (câu hỏi 1): app yêu cầu không quá 40 lần trong 24 giờ, không hai yêu cầu nào cách nhau dưới 5 s, và ít nhất 95% yêu cầu có timeline chạy trong 5 s.
4. **Reload chỉ khi nội dung đổi.** Unit test của chính sách; trong log ngày dùng thật, mọi vòng sync không có mục mới hay đổi trạng thái thì không kèm `widget.reload`.

Thêm: `swift test` của `OSWidgetKit` pass (127 test cũ cộng test mới); `cargo test --workspace` vẫn pass; app và widget build được bằng `xcodebuild`; architecture §6 và roadmap Giai đoạn 3 ghi đúng những gì đã làm.

### Ánh xạ yêu cầu sang phase

| Yêu cầu | Phase |
|---|---|
| Roadmap: widget extension đọc kho dùng chung, cỡ vừa và cỡ lớn (FR-13) | 1 (target, entitlement, nhúng), 2 (`StoreReader`), 4 (provider, hai cỡ) |
| Roadmap: mục mới nhất nằm trên cùng (FR-11) | 2 (thứ tự trong `WidgetSnapshot`), 4 (vẽ), 6 |
| Roadmap: bố cục rút gọn cho từng loại (FR-12) | 4 (`CompactCardView`, dự phòng `title` và `summary`); bố cục `vocab` thuộc Giai đoạn 4 |
| Roadmap: nút đã đọc và xoá ngay trong widget (FR-18) | 2 (hộp thư, phủ thao tác, rút vào kho), 5 (intent, nút, app theo dõi hộp thư) |
| Roadmap: app chỉ yêu cầu làm mới khi nội dung widget đổi (NFR-2) | 3 |
| Hoàn thành khi: PRD §10.2 | 2, 3, 4, 6 |
| Hoàn thành khi: thao tác đã đọc trong widget đồng bộ sang máy kia (FR-19, FR-20; một máy qua API, Mac mini ở Giai đoạn 5) | 2, 5, 6 |
| Hoàn thành khi: số lần làm mới trong một ngày dùng thật dưới mức đo được ở B | 3 (log, script đếm), 6 (chạy 24 giờ, báo cáo) |

## Phases

| # | Phase | Status | Phụ thuộc phase | Phụ thuộc thử nghiệm A |
|---|-------|--------|---|---|
| 1 | [Widget extension target, ký và điểm nối](./phase-01-widget-target-va-diem-noi.md) | Completed | Không | Có (ký, entitlement) |
| 2 | [Đọc kho, snapshot và hộp thư thao tác](./phase-02-snapshot-va-hop-thu-thao-tac.md) | Completed | Không | Có (vị trí hộp thư) |
| 3 | [Chính sách reload và đếm reload](./phase-03-chinh-sach-reload-va-dem.md) | Completed | 1, 2 | Không |
| 4 | [Giao diện widget và bố cục rút gọn theo loại](./phase-04-giao-dien-widget-va-bo-cuc-rut-gon.md) | Completed | 1, 2 | Có (nguồn dữ liệu provider) |
| 5 | [Nút đã đọc và xoá, app nhận thao tác](./phase-05-nut-da-doc-xoa-va-nhan-thao-tac.md) | Completed | 1, 2, 4 | Có (đường gửi thao tác) |
| 6 | [Cài, nghiệm thu, đếm một ngày và tài liệu](./phase-06-nghiem-thu-va-tai-lieu.md) | Pending | 1–5 | Có (cách cài) |

Thứ tự: Phase 1 và 2 chạy song song (1 chỉ sửa project và tạo khung trong `App/`, `Widget/`; 2 chỉ sửa package). Sau khi cả hai xong, Phase 3 và 4 chạy song song. Phase 5 cần khung hàng của Phase 4. Phase 6 cần tất cả. Tối đa hai session cook cùng lúc.

```text
1 ──┐      ┌──> 3 ──────────┐
    ├──────┤                ├──> 6
2 ──┘      └──> 4 ──> 5 ────┘
```

### Sở hữu file

Đường dẫn tương đối với `apps/macos/` trừ khi ghi khác. "Tạo" là file mới do plan này tạo.

| Phase | Sở hữu (tạo hoặc sửa) |
|---|---|
| 1 | Sửa `project.yml`, `App/AppDelegate.swift` (một dòng gọi `WidgetWiring.start`), `README.md` của `apps/macos/`. Tạo `Widget/Info.plist`, `Widget/Widget.entitlements`, `Widget/OSWidgetWidgetBundle.swift` (khung), `App/Widget/WidgetWiring.swift`, khung rỗng `App/Widget/WidgetReloader.swift` và `App/Widget/InboxWatcher.swift`, `OSWidgetKit/Sources/OSWidgetKit/Widget/WidgetKind.swift` |
| 2 | Sửa `OSWidgetKit/Sources/OSWidgetKit/Store/ItemStore.swift` (tách `StoreFile`, thêm `drain`). Tạo `OSWidgetKit/Sources/OSWidgetKit/Store/StoreFile.swift`, `Store/StoreReader.swift`, `OSWidgetKit/Sources/OSWidgetKit/Widget/{WidgetSnapshot,WidgetAction,ActionInbox}.swift`, `OSWidgetKit/Tests/OSWidgetKitTests/{StoreReader,WidgetSnapshot,ActionInbox}Tests.swift` |
| 3 | Viết thân `App/Widget/WidgetReloader.swift`. Tạo `OSWidgetKit/Sources/OSWidgetKit/Widget/WidgetReloadPolicy.swift`, `OSWidgetKit/Tests/OSWidgetKitTests/WidgetReloadPolicyTests.swift`; ở gốc repo `scripts/widget-reload-count.sh`, `scripts/testdata/widget-log-sample.ndjson` |
| 4 | Sửa `Widget/OSWidgetWidgetBundle.swift`. Tạo `Widget/ItemsProvider.swift`, `Widget/ItemsWidget.swift`, `Widget/ItemsWidgetView.swift`, `Widget/ItemRow.swift`, khung `Widget/ItemRowActions.swift`, `OSWidgetKit/Sources/OSWidgetKit/Cards/Compact/*`, `OSWidgetKit/Sources/OSWidgetKit/Widget/WidgetSize.swift`, `OSWidgetKit/Tests/OSWidgetKitTests/CompactCardTests.swift` |
| 5 | Viết thân `Widget/ItemRowActions.swift`, `App/Widget/InboxWatcher.swift`. Tạo `Widget/ItemIntents.swift` |
| 6 | Ở gốc repo: tạo `scripts/acceptance-widget.sh`, `scripts/build-install-macos.sh` (chỉ khi nhánh A trượt vì chữ ký), `plans/261124-1415-m3-widget/reports/acceptance.md`, `plans/261124-1415-m3-widget/reports/reload-day.md`; sửa `docs/architecture.md`, `docs/roadmap.md` |

`App/AppDelegate.swift` chỉ được Phase 1 sửa. `WidgetWiring.start(env:)` gọi hai điểm nối có chữ ký cố định từ Phase 1 (`WidgetReloader(env:).start()`, `InboxWatcher(env:).start()`), nên Phase 3 và 5 không sửa chung file. Phase nào cần đổi chữ ký điểm nối thì dừng và báo.

**Phối hợp với Giai đoạn 4 (session M4-plan, plan `plans/261124-1415-m4-vocab/`).** Bố cục rút gọn `vocab` trong widget thuộc Giai đoạn 4. M3 để đường cho nó ở đúng một chỗ: `CompactCardView` (Phase 4) chọn view theo `CompactCardView.Variant`, ánh xạ từ `ItemContent` bằng `switch` đủ trường hợp, không có nhánh `default`. Khi Giai đoạn 4 thêm `ItemContent.vocab`, trình biên dịch buộc thêm `case .vocab` ở `CompactCardView.variant(for:)` và một file view trong `Cards/Compact/`; cho tới lúc đó `vocab` đi vào `.fallback` (`title` và `summary`). Cỡ lớn giữ một hàng cao hơn cho mục đầu (`WidgetSize.large.leadRowLines`) để thẻ `vocab` rút gọn có chỗ. Phase rút gọn `vocab` của M4 phụ thuộc Phase 4 của M3; hai plan không sửa chung file nào trong M3 trừ `Cards/Compact/CompactCardView.swift` (M4 sửa sau khi Phase 4 xong).

## Scope Challenge

- Có sẵn: kho `store.json` trong group container, hàng đợi thao tác với quy tắc gộp và gửi lại, `QueueWatcher` kích hoạt sync khi có thao tác mới, view thẻ đầy đủ và `ItemContent` chịu lỗi trong `OSWidgetKit`, mẫu widget extension của `spikes/widget-probe/`, script nghiệm thu M2 làm khuôn.
- Phạm vi: đúng bốn gạch đầu dòng và ba điều kiện hoàn thành của roadmap Giai đoạn 3. Giữ nguyên phạm vi (HOLD).
- Độ phức tạp: 6 phase, khoảng 15 file Swift mới, hai script, không phụ thuộc ngoài.

## Out of scope

- Bố cục rút gọn và thẻ đầy đủ của `vocab`, phát âm (Giai đoạn 4).
- Kênh localhost cho nhánh A trượt vì App Group (plan bổ sung sau 2026-11-30 nếu cần).
- Bấm vào thân mục trong widget để mở liên kết hoặc mở app (câu hỏi 5; đề xuất không làm trong M3).
- Widget cỡ nhỏ, widget cấu hình được (`AppIntentConfiguration`), widget trên iPhone.
- Cài và kiểm trên Mac mini (Giai đoạn 5). Báo lỗi server trên UI (Giai đoạn 5).
- Sửa "+N" của popup (follow-up M2), mọi thay đổi server, schema, API.

## Constraints

- Swift 6, SwiftUI, WidgetKit, AppIntents; deployment target macOS 26 như app. Project sinh bằng XcodeGen, không commit `.xcodeproj`.
- Team ID chỉ đặt ở `DEVELOPMENT_TEAM` trong `project.yml`; App Group của extension suy ra từ nó như app.
- Chỉ app gọi mạng; widget extension không có `network.client` (nhánh A đạt).
- Chỉ app ghi `store.json`; widget chỉ đọc file đó và chỉ ghi vào `inbox/`.
- `OSWidgetKit` không import `WidgetKit` (giữ đường thay widget bằng cửa sổ desktop theo architecture §9): view rút gọn là SwiftUI thuần, mọi mã dùng `WidgetKit` hay `AppIntents` nằm trong `Widget/` hoặc `App/Widget/`.
- Log chỉ ghi id, số đếm, trạng thái; không ghi token hay nội dung mục (architecture §6).
- Không chạm app WidgetProbe đã cài và dữ liệu của nó trong group container.
- Không làm hỏng `cargo test --workspace`, `swift test`, `scripts/acceptance-server.sh`, `scripts/acceptance-menu-bar.sh`.

## Stop and ask only if

- Nút `Button(intent:)` trong widget macOS không chạy intent trong extension (không có file nào xuất hiện ở `inbox/`), hoặc extension không ghi được vào group container khi đã có entitlement.
- Kết quả A ngày 8 rơi vào nhánh không có trong bảng ở trên.
- Một tiêu chí chỉ đạt được nếu đổi API, schema, hoặc đổi định dạng `store.json` theo cách làm bản app M2 đang cài đọc sai.

## Câu hỏi cần operator trả lời

Gửi qua session giám sát `supervisor-project` ngày 2026-11-24. Trạng thái từng câu ghi ở cột cuối; câu trả lời nguyên văn ở mục "Operator answers".

| # | Câu hỏi | Đề xuất | Phase bị ảnh hưởng | Trạng thái |
|---|---|---|---|---|
| 1 | Ngưỡng nào cho "số lần làm mới trong một ngày dùng thật nằm dưới mức đo được ở thử nghiệm B"? B chỉ đo reload khi app ở foreground (được miễn ngân sách) và không đo ngân sách nền; ước lượng không chính thức là 40–70 lần mỗi ngày. | Đạt khi trong 24 giờ dùng thật: app yêu cầu không quá 40 lần (mức thấp của ước lượng), không hai yêu cầu nào cách nhau dưới 5 s, và ít nhất 95% yêu cầu có timeline chạy trong 5 s. Vượt 40 thì ghi số đo và đề xuất ở Phase 6, không tự sửa. | 3, 6 | Đã trả lời (D9, 2026-11-24 14:24): A |
| 2 | Mỗi cỡ widget hiện bao nhiêu mục? | Cỡ vừa 3 mục, cỡ lớn 6 mục (mục đầu cao hơn để để chỗ cho thẻ `vocab` rút gọn ở Giai đoạn 4). Đầu widget có số mục chưa đọc. | 2, 3, 4 | Đã quyết (giám sát, 2026-11-24 14:3x): cỡ vừa 3 mục, cỡ lớn 6 mục (hàng đầu cao hơn), số chưa đọc ở đầu |
| 3 | Widget hiện cả mục đã đọc hay chỉ mục chưa đọc? | Hiện cả hai, mục đã đọc làm mờ, giống danh sách (FR-9, FR-11 "các mục mới nhất"). Chỉ hiện chưa đọc thì widget hay trống và mục vừa bấm đã đọc biến mất khỏi widget. | 2, 4 | Đã quyết (giám sát, 2026-11-24 14:3x): hiện cả mục đã đọc, làm mờ |
| 4 | Nút trên mỗi hàng: luôn hiện hay chỉ một nút? | Luôn hiện hai biểu tượng nhỏ ở cuối hàng: dấu tích (chỉ khi chưa đọc) và thùng rác. Widget macOS không có trạng thái hover nên không ẩn được tới khi rê chuột. | 4, 5 | Đã quyết (giám sát, 2026-11-24 14:3x): luôn hiện dấu tích (chỉ hàng chưa đọc) và thùng rác |
| 5 | Bấm vào thân một mục trong widget (ngoài hai nút) thì làm gì? | Không làm gì trong M3 (PRD chỉ yêu cầu nút đã đọc và xoá). Mở liên kết hay mở danh sách cần URL scheme cho app và quyết định có đánh dấu đã đọc không; để Giai đoạn 5 nếu cần. | 4 | Đã quyết (giám sát, 2026-11-24 14:3x): bấm thân hàng không làm gì trong M3 |
| 6 | Cài lại `OSWidget` (thay bản M2 trong `/Applications`, nay có widget nhúng) trước ngày kiểm A ngày 8 (2026-11-30) được không? Cài lại đặt lại "đồng hồ 7 ngày" của riêng OSWidget. | Được. Kết luận A lấy từ WidgetProbe (không bị đụng), không từ OSWidget. Ghi ngày cài mới vào báo cáo để lần kiểm sau đếm từ ngày đó. | 6 | Đã trả lời (D10, 2026-11-24 14:24): A (cài lại OSWidget trước 2026-11-30 chỉ ở Phase 6) |
| 7 | Đóng M3 có phải chờ đủ 24 giờ đếm reload không? | Có, vì đó là một điều kiện hoàn thành. Bắt đầu đếm ngay sau khi cài ở Phase 6 để chạy song song với các kiểm khác; trong 24 giờ đó operator dùng máy bình thường, để widget trên desktop, cho máy ngủ qua đêm. | 6 | Đã trả lời (D11, 2026-11-24 14:24): A (M3 đóng sau khi đủ 24 giờ đếm) |

## Operator answers

Ngưỡng đếm reload của câu 1 (D9): trong 24 giờ có tối đa 40 yêu cầu reload từ app, không hai yêu cầu nào cách nhau dưới 5 s, và ít nhất 95% yêu cầu có timeline chạy trong 5 s. Script đếm kết luận đạt hay trượt theo ngưỡng này.

Ghi lại từ file ledger của operator, mỗi câu trả lời nguyên văn là "A" (2026-11-24 14:24, múi giờ Asia/Saigon):

| Quyết định | Câu hỏi | Trả lời (nguyên văn) |
|---|---|---|
| D9 | 1 | A |
| D10 | 6 | A |
| D11 | 7 | A |

Quyết định của giám sát cho các câu thiết kế (2026-11-24 14:3x, cuối cùng cho phase này; không phải câu trả lời của operator):

| Câu | Quyết định |
|---|---|
| 2 | Cỡ vừa hiện 3 mục, cỡ lớn 6 mục (hàng đầu cao hơn); số chưa đọc ở đầu widget |
| 3 | Hiện cả mục đã đọc, làm mờ |
| 4 | Luôn hiện dấu tích (chỉ hàng chưa đọc) và thùng rác |
| 5 | Bấm thân hàng không làm gì trong M3 |

Quyết định của giám sát (15:1x): snapshot chỉ khác ở số chưa đọc (một mục ngoài các hàng đang hiện được đọc) vẫn là thay đổi nội dung thật và kích hoạt reload.

## Validation Log

### Session 1 (2026-11-24)

Bảy câu hỏi ở trên gửi cho `supervisor-project`. Kiểm khi viết plan: mọi gạch đầu dòng và điều kiện "Hoàn thành khi" của roadmap Giai đoạn 3 có ít nhất một phase (bảng ánh xạ); các tên đã có trong mã mà plan dùng (`ItemStore.markRead`, `ItemStore.delete`, `ItemStore.visibleItems`, `ItemStore.unreadCount`, `ItemStore.queue`, `StoreLocation.appGroup`, `QueueWatcher`, `SyncWiring.start`, `AppEnvironment`, `CardView.Variant`, `ItemContent`, `PendingAction.Operation`, `Item.isVisible(at:)`, `LossyArray`, `ServerJSON`, `FallbackCardView`, dòng log `sync.applied` và `popup.shown`, `scripts/acceptance-menu-bar.sh`) đã kiểm bằng `git grep`.

<!-- slug: m3-widget -->
