# Báo cáo nghiệm thu Giai đoạn 3: Widget (phần đầu của Phase 6)

Phần này do session `m3-widget-p06-run` làm: cài bản có widget, chạy `scripts/acceptance-widget.sh`, checklist của operator trừ mục 7, và bắt đầu đếm reload 24 giờ. Kết luận đếm ngày và tài liệu do session `m3-widget-p06-finish` làm ngày 2026-11-26; mục 7 và trạng thái phase còn chờ.

## Tóm tắt

| Kiểm | Kết quả |
|---|---|
| Cài, chữ ký, entitlement, `pluginkit` | Đạt |
| `2` PRD §10.2, NFR-2 (5 lần) | PASS, trễ `sync.applied` → `widget.timeline` lớn nhất mỗi lần 101, 117, 139, 199, 251 ms; operator thấy mục trên cùng ở hai widget và danh sách |
| `read` | Lần đầu FAIL: không có lần bấm nào tới nút (xem Phát hiện 1). Chạy lại PASS: intent → rút hộp thư 214 ms → `item.read` seq 478 |
| `delete` | Lần đầu FAIL: thao tác làm trong danh sách của app, không qua widget (Phát hiện 1). Chạy lại PASS: intent → rút hộp thư 218 ms → `item.deleted` seq 484 |
| `reload` | PASS: 5 mục trong 3 s → 2 reload cách 5146 ms, timeline cuối đúng mục cuối; vòng sync `new=0` không kèm reload |
| `offline` (FR-20) | PASS (lượt thứ hai, 17:15–17:16): bấm khi mất mạng → widget mờ ngay, app rút hộp thư khi offline, `sync.queue_sent … 204` 0,4 s sau khi có mạng lại. Operator xác nhận hàng mờ ngay khi bấm lúc offline (D27 "A"). Lượt đầu (17:02–17:12) hết giờ vì operator chưa tắt mạng |
| Checklist 1–6 | Đạt (mục 3 và 4 có bằng chứng log, xem bảng checklist) |
| Checklist 8 (`acceptance-menu-bar.sh 1`, `6`) | PASS, popup `latency_ms=637`; thẻ `vocab` hiện tiêu đề và tóm tắt |
| `day` (D9) | FAIL: 45 yêu cầu reload trên ngưỡng 40, cả 45 thuộc phần nghiệm thu, phần dùng thật 0; không cặp nào dưới 5 s (nhỏ nhất 5006 ms), 100% có timeline trong 5 s. Chi tiết và đề xuất ở [reload-day.md](./reload-day.md) |
| Checklist 7 (một đêm) | chờ: đêm 26–27/11, thẻ vocab từ cron |

Mốc đếm 24 giờ: bắt đầu 2026-11-24 15:28:48; `log stream` PID 6328 ghi `~/Library/Logs/os-widget/widget-day-20261124.ndjson`.

## Môi trường

