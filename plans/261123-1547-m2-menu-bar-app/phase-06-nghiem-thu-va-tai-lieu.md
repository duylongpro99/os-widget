---
phase: 6
title: "Cài trên MacBook, nghiệm thu và cập nhật tài liệu"
status: pending
priority: P1
effort: "4h"
dependencies: [3, 4, 5]
---

# Phase 6: Cài trên MacBook, nghiệm thu và cập nhật tài liệu

## Goal

App chạy từ `/Applications` trên MacBook, đạt tiêu chí 1, 3, 4, 6 của PRD §10 và quy tắc không cướp focus, có báo cáo nghiệm thu lặp lại được, và architecture cùng roadmap ghi đúng những gì đã làm.

## Context

- Phụ thuộc thử nghiệm A: quy trình cài theo nhánh đã chọn ở Phase 1 (nếu A thất bại vì hết hạn: build lại hằng tuần, operator trả lời câu hỏi 4). Phụ thuộc B: chỉ để ghi điều Giai đoạn 3 phải đổi; B không chặn nghiệm thu M2.
- M2 chỉ cài trên MacBook (operator trả lời câu hỏi 1, 2026-11-23). Tiêu chí §10.3 kiểm trên một máy, thiết bị thứ hai giả bằng API với token client; kiểm với Mac mini thật chuyển sang Giai đoạn 5. Ba mục của §10.4 được publish từ một máy khác chỉ chạy CLI (ví dụ Mac mini, không cài app), vì MacBook đang mất mạng.
- Mẫu script: `scripts/acceptance-server.sh` (đọc token từ biến môi trường, header trong file `chmod 700`, mục thử có `source` riêng và `ttl` 3600, xoá mục thử khi kết thúc kể cả khi dừng giữa chừng, in PASS hoặc FAIL từng tiêu chí, thoát 1 khi có tiêu chí trượt). Publish bằng CLI `os-widget publish` (crate `cli`, chạy qua `cargo run -q -p cli --` hoặc binary đã build).
- Server không nhận `kind` ngoài `notification`, `vocab`, `generic`, nên tiêu chí §10.6 kiểm đầu-cuối bằng mục `vocab` (client M2 chưa có view `vocab`), còn chuỗi `kind` không tồn tại đã có unit test ở Phase 2 và 4.

## Requirements

**Script** `scripts/acceptance-menu-bar.sh`, chạy trên MacBook (máy cài app), đọc log của app tại chỗ:

- Biến môi trường: `PUBLISH_TOKEN`, `CLIENT_TOKEN`, `OS_WIDGET_SERVER`. Script đưa `PUBLISH_TOKEN` cho CLI qua `OS_WIDGET_PUBLISH_TOKEN` chỉ trong lệnh publish, như `acceptance-server.sh`. Tham số: tiêu chí cần chạy (`1`, `3`, `4`, `6`, `focus`, hoặc `all`).
- Mỗi tiêu chí in hướng dẫn cho operator, publish mục thử (`source: "acceptance-m2"`, `ttl` 3600, `dedupe_key` theo lượt chạy), kiểm phần tự động được bằng API, rồi hỏi operator xác nhận phần cần mắt người (`y/n`). In PASS hoặc FAIL, cuối cùng in tổng và xoá mọi mục thử.

| Tiêu chí | Tự động | Operator xác nhận |
|---|---|---|
| 1. Popup trong 5 giây | Publish một `notification`; đọc `latency_ms` từ `log show --last 2m --predicate 'subsystem == "local.oswidget.app" AND eventMessage CONTAINS "popup.shown id=<id>"'`; PASS khi ≤ 5000 | Popup hiện với đúng tiêu đề |
| 3a. Đã đọc từ thiết bị khác (giả bằng API) | Publish một mục; sau khi nó hiện chưa đọc, script gọi `PATCH /items/{id}` `{"read": true}` bằng token client (vai thiết bị thứ hai); log app có `sync.applied` chứa sự kiện đó | Trong vài giây mục thành đã đọc trong danh sách MacBook và dấu báo giảm |
| 3b. Đã đọc từ MacBook sang server | Publish một mục; sau khi operator bấm đã đọc trên MacBook: `GET /items` thấy `read_at` của mục đã đặt; `GET /events` có `item.read` | Operator đã bấm đã đọc trên thẻ |
| 4. Mất mạng, ba mục | Hướng dẫn tắt Wi-Fi MacBook và kiểm `ping` thất bại; in ba lệnh `os-widget publish` (cùng `run_id`) để operator chạy ở máy khác chỉ có CLI, rồi chờ operator bấm Enter; hướng dẫn bật lại mạng; sau đó `GET /items` thấy đủ ba mục để xoá ở cuối | Danh sách MacBook có đủ ba mục, mỗi mục một lần; popup hiện mục mới nhất kèm "+2 mục khác" |
| 6. Loại lạ | Publish một `vocab` hợp lệ bằng `--file` | Thẻ hiện `title` và `summary`, không có lỗi |
| Focus | Đếm ngược 10 giây rồi publish; script ghi `lsappinfo front` trước khi publish và sau khi `popup.shown` xuất hiện, PASS khi cả hai là TextEdit | Đang gõ TextEdit: ký tự vẫn vào TextEdit |

