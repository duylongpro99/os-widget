---
phase: 6
title: "Cài, nghiệm thu, đếm một ngày và tài liệu"
status: pending
priority: P1
effort: "3h (cộng 24 giờ đếm)"
dependencies: [1, 2, 3, 4, 5]
---

# Phase 6: Cài, nghiệm thu, đếm một ngày và tài liệu

## Goal

App có widget được cài trên MacBook, ba điều kiện hoàn thành của roadmap Giai đoạn 3 được kiểm bằng `scripts/acceptance-widget.sh` và checklist của operator, số reload của 24 giờ dùng thật được ghi vào báo cáo, và architecture §6 cùng roadmap Giai đoạn 3 ghi đúng những gì đã làm.

## Context

- Phụ thuộc thử nghiệm A: cách cài. Nhánh A đạt: build Release `xcodebuild -allowProvisioningUpdates`, derived data ngoài repo, copy vào `/Applications/OSWidget.app` như M2 (báo cáo nghiệm thu M2, mục Môi trường). Nhánh A trượt vì chữ ký: tạo `scripts/build-install-macos.sh` (build, thay app, mở lại) và dùng nó; checklist thêm việc kiểm widget còn trên desktop sau mỗi lần cài lại.
- Câu hỏi 6: được cài lại trước 2026-11-30; ghi ngày giờ cài mới vào báo cáo. Câu hỏi 7: M3 chỉ đóng khi đủ 24 giờ đếm. Câu hỏi 1: ngưỡng đếm.
- Máy thứ hai chưa có: thiết bị thứ hai giả bằng API với token client, như M2 tiêu chí 3; kiểm Mac mini thật ở Giai đoạn 5.
- Khuôn script: `scripts/acceptance-menu-bar.sh` (token đọc từ biến môi trường, ghi ra file header quyền 700, không in token; mục thử `ttl 3600`, `dedupe_key` theo lượt chạy, xoá khi kết thúc kể cả khi dừng sớm; `ask` y/n cho phần cần mắt người; in PASS/FAIL từng tiêu chí, thoát 1 khi có FAIL).
- Không đụng WidgetProbe: ghi mtime bundle và `codesign -dvvv` trước và sau như M2.

## Requirements

**Cài:**

- Build Release có ký, cài vào `/Applications`, mở app. Kiểm: `codesign --verify --deep --strict`; `codesign -d --entitlements -` của app (sandbox, `network.client`, App Group) và của `Contents/PlugIns/OSWidgetWidget.appex` (sandbox, App Group, không `network.client`); `pluginkit -m -i local.oswidget.app.widget` thấy widget. Số identity ký trước và sau không đổi.
- Operator thêm widget cỡ vừa và cỡ lớn lên desktop ("Edit Widgets").
- Bắt đầu đếm 24 giờ ngay sau đó: ghi mốc bắt đầu; nếu `log show` không giữ đủ 24 giờ dòng `notice`, chạy song song `log stream --style ndjson --predicate 'subsystem == "local.oswidget.app" AND category == "widget"' > <file ngoài repo>` bằng tiến trình nền có theo dõi PID và dừng khi đủ 24 giờ (quy tắc quản lý tiến trình của repo).

**Script nghiệm thu** (ở gốc repo `scripts/acceptance-widget.sh <2|read|delete|offline|reload|day|all>`, theo khuôn M2):

- `2` (PRD §10.2, NFR-2): publish một `notification`; chờ dòng `sync.applied … new=1` đầu tiên sau lúc publish và dòng `widget.timeline top=<id>` (cả `family=medium` và `family=large` nếu cả hai đang trên desktop); PASS khi độ trễ giữa hai dòng < 5 s và operator trả lời có cho "mục `<title>` nằm trên cùng ở cả hai widget và ở đầu danh sách". Lặp 5 lần cách nhau 40 s (tránh throttle theo B), in độ trễ từng lần.
- `read`: publish; operator bấm dấu tích trên widget; chờ `widget.intent action=read id=<id>` (log của extension) và `widget.inbox_drained`; rồi `GET /items` có `read_at` cho mục và `GET /events` có `item.read` với `item_id` đó. Operator xác nhận widget và danh sách hiện mục đã đọc.
- `delete`: như `read`, với `item.deleted` và mục biến khỏi `GET /items`, widget và danh sách.
- `offline` (FR-20): operator tắt Wi-Fi; bấm dấu tích trên widget; script kiểm `widget.inbox_drained` có trong log và `GET /items` chưa có `read_at` (gọi sau khi bật lại thì không kiểm được, nên bước này chỉ kiểm log app); operator bật Wi-Fi; script chờ `read_at` trên server trong 60 s.
- `reload`: publish 5 mục trong khoảng 3 s; kiểm trong 15 s sau đó có không quá 3 dòng `widget.reload`, các dòng cách nhau ≥ 5 s, và dòng `widget.timeline` cuối có `top=` là mục publish sau cùng. Rồi chờ một vòng poll không có thay đổi (dòng `sync.start` không kèm `sync.applied … new=` khác 0 và không có sự kiện đổi trạng thái) và kiểm không có `widget.reload` nào trong 6 s sau đó.
- `day`: gọi `scripts/widget-reload-count.sh --start <mốc bắt đầu> --end <mốc + 24h>` (hoặc `--input` file `log stream`), so với ngưỡng của câu hỏi 1, in PASS/FAIL kèm các số.
- `all`: chạy `2`, `read`, `delete`, `reload`; `offline` và `day` chạy riêng.