- Ngày chạy: 2026-11-24 từ 15:01 (Asia/Saigon), trên MacBook.
- macOS 27.2.1 (26B131); Xcode 27.2 (27B52); xcodegen 2.48.0.
- Mã app: `main` commit `641deb2` (widget phase 1–5 đã merge, cộng thẻ `vocab` và nút phát âm của Giai đoạn 4). Build từ worktree `widget-acceptance` sau `xcodegen generate`.
- Build `xcodebuild -scheme OSWidget -configuration Release -allowProvisioningUpdates`, derived data trong thư mục tạm ngoài repo. Thoát app cũ bằng Apple Event `quit`, xoá `/Applications/OSWidget.app`, `ditto` bản mới vào, `open`.
- **Cài lúc 2026-11-24 15:02:17 (+0700).** Đồng hồ 7 ngày của OSWidget tính từ mốc này (câu hỏi 6, D10).
- Bản build trong derived data cũng được `pluginkit` đăng ký thành widget thứ hai cùng bundle id; đã gỡ (`pluginkit -r`, `lsregister -u`, xoá bản build) để gallery chỉ có bản trong `/Applications`.
- Chữ ký: Apple Development `longdaobk17@gmail.com (N5MCHDCD2R)`, Team `22LZWPB3XL`, `Signed Time` 2026-11-24 15:02:03. Số identity ký trước và sau build đều là 1 (cùng SHA-1 `0661127514D7…`), không chứng chỉ nào được tạo hay thu hồi.
- `codesign --verify --deep --strict /Applications/OSWidget.app`: đạt.
- Entitlement app (`local.oswidget.app`): `app-sandbox`, `network.client`, `application-groups` = `22LZWPB3XL.os-widget`, `get-task-allow`.
- Entitlement extension (`Contents/PlugIns/OSWidgetWidget.appex`, `local.oswidget.app.widget`): `app-sandbox`, `application-groups` = `22LZWPB3XL.os-widget`, `get-task-allow`; không có `network.client`.
- `pluginkit -m -i local.oswidget.app.widget`: một plug-in, `/Applications/OSWidget.app/Contents/PlugIns/OSWidgetWidget.appex`.
- App chạy lại ngay sau khi cài: `widget.reload n_today=1 reason=first` lúc 15:02:18.573, `sync.applied seq=423..442 new=0`, `realtime.state joined`.
- Thử nghiệm A: nhánh "A đạt" (ký và App Group dùng được). WidgetProbe không bị đụng: mtime bundle `1795358837` (22/11 21:47:17), `Identifier=local.oswidget.probe`, `CDHash=7baa39edf5a1a594082f8f9aff02f6028125501d`, SHA-256 đầu ra `codesign -dvvv` `c5eda6f5…dc66ff7` trước khi build. Sau các bước nghiệm thu (16:49) mtime, `CDHash` và SHA-256 đầu ra `codesign -dvvv` giống hệt; số identity ký vẫn là 1.
- Token publish và token client lấy từ Keychain (`os-widget-publish-token`, `os-widget-client-token`) vào biến môi trường ngay trong lệnh chạy script, không in ra; script ghi chúng vào file header quyền 700 trong thư mục tạm, xoá khi thoát.
- Câu trả lời y/n của operator đi qua session giám sát; session này ghi câu trả lời đã relay vào FIFO mà script đọc (`OPERATOR_INPUT`).

## Đầu ra `scripts/acceptance-widget.sh`

Chạy với token từ Keychain; câu trả lời y/n là câu operator trả lời qua session giám sát (mã quyết định trong ledger ghi kèm). Đã bỏ các dòng `cleanup` lặp lại; mọi lượt chạy kết thúc với server còn 0 mục thử.

`all`, 15:29–15:58:

```text
round 1 494cdcdd-… medium: 101 ms / large: 36 ms from sync.applied to widget.timeline
round 2 8acb8cf3-… medium: 37 ms / large: 117 ms
round 3 a87bc7be-… medium: 139 ms / large: 33 ms
round 4 75d4e290-… medium: 199 ms / large: 48 ms
round 5 6313a9f8-… medium: 251 ms / large: 56 ms
PASS 2 top in under 5 s in 5 rounds (worst per round: 101 117 139 199 251 ms); operator saw it on top   (D17 "A")
FAIL read: no widget.intent action=read id=b7363378-… within 10 minutes
FAIL delete: no widget.intent action=delete id=78e02a90-… within 10 minutes
reloads: 2, gaps ms: 5146 ; last timeline: widget.timeline family=medium items=3 unread=12 top=6d84cd49-…
PASS reload burst: 2 reloads for 5 items, gaps 5146 ms, last timeline top=6d84cd49-…
PASS reload quiet: no widget.reload within 6 s of a sync round with new=0
criteria failed: 2
```

`read` chạy lại, 15:59–16:09 (D19 "B": đã bấm một lần, mục mờ đi):

```text
log: widget.intent action=read id=27996207-… -> widget.inbox_drained count=1 after 214 ms
PASS read widget tap -> inbox drained -> server item.read seq 478 for 27996207-…
```

