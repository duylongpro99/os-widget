# Đếm reload một ngày dùng thật

Bản ghi mở đầu do session `m3-widget-p06-run` viết lúc bắt đầu đếm. Phần "Kết quả" do session `m3-widget-p06-finish` điền ngày 2026-11-26 từ file log đã cắt về đúng cửa sổ 24 giờ. Phần "Đếm lại nửa ngày dùng thật" và "Mục 7 của checklist" do session `m3-widget-p06-review` điền ngày 2026-11-27 sau khi operator quyết cách tính lại (D29, D30). **Kết luận cuối: đạt** (đếm lại 12 yêu cầu trên ngưỡng 20, mục 7 đạt).

## Mốc và nguồn log

- Bắt đầu đếm: **2026-11-24 15:28:48 (+0700)**, dòng `widget.timeline` đầu tiên sau khi operator thêm widget cỡ vừa và cỡ lớn lên desktop. Kết thúc dự kiến: **2026-11-25 15:28:48**.
- App cài lúc 2026-11-24 15:02:17 (commit `641deb2`), xem [acceptance.md](./acceptance.md).
- Nguồn chính: `log stream` chạy nền, ghi ra `~/Library/Logs/os-widget/widget-day-20261124.ndjson` (ngoài repo), lỗi ở `~/Library/Logs/os-widget/widget-day-20261124.err`. **PID 6328**, khởi động 15:03:39 bằng `nohup` (không gắn với session nào). Lệnh:

  ```text
  /usr/bin/log stream --style ndjson --level info --predicate 'subsystem == "local.oswidget.app"
    AND (category == "widget" OR category == "sync") AND process BEGINSWITH "OSWidget"'
  ```

  Khác predicate trong brief ở hai chỗ, đều có lý do: thêm `category == "sync"` để file có cả `sync.start` và `sync.applied` (cần cho điều kiện "reload chỉ khi nội dung đổi" trong log ngày thật; `widget-reload-count.sh` tự lọc `category == "widget"`), và thêm `process BEGINSWITH "OSWidget"` vì `swift test` của các session song song ghi cùng subsystem và category (`swiftpm-testing-helper` ghi `widget.inbox_corrupt` và các dòng khác).
- `log show` không đủ cho 24 giờ: dòng mức `info` (như `sync.applied`) không được lưu, và kho log có khoảng trống khi máy ngủ (không có dòng nào lúc 03:00 và 06:00 ngày 24/11). Dòng `notice` của `widget.reload` và `widget.timeline` có trong `log show` khi máy thức. Dùng file `log stream` làm nguồn kết luận.
- Session kết thúc: `scripts/acceptance-widget.sh day --input ~/Library/Logs/os-widget/widget-day-20261124.ndjson` sau khi cắt file về đúng cửa sổ 24 giờ (dòng có `timestamp` trong [15:28:48, 15:28:48 ngày sau)), rồi `kill 6328`. Thực tế: lần đếm đầu cắt file ngày 2026-11-26; PID 6328 chạy tiếp tới sau cửa sổ đếm lại và đêm 26–27/11, dừng lúc 2026-11-27 21:11 (`ps -p 6328` rỗng). File `.ndjson` được giữ.

## Lưu ý khi đọc số