**Checklist operator** (ghi kết quả vào báo cáo, mỗi mục đạt/không đạt kèm lời operator):

1. Cỡ vừa hiện 3 mục, cỡ lớn 6 mục, mới nhất trên cùng; đầu widget có số chưa đọc đúng với dấu báo trên thanh menu.
2. Mục `notification`, `generic` và `vocab` (chưa có bố cục riêng, hiện `title` và `summary`) đều hiện gọn, không tràn chữ.
3. Mục đã đọc làm mờ; dấu tích không hiện trên mục đã đọc.
4. Bấm nút khi app OSWidget đã thoát (Quit từ menu): widget cập nhật ngay; mở lại app thì thao tác được gửi (kiểm bằng `GET /items`).
5. Bấm vào thân mục không làm gì (câu hỏi 5).
6. Chế độ sáng và tối của hệ thống đều đọc được.
7. Sau một đêm ngủ máy: widget hiện mục publish trong đêm sau khi máy thức (một vòng sync, một reload).
8. Popup và danh sách M2 vẫn chạy như trước (chạy lại `scripts/acceptance-menu-bar.sh 1` và `6`).

**Báo cáo và tài liệu:**

- `plans/261124-1415-m3-widget/reports/acceptance.md`: tóm tắt PASS/FAIL, môi trường (macOS, Xcode, commit, ngày giờ cài, chữ ký), đầu ra script, checklist, phát hiện và sửa.
- `plans/261124-1415-m3-widget/reports/reload-day.md`: mốc bắt đầu và kết thúc, đầu ra `widget-reload-count.sh`, phân bố theo giờ, so với ngưỡng, nhận xét về ngân sách nền (câu hỏi mở của B). Nếu có yêu cầu không được phục vụ trong 5 s hay vượt ngưỡng: ghi số và đề xuất theo bảng nhánh của plan.md, không tự sửa mã.
- `docs/architecture.md` §6: thêm mục "Widget đã làm (Giai đoạn 3)" (target, bundle id, hộp thư thao tác, chính sách reload, log đếm); sửa câu "Ở Giai đoạn 2 chỉ app ghi kho…" thành thiết kế hộp thư; §9 dòng "Widget làm mới chậm" ghi số đo một ngày.
- `docs/roadmap.md` Giai đoạn 3: mục "Kết quả" theo khuôn Giai đoạn 2 (bảng ba điều kiện, việc hoãn sang Giai đoạn 5).

## Files to Create / Modify

- Create: `scripts/acceptance-widget.sh`, `plans/261124-1415-m3-widget/reports/acceptance.md`, `plans/261124-1415-m3-widget/reports/reload-day.md`; `scripts/build-install-macos.sh` chỉ ở nhánh A trượt vì chữ ký
- Modify: `docs/architecture.md`, `docs/roadmap.md`

## Tasks & Steps

- [ ] Ghi trạng thái WidgetProbe (mtime, `codesign -dvvv`) và số identity ký.
- [ ] Build Release, cài, kiểm chữ ký và entitlement, `pluginkit`.
- [ ] Operator thêm hai widget; bắt đầu đếm 24 giờ.
- [ ] Viết và chạy `acceptance-widget.sh` (`all`, rồi `offline`).
- [ ] Checklist operator (mục 7 cần một đêm).
- [ ] Sau 24 giờ: `acceptance-widget.sh day`, viết `reload-day.md`, dừng `log stream` nếu đã chạy.
- [ ] Báo cáo, architecture, roadmap. Kiểm lại WidgetProbe không đổi.

## Verification

- `scripts/acceptance-widget.sh all` in PASS cho `2`, `read`, `delete`, `reload`; `offline` PASS; `day` PASS hoặc FAIL có số đo và đề xuất đã gửi operator.
- `cargo test --workspace` và `swift test` pass; `scripts/acceptance-server.sh` vẫn PASS.
- Mọi đường dẫn và tên trong architecture §6 mới kiểm bằng `git grep`.

## Risk Assessment

- Cài lại đặt lại ngày ký của OSWidget; kết luận A ngày 8 vẫn lấy từ WidgetProbe (câu hỏi 6).
- Hệ thống có thể gỡ widget khỏi desktop khi app được thay; checklist mục 1 phát hiện, operator thêm lại.
- Máy ngủ trong 24 giờ đếm là đúng ý (dùng thật); script tính độ trễ chỉ cho các yêu cầu khi máy thức (yêu cầu không có timeline vì máy ngủ ngay sau đó được liệt kê riêng).
- Token: script chỉ đọc từ biến môi trường, không in, không ghi vào báo cáo.

## Rollback

Cài lại bản M2 (commit `2f7bf2e`) cùng cách build; operator gỡ widget khỏi desktop. Hoàn lại sửa đổi tài liệu bằng `git revert` commit tài liệu của phase.