`delete` chạy lại, 16:25–16:28 (D21 "A": bấm thùng rác trên widget, mục biến khỏi hai widget và danh sách):

```text
log: widget.intent action=delete id=05652ed7-… -> widget.inbox_drained count=1 after 218 ms
PASS delete widget tap -> inbox drained -> server item.deleted seq 484 for 05652ed7-…
```

Chuỗi log của lần bấm đã đọc (16:08), từ extension tới server:

```text
16:08:14.677 OSWidgetWidget widget.intent action=read id=27996207-…
16:08:14.714 OSWidgetWidget widget.timeline family=medium items=1 unread=0 top=27996207-…
16:08:14.891 OSWidget       widget.inbox_drained count=1
16:08:14.899 OSWidget       widget.reload n_today=19 reason=changed gap_ms=520165
16:08:15.629 OSWidget       sync.queue_sent id=27996207-… status=204
16:08:20.055 OSWidget       widget.reload n_today=20 reason=trailing gap_ms=5156
```

`offline`, lượt đầu 17:02–17:12: `FAIL offline: the server stayed reachable for 10 minutes` (operator chưa làm bước này; mục thử đã xoá). Lượt hai 17:15–17:16 (D26 "A": sẵn sàng), mạng tắt khoảng 20 s:

```text
offline since 2026-11-24 17:16:01
log: widget.intent action=read id=d8a20c75-… -> widget.inbox_drained count=1
queue_sent before the network came back: none
online again at 2026-11-24 17:16:19
PASS offline tap drained while offline, read_at 2026-11-24T10:16:17.846+00:00 on the server after reconnect (sync.queue_sent id=d8a20c75-… status=204)
```

```text
17:15:57.123 OSWidget       realtime.state send_failed
17:16:02.606 OSWidgetWidget widget.intent action=read id=d8a20c75-…
17:16:02.643 OSWidgetWidget widget.timeline family=large items=1 unread=0 top=d8a20c75-…
17:16:02.646 OSWidget       sync.retry in=2s reason=network
17:16:02.822 OSWidget       widget.inbox_drained count=1
17:16:07.009 OSWidget       sync.retry in=8s reason=network
17:16:15.569 OSWidget       sync.retry in=16s reason=network
17:16:17.685 OSWidget       sync.start
17:16:18.118 OSWidget       sync.queue_sent id=d8a20c75-… status=204
```

## Checklist của operator

| # | Mục | Kết quả |
|---|---|---|
| 1 | Cỡ vừa 3 mục, cỡ lớn 6 mục, mới nhất trên cùng, số chưa đọc khớp dấu báo | Đạt. D22 "A"; log: `family=medium items=3`, `family=large items=6`, `unread=7` với 7 mục |
| 2 | `notification`, `generic`, `vocab` hiện gọn, không tràn | Đạt. D22 "A", cỡ vừa không tràn; không cần đặt `WidgetSize.medium.leadRowLines = 1` |
| 3 | Mục đã đọc làm mờ, không còn dấu tích | Đạt. D22 "A", D23 "A". Operator bấm trên hàng `vocab` thay cho hàng `note`; log 16:32:05.237 `widget.intent action=read` → timeline `unread` 7→6 sau 29 ms → rút hộp thư 221 ms → server `read_at` |
| 4 | Bấm khi app đã thoát: widget cập nhật ngay; mở lại app thì thao tác được gửi | Đạt. App thoát khoảng 16:32:12; 16:32:14.721 `widget.intent action=read` (hàng `generic`) → timeline `unread` 6→5 sau 30 ms, app không chạy. Operator chưa mở lại app nên session này mở lúc 16:40:41: `widget.inbox_drained count=1` ngay khi khởi động, `sync.queue_sent … status=204`, server `item.read` seq 493 |
| 5 | Bấm thân mục không làm gì | Đạt. D22 "A" |
| 6 | Sáng và tối đều đọc được | Đạt. D22 "A" |
| 7 | Sau một đêm ngủ máy | chờ: đêm 26–27/11, thẻ vocab từ cron |
| 8 | Popup và danh sách M2 vẫn chạy | Đạt. `acceptance-menu-bar.sh 1`: `PASS 1 … latency_ms=637`; `6`: `PASS 6 vocab item … shown with title and summary`. D24 "A + title and summary must show". Câu trả lời mục 6 tới trước khi script publish mục `vocab m2-…164848`, nên operator thực ra nhìn thẻ `vocab m3-…162821` của checklist (cùng tóm tắt); hai mục cùng đường hiển thị |