- **Cửa sổ có cả các lần chạy nghiệm thu chiều 24/11** (15:29–17:xx): kiểm `2` (5 mục), `reload` (5 mục trong 3 s), `read`, `delete`, checklist (7 mục), `acceptance-menu-bar.sh 1` và `6`, `offline`, cùng các lần xoá dọn dẹp. Mỗi mục publish và mỗi lần xoá dọn dẹp đổi snapshot nên gây reload. Lúc 16:32 đã có `n_today=32`. Khi đánh giá ngưỡng 40, tách phần nghiệm thu (đến hết lượt offline) khỏi phần dùng thật; ghi cả hai số.
- **Khung giờ có mục thử của nghiệm thu** (mọi mục `ttl 3600`, xoá khi kết thúc lượt): 15:29–15:58 (`all`, kể cả 5 mục burst), 15:59–16:09 (`read`), 16:10–16:28 (`delete` hai lượt), 16:28–16:41 (checklist, 7 mục), 16:41–16:49 (`acceptance-menu-bar.sh 1`, `6`), 17:02–17:12 và 17:15–17:17 (`offline`). Phần dùng thật nên tính từ 17:17 trở đi. Tới 17:17 file đã có 45 dòng `widget.reload` kể từ mốc bắt đầu, gần như toàn bộ do nghiệm thu.
- **Số lần bấm nút trên widget trong phần nghiệm thu: 5** (`widget.intent` lúc 16:08:14 read, 16:27:41 delete, 16:32:05 read, 16:32:14 read khi app tắt, 17:16:02 read khi offline). Lần bấm sau đó là dùng thật; `acceptance-widget.sh day` in tổng `button taps` của cả cửa sổ.
- **Mỗi lần bấm nút trên widget gây khoảng 2 reload**: một `changed` ngay sau khi app rút hộp thư, một `trailing` khoảng 5 s sau khi vòng sync áp lại trạng thái từ server (ví dụ 16:08:14.899 và 16:08:20.055; 16:32:05.478 và 16:32:10.519). `acceptance-widget.sh day` in số lần bấm (`button taps`) trong cửa sổ; tính ngưỡng với khoảng 2 reload mỗi lần bấm.
- **Bộ đếm `n_today` về 1 khi app chạy lại và sau nửa đêm theo giờ máy** (`WidgetReloadPolicy` đếm theo ngày; ví dụ 2026-11-27 00:07:31 `n_today=1`; app được mở lại lúc 16:40:41 cho checklist mục 4: `widget.reload n_today=1 reason=first`). Script đếm không dùng `n_today` nên không ảnh hưởng; chỉ đừng đọc `n_today` như tổng của ngày.
- `widget-reload-count.sh` in PASS khi cửa sổ không có yêu cầu nào; `acceptance-widget.sh day` thêm điều kiện `requests > 0`.
- Máy ngủ qua đêm là đúng ý (dùng thật); yêu cầu không có timeline trong 5 s vì máy ngủ ngay sau đó cần liệt kê riêng.

## Kết quả lần đếm đầu (24 giờ)

**Kết luận D9: FAIL trên cửa sổ đầy đủ, chỉ vì phần nghiệm thu.** 45 yêu cầu reload, vượt ngưỡng 40. Cả 45 nằm trong phần nghiệm thu (15:28:48 đến 17:20); phần dùng thật sau đó có 0 yêu cầu. Hai điều kiện còn lại đạt: khoảng cách nhỏ nhất giữa hai yêu cầu là 5006 ms (không cặp nào dưới 5 s) và 100% yêu cầu có timeline trong 5 s. Kết luận này giữ nguyên làm lần đếm đầu. Operator quyết đếm lại trên một cửa sổ dùng thật khoảng nửa ngày không có lượt nghiệm thu (D29) với ngưỡng 20 (D30); kết quả ở phần "Đếm lại nửa ngày dùng thật".

### Cách đếm

- Nguồn: `~/Library/Logs/os-widget/widget-day-20261124.ndjson` (PID 6328, lúc đó còn chạy vì mục 7 cần nó). Cắt bằng `jq` theo `timestamp` về [2026-11-24 15:28:48, 2026-11-25 15:28:48) (+0700) vào một file ngoài repo: 920 dòng, từ 15:28:48.727 ngày 24/11 đến 15:26:19.374 ngày 25/11 (dòng "Filtering the log data…" ở đầu file không phải JSON nên bị bỏ).
- Lệnh: `scripts/acceptance-widget.sh day --input <file đã cắt>`. Script chạy qua `bash -n` và `shellcheck` không báo gì; không sửa script.
- Phần nghiệm thu tính đến hết lượt `offline` (dòng `widget.reload` cuối của phần này lúc 17:16:30; từ đó tới hết cửa sổ không có dòng `widget.reload`, `widget.timeline` hay `widget.intent` nào). Chọn mốc 17:20 hay 17:17 đều cho cùng số.

### Đầu ra `acceptance-widget.sh day`

```text
requests=45 (first=1 changed=31 trailing=13)
per hour: 15:17 16:22 17:6
timelines=109, min_gap_ms=5006
delay to next timeline: p50=39 p95=103 max=122 ms; without timeline in 5 s: 0 of 45
requests=45 min_gap_ms=5006 within_5s=100 timelines=109 verdict=FAIL
button taps in the window: 5
FAIL day requests=45 min_gap_ms=5006 within_5s=100 timelines=109 verdict=FAIL
```

Dòng `per hour` của script chỉ ghi giờ trong ngày, không ghi ngày; ở đây mọi yêu cầu đều của 24/11 nên không lẫn.

### Hai số

