# Báo cáo nghiệm thu Giai đoạn 4: thẻ từ vựng (Phase 10)

Session `m4-vocab-p10`, ngày 2026-11-27 từ 21:51 (Asia/Saigon), trên MacBook. Câu hỏi cho operator đi qua session giám sát `supervisor-project`; mã quyết định (D31 đến D34, …) nằm trong ledger của supervisor. Phần server (tiêu chí 2 đến 5 của roadmap, CPU) ở [acceptance-server.md](./acceptance-server.md).

**Đạt, có một giới hạn.** Thẻ `vocab` hiện đủ trường ở popup và danh sách. Nút phát âm phát `audio_url` và đọc bằng bộ đọc hệ thống khi không có `audio_url`. Widget hiện bố cục rút gọn ở cỡ vừa và cỡ lớn. Giới hạn: log không có lần bấm nút nào trên chính popup (mọi lần bấm ở danh sách, cùng view), và thẻ do cron gửi không được kiểm bằng tay (D35). URL audio của dictionaryapi.dev hiện trả 403, nên thẻ cron phát âm qua đường dự phòng (Phát hiện 1).

## Tóm tắt

| Kiểm | Kết quả |
|---|---|
| Cài lại từ `main` `5fe3c0a` (cần vì Phase 9) | Đạt, 2026-11-27 21:53:57; một widget đăng ký; WidgetProbe không đổi |
| `acceptance-menu-bar.sh 1` | PASS, `latency_ms=549` |
| PRD §10.5: popup và danh sách hiện đủ trường | Đạt (D32) |
| PRD §10.5: phát `audio_url`, mục vẫn chưa đọc | Đạt, 4 lần `source=audio`, `read_at` rỗng; bấm trong danh sách |
| PRD §10.5: không có `audio_url` thì đọc bằng hệ thống | Đạt (D34), `source=speech`; bấm trong danh sách |
| Widget rút gọn cỡ vừa và cỡ lớn | Đạt (D33) |
| Thẻ thử | 2 thẻ publish, 2 lần xoá 204 |

## Môi trường và cài đặt

- macOS 27.2.1 (26B131), Xcode 27.2 (27B52), xcodegen 2.48.0.
- **Cài lại là cần thiết.** Bản trong `/Applications` build từ `641deb2` (cài 2026-11-24 15:02:17). `git log 641deb2..main -- apps/` có hai commit của Phase 9: `b7567e0` (bố cục rút gọn `vocab` ở widget) và `790623d` (giữ từ đọc được khi phiên âm dài). Bản cũ vì vậy hiện `vocab` ở widget bằng bố cục dự phòng.
- Mã: `main` tại `5fe3c0a`. Lấy `apps/macos` bằng `git archive` vào scratchpad ngoài repo, `xcodegen generate`, rồi `xcodebuild -scheme OSWidget -configuration Release -allowProvisioningUpdates` với derived data trong scratchpad. Thoát app cũ bằng Apple Event `quit`, xoá `/Applications/OSWidget.app`, `ditto` bản mới vào, `open`.
- **Cài lúc 2026-11-27 21:53:57 (+0700).** Đồng hồ 7 ngày của riêng OSWidget tính lại từ mốc này. Kết luận thử nghiệm A vẫn lấy từ WidgetProbe (D10).
- Chữ ký: Apple Development `longdaobk17@gmail.com (N5MCHDCD2R)`, Team `22LZWPB3XL`, `Signed Time` 2026-11-27 21:53:47, `CDHash=4553dfa3…`. `codesign --verify --deep --strict` đạt. Số identity ký trước và sau build đều là 1.
- Widget thừa: gỡ bản trong derived data (`pluginkit -r`, `lsregister -u`, xoá thư mục build). `pluginkit -m -i local.oswidget.app.widget` trả đúng một plug-in, `/Applications/OSWidget.app/Contents/PlugIns/OSWidgetWidget.appex`.
- App chạy lại: `widget.reload n_today=1 reason=first` 21:53:58.351, `realtime.state joined` 21:53:59.008, `sync.applied seq=638..657 new=0` 21:53:59.113.
- WidgetProbe không bị đụng: mtime bundle `1795358837`, `Identifier=local.oswidget.probe`, `CDHash=7baa39edf5a1a594082f8f9aff02f6028125501d`, SHA-256 đầu ra `codesign -dvvv` bắt đầu bằng `c5eda6f5`, giống trước khi build và giống báo cáo widget.
- Operator xác nhận widget cỡ vừa và cỡ lớn vẫn trên desktop sau khi cài (D31).
- Bằng chứng log: `log stream --info --debug` lọc subsystem `local.oswidget.app` và tiến trình `OSWidget*`, ghi ra scratchpad ngoài repo (từ 21:57 đến khi kết thúc), vì `log show` không giữ dòng `info`.