## Phát hiện

1. **Lần đầu `read` và `delete` trượt vì không có lần bấm nào tới nút trên widget, không phải lỗi mã.** 15:36–15:56 không có dòng `widget.intent`, `widget.intent_failed`, hay hoạt động AppIntents nào của extension. Lượt `delete` thứ hai (16:10) operator thao tác trong danh sách của app: app tự đánh dấu đã đọc (16:10:11) rồi tự xoá (16:10:39) và gửi qua hàng đợi, không có `widget.intent` hay `widget.inbox_drained`. Sau khi dặn rõ "bấm trên widget ở desktop, đóng danh sách", cả `read` và `delete` đều PASS. Điều kiện "Stop and ask" của plan (nút không chạy intent trong extension) không xảy ra.
2. **Mỗi lần bấm nút trên widget gây khoảng 2 reload**: `changed` sau khi rút hộp thư và `trailing` khoảng 5 s sau, khi sync áp lại trạng thái từ server. Cần tính khi so ngưỡng 40 lần mỗi ngày (ghi trong [reload-day.md](./reload-day.md)). Không sửa mã trong session này.
3. **Bộ đếm `n_today` về 1 khi app chạy lại** (16:40:42), và cả sau nửa đêm theo giờ máy (`WidgetReloadPolicy` đếm theo ngày; ví dụ 2026-11-27 00:07:31 `n_today=1`). Script đếm không dùng nó.
4. **Bản build trong derived data được đăng ký như widget thứ hai** cùng bundle id. Đã gỡ trước khi operator thêm widget. Ai build Release có ký trên máy này cần gỡ bản trong derived data (hoặc xoá nó) để gallery không có hai widget "OS Widget".
5. **`swift test` ghi log cùng subsystem và category** (`swiftpm-testing-helper`), nên mọi truy vấn log đếm phải lọc theo tiến trình `OSWidget`/`OSWidgetWidget`. Script nghiệm thu và `log stream` đã lọc.
6. Sửa script trong lúc chạy: mục hiện trên widget (`read`, `delete`) không được ghi để xoá khi thoát vì hàm chạy trong subshell; hai mục sót của lượt `all` đã xoá tay (204), script đã sửa. Thời gian chờ lần bấm đặt được bằng `TAP_WAIT_SECONDS`.
7. Hai thư mục tạm có từ trước session này còn trong `$TMPDIR`: `tmp.zgy5yrxwfk` (08:46, có file `client`, có thể là file header token của một lần chạy script nghiệm thu khác) và `tmp.5oWc62RIeA` (14:37). Không phải của session này nên không xoá; nên kiểm và xoá.

## Còn lại

- Checklist mục 7: chờ: đêm 26–27/11, thẻ vocab từ cron. Đêm 24–25/11 không có mục nào được publish (mọi `sync.applied` sau 17:17 có `new=0`), nên file log của đêm đó không chứng minh được mục này. Nguồn đánh giá là `~/Library/Logs/os-widget/widget-day-20261124.ndjson`, vẫn do `log stream` PID 6328 ghi; chưa được dừng.
- Kết luận D9 và việc có tính lại ngưỡng hay không: chờ quyết định của operator (xem [reload-day.md](./reload-day.md)).
- Trạng thái Phase 6 và plan chưa đổi; session review sau đêm 26–27/11 đánh giá mục 7 rồi merge.