- Tham số tiêu chí `3` chạy cả 3a và 3b.
- Không in token; header trong file tạm quyền 600 như `acceptance-server.sh`.

**Cài đặt trên MacBook:** `xcodegen generate`, build Release với `-allowProvisioningUpdates`, copy `OSWidget.app` vào `/Applications`, mở, nhập cấu hình ở cửa sổ cài đặt, bật "Mở khi đăng nhập". Nếu nhánh A là "build lại định kỳ", gói các bước này vào `scripts/build-install-macos.sh` và ghi chu kỳ build lại.

**Tài liệu:**

- `docs/architecture.md` §6: vị trí app (`apps/macos/`), package `OSWidgetKit`, kho `store.json` và nơi đặt nó theo kết quả A, client Realtime Phoenix tự viết (heartbeat 25 giây, kết nối lại lùi dần tới 60 giây), chu kỳ poll 5 phút, lùi cursor 20, đối chiếu 6 giờ, quy tắc hàng đợi (404 là xong, 401 và 403 dừng). §9: cập nhật hàng "Profile ký hết hạn" theo kết quả A.
- `docs/roadmap.md` Giai đoạn 2: phần "Kết quả" với bảng tiêu chí như Giai đoạn 1, liên kết tới báo cáo nghiệm thu. Ghi chú cho Giai đoạn 3 theo kết quả B (giữ WidgetKit hay chuyển sang cửa sổ desktop dùng lại `OSWidgetKit`), và việc kho chỉ có một tiến trình ghi ở M2 (Giai đoạn 3 cần phối hợp ghi nếu widget ghi hàng đợi).
- Không sửa `plans/261122-0754-m0-kiem-chung-worker-rust/reports/b-results.md` hay hàng B của roadmap (thuộc session đo B).

## Files to Create / Modify

- Create: `scripts/acceptance-menu-bar.sh`
- Create (chỉ khi nhánh A cần): `scripts/build-install-macos.sh`
- Create: `plans/261123-1547-m2-menu-bar-app/reports/acceptance.md`
- Modify: `docs/architecture.md`, `docs/roadmap.md`

## Tasks & Steps

- [ ] Viết `scripts/acceptance-menu-bar.sh`; `bash -n` và `shellcheck` sạch.
- [ ] Build và cài trên MacBook. Không cài app trên Mac mini trong M2.
- [ ] Chạy `scripts/acceptance-server.sh` trước để chắc server vẫn 8/8.
- [ ] Chạy `scripts/acceptance-menu-bar.sh all` trên MacBook (bước §10.4 cần một máy khác chạy CLI); lưu đầu ra (đã bỏ mọi giá trị nhạy cảm) và các câu trả lời vào `reports/acceptance.md`, kèm phiên bản macOS, Xcode, commit.
- [ ] Đăng xuất rồi đăng nhập lại trên MacBook: app tự chạy, không có icon Dock (FR-5).
- [ ] Để app chạy qua một lần ngủ máy: sáng hôm sau mục publish trong đêm có trong danh sách, log có một vòng sync sau `didWake`.
- [ ] Cập nhật architecture và roadmap như Requirements.

## Verification

- `reports/acceptance.md` có PASS cho 1, 3, 4, 6 và focus, với `latency_ms` của tiêu chí 1.
- `cd apps/macos/OSWidgetKit && swift test` pass; `cargo test --workspace` vẫn pass.
- `git grep -nE 'sb_secret_[A-Za-z0-9]{8,}|sb_publishable_[A-Za-z0-9]{8,}|eyJhbGci[A-Za-z0-9_-]{20,}' -- ':!.claude'` rỗng.
- Liên kết trong `docs/roadmap.md` tới báo cáo nghiệm thu mở được.

## Risk Assessment

- Đồng hồ MacBook lệch với server làm `latency_ms` sai: `latency_ms` tính trên MacBook so với `created_at` của server; kiểm `sntp time.apple.com` trên MacBook trước khi đo và ghi độ lệch vào báo cáo.
- Popup trượt 5 giây vì Realtime trễ: log `realtime.state` và `sync.applied` cho biết trễ ở đâu. Nếu Realtime đến chậm thường xuyên, ghi số đo và dừng hỏi; không rút chu kỳ poll xuống dưới 1 phút (NFR-5).
- Tắt Wi-Fi không cắt hết mạng nếu MacBook có Ethernet hoặc chia sẻ điện thoại: hướng dẫn trong script yêu cầu kiểm `networkQuality` hoặc `ping` thất bại trước khi publish.
- Mục thử sót lại nếu script dừng giữa chừng: `trap` xoá như `acceptance-server.sh`; mục còn sót tự hết hạn sau 3600 giây.

## Rollback

Gỡ app khỏi `/Applications` trên MacBook, tắt mục Login Items, xoá `store.json` trong group container (không đụng dữ liệu WidgetProbe) và mục Keychain `local.oswidget.app`. Revert commit tài liệu nếu nghiệm thu không đạt; giữ báo cáo nghiệm thu làm bằng chứng.