## Thẻ thử publish tay

Hai envelope `vocab` nằm ngoài repo, `source` `acceptance-m4`, `dedupe_key` bắt đầu bằng `acceptance-m4-`, `priority` `normal`, `ttl` 7200, publish bằng `os-widget publish --file` với token publish từ Keychain. (`origin` là cột của `vocab_words`, không phải trường của envelope, nên thẻ publish tay không có `origin`.)

| Thẻ | id | Trường | Publish | Xoá |
|---|---|---|---|---|
| `ubiquitous` | `78cd245d-ebc9-48a8-895f-bf5e3de7478a` | Đủ mọi trường: `ipa`, `pos` `adjective`, 2 nghĩa mỗi nghĩa 1 ví dụ, `context`, 3 đồng nghĩa, 2 trái nghĩa, `audio_url` (mp3 HTTPS trên `ssl.gstatic.com`) | 21:59:11 | 22:05:11, 204 |
| `meander` | `ef7592b8-69cb-410a-9016-956760aba8a9` | Không có `audio_url` và `context`; 1 nghĩa, 1 đồng nghĩa, 1 trái nghĩa | 22:02:57 | 22:05:11, 204 |

Sau khi xoá, `GET /items` không còn mục nào có `source` bắt đầu bằng `acceptance`.

`audio_url` của thẻ đủ trường không lấy từ dictionaryapi.dev, vì URL audio của API này hiện không tải được (xem Phát hiện 1).

## PRD §10.5

| Gạch đầu dòng | Kết quả | Bằng chứng |
|---|---|---|
| Popup hiện đủ trường FR-15 | Đạt (D32). Operator thấy đủ: từ, phiên âm, từ loại, 2 nghĩa đánh số kèm ví dụ, ngữ cảnh, "Đồng nghĩa", "Trái nghĩa", nút loa. | `sync.applied seq=638..658 new=1` 21:59:14.954, `popup.shown id=78cd245d-… latency_ms=2293` 21:59:15.033, `popup.closed reason=timeout` 21:59:46.890 |
| Bấm nút phát `audio_url`, mục vẫn chưa đọc | Đạt (D32, operator nghe tiếng đọc). Cả 4 lần bấm đều trong danh sách, không trên popup (xem dưới). | `list.shown` 22:00:33.255; `pronounce.play source=audio` 22:00:34.794, 22:00:36.851, 22:00:38.141, 22:00:42.034; không có `pronounce.fallback`; `GET /items` cho `78cd245d-…` `read_at: null` |
| Danh sách: thẻ giống popup, bấm cũng phát | Đạt (D32). | Như dòng trên |
| Thẻ không có `audio_url` đọc bằng bộ đọc hệ thống | Đạt (D34, operator nghe giọng hệ thống đọc "meander"). | `popup.shown id=ef7592b8-… latency_ms=1120` 22:03:01.214; `popup.closed reason=timeout` 22:03:31.217; `list.shown` 22:04:42.919; `pronounce.play source=speech` 22:04:44.023 |
| Một mục `vocab` thật do cron gửi | Không kiểm bằng tay. Theo quyết định của operator (D35, "B"), phase đóng mà không đợi thẻ cron lúc 22:40. Thẻ cron có cùng dạng `body` và đi cùng đường hiển thị; thẻ cron `comes` (`0a00e8ea-…`, có `context`) nằm đầu widget sau khi xoá thẻ thử. Thẻ cron có `audio_url` của dictionaryapi.dev sẽ đọc bằng bộ đọc hệ thống (Phát hiện 1). | `widget.timeline … top=0a00e8ea-…` 22:05:10.885 |

**Không có lần bấm nào trên chính popup trong log.** Operator trả lời "nghe trên popup" cho thẻ `meander` (D34). Nhưng log cho thấy cả hai popup đều đóng vì hết 30 giây (`popup.closed reason=timeout` lúc 21:59:46 và 22:03:31) trước lần bấm đầu tiên. Nút loa được bấm trong danh sách: `source=audio` lúc 22:00:34–22:00:42 và `source=speech` lúc 22:04:44, đều nằm giữa `list.shown` và `list.closed`. Popup và danh sách dùng cùng một view `VocabCardView` với cùng nút, và operator xác nhận nút có trên popup (D32). Operator quyết định đóng phase mà không bấm thêm trên popup (D35, "B").