| | Yêu cầu reload | Lần bấm nút | Cặp cách nhau dưới 5 s | Timeline trong 5 s |
|---|---|---|---|---|
| Cả cửa sổ (D9) | 45 (ngưỡng 40) | 5 | 0 (nhỏ nhất 5006 ms) | 45 trên 45 (100%, ngưỡng 95%) |
| Phần nghiệm thu, 15:28:48 đến 17:20 | 45 | 5 | 0 | 45 trên 45 |
| Dùng thật, sau 17:20 đến 15:28:48 ngày 25/11 | 0 | 0 | 0 | không có yêu cầu để tính |

Phần nghiệm thu là 100% số vượt ngưỡng: 45 yêu cầu gồm 31 `changed`, 13 `trailing` và 1 `first`. Trong đó 5 lần bấm nút cho khoảng 10 reload (mỗi lần bấm một `changed` và một `trailing`, xem phần ghi chú đầu báo cáo); phần còn lại là mục thử publish và xoá dọn dẹp của `acceptance-widget.sh`, `acceptance-menu-bar.sh` và `acceptance-server.sh` (các mục thử của `acceptance-server.sh` lúc 15:34:05–15:34:20).

Phân bố theo giờ (yêu cầu reload, +0700, ngày 24/11): 15h 17, 16h 22, 17h 6; mọi giờ từ 18h ngày 24/11 tới 15h ngày 25/11 là 0. Timeline theo giờ: 15h 41, 16h 54, 17h 14, sau đó 0.

### Dùng thật: widget không có gì để làm mới

Sau 17:20 không có mục nào mới (mọi dòng `sync.applied` có `new=0`; 273 trong 300 dòng `sync.applied` của cửa sổ), nên không có lần reload nào và cũng không có timeline nào. Điều này khớp với điều kiện "chỉ reload khi nội dung đổi" (không có reload thừa qua 22 giờ gồm 227 vòng sync không đổi gì), nhưng không phải là phép đo một ngày dùng thật: ngày đó không có thẻ nào tới và không ai bấm nút. Số 0 chứng minh ngân sách không bị tiêu khi không có gì đổi; nó không cho biết ngày có tải thật (vài chục mục, vài lần bấm) tốn bao nhiêu. Ước lượng theo phần nghiệm thu: mỗi mục mới cho 1 reload (hoặc 2 nếu tới trong 5 s sau một reload, một `changed` rồi một `trailing`) và mỗi lần bấm nút cho khoảng 2; với 40 reload mỗi ngày, ngưỡng cho phép khoảng 20 lần bấm cộng 0 mục mới, hoặc khoảng 40 mục mới rải đều hơn 5 s.

### Máy ngủ và khoảng trống

Log không có dòng "máy ngủ" riêng; dấu hiệu là `realtime.state stopped` (app dừng kết nối khi máy ngủ) rồi `joined` khi thức. Các đoạn ngủ thấy được trong cửa sổ: 18:41 đến 19:08, 20:17 đến 20:39, **22:47 đến 07:20 ngày 25/11 (khoảng 8 giờ 33 phút, qua đêm)**, 07:55 đến 08:41, 09:39 đến 09:43. Trong đêm vẫn có khoảng 4 vòng `sync.start` mỗi giờ (cách nhau 15 đến 18 phút, không phải 5 phút của poll), tất cả `new=0` và không kèm reload. Khoảng trống lớn nhất giữa hai dòng bất kỳ của file là dưới 20 phút. Không có yêu cầu nào bị bỏ vì máy ngủ ngay sau đó, nên không có yêu cầu thiếu timeline cần liệt kê.

### Nhận xét về ngân sách nền (câu hỏi mở của thử nghiệm B)

- Chính sách gộp hoạt động đúng: khoảng cách nhỏ nhất 5006 ms ở cả 45 yêu cầu, trễ yêu cầu tới timeline p50 39 ms, p95 103 ms, lớn nhất 122 ms; không yêu cầu nào bị hệ thống bỏ qua hay trễ quá 5 s.
- Chưa đo được ngân sách reload khi app chạy nền với tải thật vì phần dùng thật không có yêu cầu nào. Câu hỏi mở của B vẫn còn: số lần reload tối đa mà chronod cho phép cho một app agent ở nền chưa bị chạm tới.
- Đề xuất theo bảng nhánh của plan (không sửa mã): không có yêu cầu nào không được phục vụ trong 5 s và không có yêu cầu nào vượt ngưỡng ngoài phần nghiệm thu, nên không cần đổi chính sách reload. Câu hỏi về cách tính ngưỡng 40 khi nghiệm thu nằm trong cửa sổ đếm đã được operator trả lời: đếm lại khoảng nửa ngày dùng thật (D29), ngưỡng 20 (D30).

## Đếm lại nửa ngày dùng thật (D29, D30)

