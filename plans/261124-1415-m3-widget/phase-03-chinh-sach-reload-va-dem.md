---
phase: 3
title: "Chính sách reload và đếm reload"
status: pending
priority: P1
effort: "4h"
dependencies: [1, 2]
---

# Phase 3: Chính sách reload và đếm reload

## Goal

App yêu cầu WidgetKit làm mới chỉ khi `WidgetSnapshot` đổi, không quá một lần mỗi 5 giây, và ghi mỗi yêu cầu vào unified log ở mức được lưu lại. Một script đếm được số yêu cầu, số lần timeline chạy và độ trễ giữa hai thứ đó trong một khoảng thời gian bất kỳ, mặc định 24 giờ.

## Context

- Chính sách: plan.md, mục "Chính sách reload". NFR-2: mục mới hiện ở widget trong 5 s ở ≥ 95% trường hợp; gộp reload, không quá một lần mỗi 5 s.
- B (`b-results.md`): reload được cho phép vẽ lại sau p50 66 ms; gọi dồn thì chronod cho một yêu cầu qua, giữ một reload chờ và chạy lại khoảng mỗi 5 s; cách nhau ≥ 30 s thì không yêu cầu nào bị chặn. Ngân sách khi app chạy nền chưa đo. Dòng log quyết định của chronod ở mức debug, không được lưu lâu, nên số đếm phải dựa vào log của chính app và extension.
- Không phụ thuộc thử nghiệm A.
- Phase 1 tạo khung `App/Widget/WidgetReloader.swift` (`init(env:)`, `start()`) và `WidgetKind.items`; Phase 2 tạo `WidgetSnapshot.make`, `ActionInbox`.
- M2 ghi log bằng `.info` (không được lưu bền); dòng của phase này dùng `.notice`.

## Requirements

**Chính sách** (`OSWidgetKit/Sources/OSWidgetKit/Widget/WidgetReloadPolicy.swift`, thuần, test được):

- `public struct WidgetReloadPolicy: Sendable` với `minimumInterval: Duration = .seconds(5)`.
- `mutating func offer(_ snapshot: WidgetSnapshot, at now: Date) -> Decision`: `.skip` khi bằng snapshot đã reload gần nhất (hoặc bằng snapshot đang chờ); `.reloadNow` khi khác và lần reload trước đã cách ≥ 5 s (hoặc chưa từng reload); `.schedule(at: Date)` khi khác nhưng chưa đủ 5 s, chỉ trả một lần cho mỗi khoảng chờ (lần `offer` sau trong cùng khoảng chỉ thay snapshot đang chờ và trả `.skip`).
- `mutating func fire(at now: Date) -> Bool`: gọi khi hẹn giờ tới; trả `true` nếu snapshot đang chờ vẫn khác snapshot đã reload (khi đó coi như đã reload).
- `mutating func didReload(_ snapshot:, at:)` và đếm theo ngày địa phương: `reloadsToday` đặt về 0 khi qua nửa đêm (múi giờ của máy).
- Lần đầu sau khi app chạy luôn là `.reloadNow` (widget có thể đang hiện dữ liệu cũ của lần chạy trước).

**Reloader trong app** (`App/Widget/WidgetReloader.swift`):

- Quan sát `env.store.items` bằng `withObservationTracking` (cùng cách `QueueWatcher`), mỗi lần đổi dựng `WidgetSnapshot.make(items: store.items, pending: ActionInbox(...).pending(), now:)` rồi hỏi chính sách. Thao tác chỉ đổi `queue` hay `cursor` không kích hoạt.
- `.reloadNow` và lần hẹn giờ bắn: gọi `WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.items)` rồi ghi `widget.reload n_today=<n> reason=<first|changed|trailing> gap_ms=<ms từ lần trước>` bằng `Logger(subsystem: "local.oswidget.app", category: "widget").notice`.
- `.skip`: ghi `widget.reload_skipped reason=<unchanged|coalesced>` ở mức `debug` (không lưu, chỉ để soi khi cần).
- Kho chạy trong bộ nhớ (không có group container) thì không reload và ghi một lần `widget.reload_disabled reason=no_container`.

**Script đếm** (ở gốc repo `scripts/widget-reload-count.sh`):