## Widget (Phase 9): bố cục rút gọn

| Cỡ | Kết quả (D33) | Log |
|---|---|---|
| Vừa | Hàng `ubiquitous` hiện từ, phiên âm, từ loại và nghĩa đầu; đọc được. | `widget.timeline family=medium items=3 top=78cd245d-…` 21:59:15.010, 56 ms sau `sync.applied` |
| Lớn | Thêm các dòng chi tiết (ví dụ, đồng nghĩa, ngữ cảnh); đọc được. | `widget.timeline family=large items=6 top=78cd245d-…` 21:59:15.122 |
| Nút loa | Không có trên widget, đúng thiết kế. | |

Thẻ `meander` cũng lên đầu hai widget (`widget.timeline` medium 22:03:01.244, large 22:03:01.355). Sau khi xoá hai thẻ thử, đầu widget trở lại thẻ cron thật `comes` (`top=0a00e8ea-…` 22:05:10.885).

## `scripts/acceptance-menu-bar.sh`

Chạy `scripts/acceptance-menu-bar.sh 1` lúc 22:05:49 với token từ Keychain trong môi trường của lệnh, qua một wrapper pty ngoài repo (script đọc câu trả lời y/n từ `/dev/tty`). Câu trả lời "y" là câu operator trả lời qua supervisor (D36: thấy popup).

```text
run m2-20261127T220549-99386 against https://os-widget.longdaobk17.workers.dev
== 1. Popup within 5 seconds
published 4bc8cc48-6c3c-4df3-b98e-40a09dd1e4a1; waiting for popup.shown
log:  id=4bc8cc48-6c3c-4df3-b98e-40a09dd1e4a1 others=0 latency_ms=549
PASS 1 popup shown for 4bc8cc48-6c3c-4df3-b98e-40a09dd1e4a1, latency_ms=549 (<= 5000)
criteria failed: 0
cleanup: DELETE /items/4bc8cc48-6c3c-4df3-b98e-40a09dd1e4a1 -> 204
```

Không chạy tiêu chí `6` của script. Tiêu chí đó dùng `vocab` làm ví dụ cho `kind` app chưa có view, và hỏi thẻ có hiện `title` và `summary` không. Từ Phase 8, `vocab` có view riêng hiện `word` và các trường của `body`, không hiện `summary`, nên câu hỏi đó không còn đúng với `vocab`. PRD §10.5 ở trên thay cho nó với `vocab`; `kind` lạ thật vẫn được unit test của `OSWidgetKit` phủ. Sửa script để dùng một `kind` lạ khác là việc ngoài phạm vi phase này (không sửa script).

## Phát hiện

1. **URL audio của Free Dictionary API hiện không tải được.** `https://api.dictionaryapi.dev/media/pronunciations/en/<word>-us.mp3` trả 403 (trang HTML) với `curl`, và 404 khi đổi User-Agent; `AVPlayerItem` báo lỗi `-1100` cho `comes-1-us.mp3` và `beauty-us.mp3` (thử bằng một chương trình nhỏ ngoài repo, âm lượng 0). Cùng chương trình đó tải được mp3 trên `ssl.gstatic.com`. Vì vậy mọi thẻ cron có `audio_url` của dictionaryapi.dev sẽ đi đường dự phòng: `pronounce.fallback reason=load` rồi bộ đọc hệ thống. App làm đúng thiết kế (architecture §6), nên đây không phải lỗi mã. Đường `source=audio` được chứng minh bằng thẻ publish tay. Nếu muốn phát file thật: kiểm lại sau xem API có mở lại không, hoặc để ingest bỏ `audio_url` không tải được. Việc này ngoài phạm vi phase này.
2. **Popup đóng sau 30 giây trong lúc chờ câu hỏi đi qua supervisor**, nên lần bấm trên popup khó bắt đúng lúc. Câu hỏi cho bước cần bấm trên popup nên gửi trước, rồi mới publish.

## Kiểm cuối

- `cargo test --workspace`: 197 pass. `cd apps/macos/OSWidgetKit && swift test`: 188 test trong 19 suite pass. Chạy trên `main` tại `5fe3c0a` (Phase 10 không sửa mã).
- Không đổi `settings` live. Không xoá mục nào ngoài hai thẻ thử của session này và mục của script (script tự xoá).
- Tiến trình do session này bật (`log stream`, wrapper của script) đã dừng khi kết thúc.