**Kết luận D30: PASS.** 12 yêu cầu reload trong 12 giờ (ngưỡng 20), không cặp nào cách nhau dưới 5 s (nhỏ nhất 5290 ms), 100% có timeline trong 5 s (ngưỡng 95%). 0 lần bấm nút trên widget.

Quyết định của operator, nguyên văn: D29 (2026-11-26) "A, nhưng tính khoảng nửa ngày thôi": đếm lại trên một cửa sổ dùng thật khoảng nửa ngày, không có lượt nghiệm thu. D30 (2026-11-27) "A": với cửa sổ 12 giờ, tối đa 20 yêu cầu reload; hai điều kiện còn lại giữ nguyên.

### Cửa sổ và cách đếm

- Cửa sổ do giám sát chọn: **[2026-11-27 08:56:41, 2026-11-27 20:56:41) (+0700)**. Trong cửa sổ không có lượt nghiệm thu nào và không session nào ghi vào dữ liệu thật. Cài đặt thật lúc đó: thẻ vocab mỗi 60 phút, priority normal.
- Nguồn: cùng file `~/Library/Logs/os-widget/widget-day-20261124.ndjson` (PID 6328). Cắt bằng `jq` theo `timestamp` vào một file ngoài repo: 366 dòng, từ 09:01:14.038 đến 20:48:47.849.
- Lệnh: `scripts/acceptance-widget.sh day --input <file đã cắt>`, chạy hai lần: mặc định (ngưỡng 40) và `MAX_REQUESTS=20` (script đọc ngưỡng từ biến môi trường này; mặc định 40 không đổi). Hai lần cho cùng đầu ra.

### Đầu ra `MAX_REQUESTS=20 acceptance-widget.sh day`

```text
requests=12 (first=0 changed=11 trailing=1)
per hour: 09:1 10:1 11:3 12:1 13:1 14:1 15:1 16:1 17:1 20:1
timelines=24, min_gap_ms=5290
delay to next timeline: p50=67 p95=178 max=178 ms; without timeline in 5 s: 0 of 12
requests=12 min_gap_ms=5290 within_5s=100 timelines=24 verdict=PASS
button taps in the window: 0
PASS day requests=12 min_gap_ms=5290 within_5s=100 timelines=24 verdict=PASS
```

| Điều kiện (D30) | Ngưỡng | Đo được | Kết quả |
|---|---|---|---|
| Số yêu cầu reload trong 12 giờ | ≤ 20 | 12 | Đạt |
| Cặp yêu cầu cách nhau dưới 5 s | 0 | 0 (nhỏ nhất 5290 ms) | Đạt |
| Yêu cầu có timeline trong 5 s | ≥ 95% | 12 trên 12 (100%); p50 67 ms, lớn nhất 178 ms | Đạt |

### 12 yêu cầu từ đâu

- **10 yêu cầu do thẻ mới**, mỗi vòng sync có thẻ mới đúng một reload `changed`: 9 vòng `sync.applied … new=1` (thẻ vocab mỗi giờ, 09:55:33, 10:55:33, 11:55:33, 12:55:32, 13:55:32, 14:55:32, 15:57:45 lúc thức tối, 16:55:33, 17:55:33) và một vòng `new=2` lúc 20:06:57.736 (hai thẻ 18:55 và 19:55 tới khi mạng có lại, xem dưới) với một reload lúc 20:06:57.759.
- **2 yêu cầu do một thao tác đã đọc trong app** (không qua widget, không có `widget.intent`): 11:56:09.095 `changed` (timeline `unread` 134 → 133), `sync.queue_sent id=865bc32d-… status=204` lúc 11:56:09.366, rồi 11:56:14.385 `trailing` sau 5290 ms khi vòng sync áp lại trạng thái từ server. Đúng mẫu "khoảng 2 reload mỗi thao tác đã đọc" đã thấy khi nghiệm thu.
- Phân bố theo giờ (+0700): 09h 1, 10h 1, 11h 3, 12h 1, 13h 1, 14h 1, 15h 1, 16h 1, 17h 1, 18h 0, 19h 0, 20h 1.
- Reload chỉ khi nội dung đổi: 152 dòng `sync.start`, 129 `sync.applied`, chỉ 10 có `new` khác 0; không vòng `new=0` nào kèm reload (trừ `trailing` 11:56:14 của thao tác đã đọc ở trên).

### Máy ngủ trong cửa sổ