- `scripts/widget-reload-count.sh [--last 24h | --start "YYYY-MM-DD HH:MM:SS" --end "…"] [--input <ndjson>]`: đọc `log show --style ndjson --info --predicate 'subsystem == "local.oswidget.app" AND category == "widget"'` (hoặc file `--input` để test), in:
  - số dòng `widget.reload` (yêu cầu) theo lý do, và theo từng giờ;
  - số dòng `widget.timeline` (lần timeline chạy, gồm cả lần do hệ thống hay do bấm nút);
  - khoảng cách nhỏ nhất giữa hai yêu cầu;
  - với mỗi yêu cầu, lần `widget.timeline` đầu tiên sau nó: p50, p95, max độ trễ, và số yêu cầu không có timeline trong 5 s;
  - một dòng tóm tắt `requests=<n> min_gap_ms=<n> within_5s=<pct> timelines=<n>` để Phase 6 so với ngưỡng (câu hỏi 1).
- Chỉ dùng `bash`, `jq`, `/usr/bin/log`; không cần token.
- `scripts/testdata/widget-log-sample.ndjson`: mẫu ndjson viết tay (vài yêu cầu, một đợt dồn, một yêu cầu không có timeline) để kiểm script.

## Files to Create / Modify

- Modify: `apps/macos/App/Widget/WidgetReloader.swift`
- Create: `apps/macos/OSWidgetKit/Sources/OSWidgetKit/Widget/WidgetReloadPolicy.swift`, `apps/macos/OSWidgetKit/Tests/OSWidgetKitTests/WidgetReloadPolicyTests.swift`, `scripts/widget-reload-count.sh`, `scripts/testdata/widget-log-sample.ndjson`

## Tasks & Steps

- [ ] `WidgetReloadPolicy` và test.
- [ ] Thân `WidgetReloader` (quan sát, hẹn giờ một lần bằng `Task.sleep`, gọi `WidgetCenter`, log).
- [ ] Script đếm và mẫu ndjson; chạy script trên mẫu.
- [ ] Build Debug không ký.

| Test | Kiểm |
|---|---|
| Không đổi | Cùng snapshot hai lần: lần hai `.skip` |
| Đổi | Snapshot khác sau ≥ 5 s: `.reloadNow` |
| Gộp | Ba snapshot khác nhau trong 2 s sau một lần reload: đúng một `.schedule`, `fire` dùng snapshot cuối |
| Dồn | 50 snapshot khác nhau trong 12,4 s (như đợt dồn của B): không quá 4 lần reload, các lần cách nhau ≥ 5 s, lần cuối mang snapshot cuối |
| Đổi rồi đổi lại | Snapshot A, rồi B, rồi A trong khoảng chờ: `fire` trả `false` (không reload vì nội dung bằng lần trước) |
| Lần đầu | Lần `offer` đầu tiên luôn `.reloadNow` |
| Đếm theo ngày | `reloadsToday` về 0 sau nửa đêm |

## Verification

- `cd apps/macos/OSWidgetKit && swift test` pass.
- `scripts/widget-reload-count.sh --input scripts/testdata/widget-log-sample.ndjson` in đúng số đã biết trước của mẫu (ghi các số mong đợi trong đầu file mẫu dưới dạng chú thích của script hoặc trong báo cáo cook).
- `xcodebuild … CODE_SIGNING_ALLOWED=NO build` thành công.
- `git grep -n "reloadAllTimelines\|reloadTimelines" apps/macos` chỉ thấy trong `App/Widget/WidgetReloader.swift`.

## Risk Assessment

- Nhiều lần `@Observable` báo đổi trong một vòng sync (mỗi `apply` một trang): snapshot giống nhau nên `.skip`; khác nhau thì gộp. Không reload theo từng trang.
- `withObservationTracking` chỉ báo một lần mỗi lần đăng ký; phải đăng ký lại sau mỗi lần báo (như `QueueWatcher`).
- Mức `notice` có thể bị giới hạn dung lượng log khi máy ghi nhiều; một ngày chỉ vài chục dòng nên không sao. Nếu `log show --last 24h` thiếu dòng đầu ngày, Phase 6 chạy thêm `log stream` vào file trong suốt 24 giờ.
- Chênh lệch giữa `widget.reload` và `widget.timeline` có thể do hệ thống tự chạy timeline (lúc hiện desktop, sau khi bấm nút). Script báo cả hai, không coi timeline thừa là lỗi.

## Rollback

Trả `WidgetReloader.swift` về khung rỗng của Phase 1, xoá file chính sách, test và script. App không yêu cầu reload; widget vẫn cập nhật khi hệ thống tự chạy timeline.
