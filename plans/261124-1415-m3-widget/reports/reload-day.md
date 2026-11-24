# Đếm reload một ngày dùng thật (đang chạy)

Bản ghi mở đầu do session `m3-widget-p06-run` viết lúc bắt đầu đếm. Session kết thúc Phase 6 điền kết quả sau 24 giờ.

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
- Session kết thúc: `scripts/acceptance-widget.sh day --input ~/Library/Logs/os-widget/widget-day-20261124.ndjson` sau khi cắt file về đúng cửa sổ 24 giờ (dòng có `timestamp` trong [15:28:48, 15:28:48 ngày sau)), rồi `kill 6328`.

## Lưu ý khi đọc số

- **Cửa sổ có cả các lần chạy nghiệm thu chiều 24/11** (15:29–17:xx): kiểm `2` (5 mục), `reload` (5 mục trong 3 s), `read`, `delete`, checklist (7 mục), `acceptance-menu-bar.sh 1` và `6`, `offline`, cùng các lần xoá dọn dẹp. Mỗi mục publish và mỗi lần xoá dọn dẹp đổi snapshot nên gây reload. Lúc 16:32 đã có `n_today=32`. Khi đánh giá ngưỡng 40, tách phần nghiệm thu (đến hết lượt offline) khỏi phần dùng thật; ghi cả hai số.
- **Mỗi lần bấm nút trên widget gây khoảng 2 reload**: một `changed` ngay sau khi app rút hộp thư, một `trailing` khoảng 5 s sau khi vòng sync áp lại trạng thái từ server (ví dụ 16:08:14.899 và 16:08:20.055; 16:32:05.478 và 16:32:10.519). `acceptance-widget.sh day` in số lần bấm (`button taps`) trong cửa sổ; tính ngưỡng với khoảng 2 reload mỗi lần bấm.
- **Bộ đếm `n_today` về 1 khi app chạy lại** (app được mở lại lúc 16:40:41 cho checklist mục 4: `widget.reload n_today=1 reason=first`). Script đếm không dùng `n_today` nên không ảnh hưởng; chỉ đừng đọc `n_today` như tổng của ngày.
- `widget-reload-count.sh` in PASS khi cửa sổ không có yêu cầu nào; `acceptance-widget.sh day` thêm điều kiện `requests > 0`.
- Máy ngủ qua đêm là đúng ý (dùng thật); yêu cầu không có timeline trong 5 s vì máy ngủ ngay sau đó cần liệt kê riêng.

## Kết quả

Chờ session kết thúc (sau 2026-11-25 15:28:48): đầu ra `acceptance-widget.sh day`, phân bố theo giờ, so với ngưỡng D9 (≤ 40 yêu cầu, không hai yêu cầu cách nhau dưới 5 s, ≥ 95% có timeline trong 5 s), nhận xét về ngân sách nền, và checklist mục 7 (một đêm ngủ máy).