Theo `pmset -g log` và `realtime.state`: ngủ 12:15:52 tới 12:26:51; 14:58:46 tới khoảng 16:48 (`realtime.state joined` 16:48:51); 17:56:02 (gập máy) tới 20:15:16 (mở nắp); từ 20:48:52 tới hết cửa sổ. Thẻ 15:55 tới lúc máy thức tối 15:57:45 (một reload). Từ 17:59 tới 20:06:45 các lần thức tối chỉ có `sync.retry reason=network` (không có mạng khi thức tối), nên hai thẻ 18:55 và 19:55 tới cùng lúc ở vòng 20:06:57 với một reload. Sáu khoảng hơn 15 phút không có dòng nào đều nằm trong lần ngủ 18:06 tới 19:44. Không yêu cầu nào bị bỏ vì máy ngủ ngay sau đó.

### Nhận xét

- Với tải thật lúc này (một thẻ mỗi giờ, ít thao tác), 12 giờ cần 12 reload, tức khoảng 24 trong 24 giờ, dưới ngưỡng 40 của D9.
- Hệ thống phục vụ mọi yêu cầu trong 178 ms; không thấy chronod từ chối hay trễ reload. Câu hỏi mở của thử nghiệm B (ngân sách tối đa khi app ở nền) chưa bị chạm tới ở mức tải này. Không cần đổi chính sách reload.

## Mục 7 của checklist: một đêm ngủ máy

**Kết luận: Đạt.** Đêm 2026-11-26 tới 27, trong lúc kiểm chu kỳ vocab (22:03 tới 08:56) thẻ được publish mỗi 5 phút ở priority low (priority không ảnh hưởng mục này). Máy ngủ suốt đêm; sau khi thức, vòng sync đầu áp các thẻ mới và một reload theo sau, có timeline của cả hai cỡ.

- **Ngủ:** `pmset -g log`: `Sleep … 'Idle Sleep'` lúc **2026-11-26 22:07:16**; app ghi `realtime.state stopped` lúc 22:07:11.905. Thức hẳn (mở nắp): `Wake … lid` lúc **2026-11-27 08:56:12**. Giữa hai mốc chỉ có các lần `DarkWake` khoảng 15–18 phút một lần và một lần mở nắp ngắn 07:56:22 tới 07:56:52.
- **Sau khi thức:**

  ```text
  08:56:12.384 OSWidget       sync.start
  08:56:13.801 OSWidget       sync.applied seq=619..640 new=2
  08:56:13.838 OSWidget       widget.reload n_today=36 reason=changed gap_ms=568610
  08:56:13.859 OSWidget       realtime.state joined
  08:56:13.872 OSWidgetWidget widget.timeline family=medium items=3 unread=131 top=4b554525-…
  08:56:13.989 OSWidgetWidget widget.timeline family=large items=6 unread=131 top=4b554525-…
  08:56:14.147 OSWidget       sync.applied seq=621..640 new=0
  08:56:14.548 OSWidget       sync.applied seq=621..640 new=0
  ```

  Vòng sync đầu sau khi thức áp 2 thẻ publish trong lúc máy ngủ (từ lần thức tối trước, 08:46:45), một reload sau 37 ms, timeline cỡ vừa và cỡ lớn với mục đầu mới `4b554525-…` sau 34 ms và 151 ms. Hai vòng sync tiếp theo `new=0` không kèm reload.
- **Khoảng dài nhất không có dòng nào trong đêm:** 00:07:31.762 tới 00:28:27.772 (21 phút, máy ngủ). Lần thức tối sau đó: `sync.applied seq=515..538 new=4` lúc 00:28:29.419, một `widget.reload` lúc 00:28:29.439, timeline 00:28:29.471 (cỡ vừa) và 00:28:29.590 (cỡ lớn) `top=de1a8771-…`.
- **Cả đêm** (22:07:16 tới 08:56:41, `widget-reload-count.sh` trên file cắt): 130 thẻ tới trong 43 vòng sync ở các lần thức tối, mỗi vòng đúng một reload `changed` (43, không `trailing`), khoảng cách nhỏ nhất 362647 ms, 43 trên 43 có timeline trong 5 s (p50 35 ms, lớn nhất 290 ms). Script in `verdict=FAIL` cho cửa sổ này chỉ vì 43 > 40; đêm này không phải cửa sổ đếm của D30 và tải (một thẻ mỗi 5 phút) là tải thử, không phải dùng thật. Số này cho thấy máy ngủ gộp 130 thẻ thành 43 reload.
- Giới hạn: kết luận từ log, không có mắt operator; session này không gọi server để đối chiếu `4b554525-…` là thẻ mới nhất, nhưng mục đầu của timeline đổi sang id mới ở mọi vòng có thẻ mới và `unread` tăng đúng bằng số thẻ áp.
