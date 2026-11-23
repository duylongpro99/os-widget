# Thử nghiệm B: độ trễ widget

Đo ngày 2026-11-23, 17:39–20:38 (Asia/Saigon). Viết lúc 20:40.

## Kết quả

Khi app chứa widget gọi `WidgetCenter.shared.reloadAllTimelines()` và yêu cầu được hệ thống cho phép, timeline của widget chạy xong sau 47 ms (p50), 63 ms (p90), tối đa 216 ms. Widget được vẽ lại sau 66 ms (p50), 84 ms (p90), tối đa 270 ms. Số mẫu là 69 yêu cầu được cho phép, trong tổng số 120 yêu cầu.

Hệ thống chỉ chặn (throttle) khi app gọi dồn dập. Với 50 yêu cầu trong 12,4 giây, chronod cho 1 yêu cầu qua và chặn 49. Nó vẫn chạy lại timeline khoảng mỗi 5 giây, nên trạng thái cuối luôn hiện ra. Trường hợp chậm nhất ghi nhận là một yêu cầu bị chặn: widget vẽ lại sau 3,17 giây. Khi các yêu cầu cách nhau từ 30 giây trở lên, không yêu cầu nào bị chặn (0/67 yêu cầu trong các giai đoạn a, c, d, e, không tính yêu cầu sát ngay sau đợt dồn).

**Đề xuất NFR-2:** khi app menu bar đang chạy và máy đang thức, widget hiện mục mới trong vòng **5 giây** kể từ lúc app nhận mục, trong **ít nhất 95%** trường hợp. App phải gộp các lần reload, không gọi quá một lần mỗi 5 giây. Ngưỡng này chỉ dựa trên reload khi app được coi là đang ở foreground. Ngân sách reload khi app chạy nền chưa đo được (xem mục Giới hạn), nên cần kiểm lại khi app thật đồng bộ ở chế độ nền.

## Môi trường

- macOS 27.2.1 (26B131), Darwin 27.2.0. Lúc cài app thử nghiệm A, báo cáo `a-c-results.md` ghi macOS 26.6.2. Máy đã được cập nhật sau đó, app vẫn chạy.
- App `/Applications/WidgetProbe.app` (`spikes/widget-probe`): PID 50087, chạy từ 2026-11-22 21:47:33. Widget extension PID 53067. Widget nằm trên desktop suốt buổi đo.
- Chữ ký trước và sau buổi đo giống nhau: `Identifier=local.oswidget.probe`, `Authority=Apple Development … (N5MCHDCD2R)`, `TeamIdentifier=22LZWPB3XL`, `Signed Time=22 Nov 2026 at 21:47:15`. Không build lại, ký lại, cài lại hay sửa app.
- Máy chạy pin. Màn hình không khoá trong lúc lấy mẫu (`CGSSessionScreenIsLocked` được ghi cho từng lần bấm, đều bằng 0 ở các lần thành công).
- Để tự động hoá, chủ dự án tạm cấp quyền Accessibility cho Ghostty và kéo biểu tượng "Probe" từ vùng ẩn ra vùng hiện của thanh menu.

## Phương pháp

App không có URL scheme hay AppleScript, nên mỗi mẫu được tạo bằng cách bấm mục menu có sẵn của app. Một công cụ Swift nhỏ dùng Accessibility API bấm nút "Probe" trên thanh menu (do MenuBarAgent quản lý trên macOS 27), rồi bấm mục "Ghi dữ liệu". Mục này ghi `lastWrite` vào App Group và gọi `reloadAllTimelines()`. Công cụ chỉ bấm mục menu của app này, không gõ phím hay đụng tới app khác.

Mỗi mẫu có ba mốc, đều lấy từ unified log (`/usr/bin/log show --info --debug`):

1. **Yêu cầu**: tiến trình WidgetProbe ghi `reloadAllTimelines() - reloaded all timelines`.
2. **Timeline chạy xong**: chronod ghi `[…ProbeWidget] reload: succeeded` (mức debug).
3. **Render**: NotificationCenter ghi `Evaluated inner view with result: LIVE … reasons: [timelineAdvancedOrNewArchive]` cho widget này. Đây là lúc hệ thống dựng lại giao diện widget, không phải quan sát bằng mắt.

Quyết định cho phép hay chặn lấy từ category `externalRequestTimelineReloadFilter` của chronod, dòng nằm trong 50 ms trước yêu cầu. Nếu yêu cầu kế tiếp tới trước khi timeline chạy, yêu cầu trước được tính là đã bị gộp (ô "—" trong bảng).

Các giai đoạn:

| Giai đoạn | Cách bấm | Thời gian | Số yêu cầu |
|---|---|---|---|
| thu | Kiểm tra Probe đã hiện chưa | 17:39–17:41 | 2 |
| a-30s | 25 lần, cách 30 giây | 17:41–17:53 | 25 |
| b-burst | 50 lần liên tiếp, không nghỉ | 17:53:25–17:53:37 | 50 |
| c-1min | 30 lần, cách 60 giây (3 lần hỏng do máy ngủ) | 17:53–18:53 | 27 |
| d-5min | 12 lần, cách 5 phút | 18:58–19:57 | 12 |
| e-10min | Cách 10 phút tới giờ dừng | 20:07–20:37 | 4 |

Khoảng spacing 15 phút được rút xuống 10 phút để kết thúc trước 20:45 theo yêu cầu của chủ dự án.

Hai mẫu cũ trong log, có trước buổi đo, khớp với kết quả: 2026-11-22 21:52:14.075 (timeline 37 ms, render 51 ms) và 2026-11-23 08:51:53.353 (timeline 56 ms). Hai mẫu này không nằm trong thống kê.

### Khoảng máy ngủ

Các khoảng này bị loại khỏi mọi số liệu về tần suất và throttle:

- **18:04:57–18:38:41, máy ngủ (gập nắp)** (Clamshell Sleep). Ba lần bấm của c-1min lúc 18:10:36, 18:22:40 và 18:29:35 thất bại vì màn hình khoá, nên không tạo yêu cầu. Bấm chạy lại bình thường từ 18:39:18.
- **19:27:34–19:31:30, máy ngủ (để lâu không dùng)** (Idle Sleep, đánh thức bằng trackpad). Mất một lần bấm của d-5min: hai lần bấm liền nhau là 19:23:34 và 19:32:28. Sau đó `caffeinate -di` giữ máy thức tới hết buổi đo.

## Thống kê

Phân vị tính theo nearest-rank, đơn vị ms.

| Nhóm | Yêu cầu | Cho phép | Bị chặn | Lần chạy timeline | Timeline p50 / p90 / max | Render p50 / p90 / max |
|---|---|---|---|---|---|---|
| thu | 2 | 2 | 0 | 2 | 68 / 216 / 216 | 99 / 270 / 270 |
| a-30s | 25 | 25 | 0 | 24 | 51 / 63 / 63 | 72 / 84 / 90 |
| b-burst | 50 | 1 | 49 | 4 (+1 sau đợt) | 44 / 96 / 96 | 64 / 118 / 118 |
| c-1min | 27 | 26 | 1 | 27 | 44 / 53 / 3153 | 64 / 79 / 3168 |
| d-5min | 12 | 12 | 0 | 12 | 46 / 55 / 67 | 63 / 78 / 90 |
| e-10min | 4 | 4 | 0 | 4 | 46 / 50 / 50 | 62 / 69 / 69 |
| **Mọi yêu cầu được cho phép** | **69** | 69 | 0 | 69 | **47 / 63 / 216** | **66 / 84 / 270** |

Độ trễ từ lúc công cụ bấm tới lúc app gọi reload là 306 / 383 / 402 ms (p50 / p90 / max, n = 120). Phần này do tự động hoá mở menu, không thuộc độ trễ của widget, nên không cộng vào các số trên.

Trong a-30s có một yêu cầu (17:53:24) không có lần chạy timeline riêng vì yêu cầu đầu của đợt dồn tới ngay sau đó và được phục vụ chung.

## Throttle

Những gì log của chronod cho thấy:

- Mỗi lần app được đưa lên foreground (mở menu làm app thành foreground), yêu cầu đầu tiên được cho qua ngay: `Allowing first refresh while foreground`.
- Các yêu cầu tiếp theo trong cùng phiên foreground bị chặn: `Throttling additional refresh request while foreground`. Yêu cầu bị chặn không mất. chronod giữ một reload chờ và chạy lại khoảng mỗi 5 giây (`Reloading for prior requested throttled reload` lúc 17:53:30.607, 35.610, 40.613).
- Khi app rời foreground, reload đang chờ được chạy ngay: `Flushing pending reload request due to background transition` (17:53:25.129).
- Đợt dồn: 50 yêu cầu từ 17:53:25.011 tới 17:53:37.449. Timeline chạy 5 lần (25.040, 25.649, 30.639, 35.636, 40.654). Lần cuối chạy 3,2 giây sau yêu cầu cuối, nên nội dung cuối cùng vẫn hiện ra.
- Reload này được miễn ngân sách: chronod ghi `budget exempt reason: containerApp-ExemptReason`.
- Với các khoảng cách 30 giây, 1 phút, 5 phút và 10 phút, không yêu cầu nào bị chặn trong suốt khoảng 3 giờ đo, không tính thời gian máy ngủ.

## Giới hạn và những gì chưa đo

- **Chỉ đo reload khi app ở foreground.** Bấm menu làm app thành foreground, nên mọi mẫu đều được miễn ngân sách. Tài liệu của Apple nói reload khi app ở foreground không tính vào ngân sách, còn reload khi app chạy nền thì bị giới hạn bởi một ngân sách động trong 24 giờ ([Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date), [Apple Developer Forums 652946](https://developer.apple.com/forums/thread/652946), [819899](https://developer.apple.com/forums/thread/819899)). Con số 40–70 lần mỗi ngày chỉ là ước lượng không chính thức. App thật sẽ reload khi đồng bộ ở nền, nên trường hợp đó chưa được đo. Muốn đo phải sửa app thử nghiệm (thêm hẹn giờ reload ở nền), nhưng việc này không được phép vì sẽ làm hỏng thử nghiệm A.
- **Render đo qua log**, không quan sát trên màn hình. Thời gian từ lúc NotificationCenter dựng xong tới lúc điểm ảnh đổi trên màn hình chưa đo, nhưng thường không đáng kể so với ngưỡng 5 giây.
- Không đo khi màn hình khoá, khi máy ngủ hay khi widget extension phải khởi động lạnh. Extension đã chạy sẵn suốt buổi đo.
- Chỉ có một máy, một widget và một kích thước widget.
- Không đọc được group container (TCC chặn), nên không đối chiếu được `reloadLog` của app. Mọi mốc thời gian đều lấy từ unified log.

## Mẫu thô

Giờ theo Asia/Saigon, ngày 2026-11-23. "Giai đoạn" lấy theo lần bấm thành công tương ứng (bấm thứ n ứng với yêu cầu thứ n).

| # | Giai đoạn | Yêu cầu reload | Timeline chạy xong | Render (LIVE) | ms → timeline | ms → render | Bộ lọc chronod |
|---|---|---|---|---|---|---|---|
| 1 | thu | 17:39:47.894 | 17:39:48.111 | 17:39:48.164 | 216 | 270 | cho phép |
| 2 | thu | 17:41:05.057 | 17:41:05.125 | 17:41:05.156 | 68 | 99 | cho phép |
| 3 | a-30s | 17:41:06.319 | 17:41:06.342 | 17:41:06.363 | 23 | 44 | cho phép |
| 4 | a-30s | 17:41:37.138 | 17:41:37.194 | 17:41:37.228 | 56 | 90 | cho phép |
| 5 | a-30s | 17:42:07.944 | 17:42:07.990 | 17:42:08.008 | 46 | 64 | cho phép |
| 6 | a-30s | 17:42:38.728 | 17:42:38.781 | 17:42:38.800 | 53 | 72 | cho phép |
| 7 | a-30s | 17:43:09.559 | 17:43:09.597 | 17:43:09.614 | 39 | 55 | cho phép |
| 8 | a-30s | 17:43:39.868 | 17:43:39.905 | 17:43:39.928 | 37 | 60 | cho phép |
| 9 | a-30s | 17:44:10.698 | 17:44:10.751 | 17:44:10.777 | 53 | 78 | cho phép |
| 10 | a-30s | 17:44:41.832 | 17:44:41.880 | 17:44:41.901 | 48 | 69 | cho phép |
| 11 | a-30s | 17:45:12.657 | 17:45:12.705 | 17:45:12.724 | 48 | 67 | cho phép |
| 12 | a-30s | 17:45:43.462 | 17:45:43.512 | 17:45:43.535 | 51 | 73 | cho phép |
| 13 | a-30s | 17:46:14.257 | 17:46:14.312 | 17:46:14.338 | 54 | 80 | cho phép |
| 14 | a-30s | 17:46:45.039 | 17:46:45.071 | 17:46:45.091 | 31 | 52 | cho phép |
| 15 | a-30s | 17:47:15.337 | 17:47:15.400 | 17:47:15.413 | 63 | 76 | cho phép |
| 16 | a-30s | 17:47:46.489 | 17:47:46.540 | 17:47:46.564 | 51 | 75 | cho phép |
| 17 | a-30s | 17:48:17.227 | 17:48:17.278 | 17:48:17.299 | 51 | 72 | cho phép |
| 18 | a-30s | 17:48:48.019 | 17:48:48.078 | 17:48:48.097 | 58 | 77 | cho phép |
| 19 | a-30s | 17:49:18.835 | 17:49:18.893 | 17:49:18.917 | 58 | 82 | cho phép |
| 20 | a-30s | 17:49:49.286 | 17:49:49.325 | 17:49:49.338 | 39 | 53 | cho phép |
| 21 | a-30s | 17:50:19.965 | 17:50:20.007 | 17:50:20.029 | 42 | 65 | cho phép |
| 22 | a-30s | 17:50:51.088 | 17:50:51.152 | 17:50:51.173 | 63 | 84 | cho phép |
| 23 | a-30s | 17:51:21.905 | 17:51:21.955 | 17:51:21.982 | 51 | 78 | cho phép |
| 24 | a-30s | 17:51:52.557 | 17:51:52.612 | 17:51:52.622 | 54 | 65 | cho phép |
| 25 | a-30s | 17:52:23.462 | 17:52:23.525 | 17:52:23.552 | 63 | 90 | cho phép |
| 26 | a-30s | 17:52:54.236 | 17:52:54.278 | 17:52:54.292 | 42 | 56 | cho phép |
| 27 | a-30s | 17:53:24.986 | — | — | — | — | cho phép |
| 28 | b-burst | 17:53:25.011 | 17:53:25.040 | 17:53:25.075 | 28 | 64 | bị throttle |
| 29 | b-burst | 17:53:25.605 | 17:53:25.649 | 17:53:25.658 | 44 | 53 | cho phép |
| 30 | b-burst | 17:53:25.660 | — | — | — | — | bị throttle |
| 31 | b-burst | 17:53:26.142 | — | — | — | — | bị throttle |
| 32 | b-burst | 17:53:26.219 | — | — | — | — | bị throttle |
| 33 | b-burst | 17:53:26.635 | — | — | — | — | bị throttle |
| 34 | b-burst | 17:53:26.703 | — | — | — | — | bị throttle |
| 35 | b-burst | 17:53:27.093 | — | — | — | — | bị throttle |
| 36 | b-burst | 17:53:27.209 | — | — | — | — | bị throttle |
| 37 | b-burst | 17:53:27.617 | — | — | — | — | bị throttle |
| 38 | b-burst | 17:53:27.702 | — | — | — | — | bị throttle |
| 39 | b-burst | 17:53:28.145 | — | — | — | — | bị throttle |
| 40 | b-burst | 17:53:28.214 | — | — | — | — | bị throttle |
| 41 | b-burst | 17:53:28.656 | — | — | — | — | bị throttle |
| 42 | b-burst | 17:53:28.717 | — | — | — | — | bị throttle |
| 43 | b-burst | 17:53:29.146 | — | — | — | — | bị throttle |
| 44 | b-burst | 17:53:29.238 | — | — | — | — | bị throttle |
| 45 | b-burst | 17:53:29.649 | — | — | — | — | bị throttle |
| 46 | b-burst | 17:53:29.729 | — | — | — | — | bị throttle |
| 47 | b-burst | 17:53:30.139 | — | — | — | — | bị throttle |
| 48 | b-burst | 17:53:30.235 | — | — | — | — | bị throttle |
| 49 | b-burst | 17:53:30.593 | 17:53:30.639 | 17:53:30.660 | 46 | 67 | bị throttle |
| 50 | b-burst | 17:53:30.691 | — | — | — | — | bị throttle |
| 51 | b-burst | 17:53:31.057 | — | — | — | — | bị throttle |
| 52 | b-burst | 17:53:31.145 | — | — | — | — | bị throttle |
| 53 | b-burst | 17:53:31.552 | — | — | — | — | bị throttle |
| 54 | b-burst | 17:53:31.642 | — | — | — | — | bị throttle |
| 55 | b-burst | 17:53:32.049 | — | — | — | — | bị throttle |
| 56 | b-burst | 17:53:32.134 | — | — | — | — | bị throttle |
| 57 | b-burst | 17:53:32.497 | — | — | — | — | bị throttle |
| 58 | b-burst | 17:53:32.595 | — | — | — | — | bị throttle |
| 59 | b-burst | 17:53:32.992 | — | — | — | — | bị throttle |
| 60 | b-burst | 17:53:33.096 | — | — | — | — | bị throttle |
| 61 | b-burst | 17:53:33.445 | — | — | — | — | bị throttle |
| 62 | b-burst | 17:53:33.534 | — | — | — | — | bị throttle |
| 63 | b-burst | 17:53:33.953 | — | — | — | — | bị throttle |
| 64 | b-burst | 17:53:34.045 | — | — | — | — | bị throttle |
| 65 | b-burst | 17:53:34.441 | — | — | — | — | bị throttle |
| 66 | b-burst | 17:53:34.516 | — | — | — | — | bị throttle |
| 67 | b-burst | 17:53:34.947 | — | — | — | — | bị throttle |
| 68 | b-burst | 17:53:35.022 | — | — | — | — | bị throttle |
| 69 | b-burst | 17:53:35.462 | — | — | — | — | bị throttle |
| 70 | b-burst | 17:53:35.540 | 17:53:35.636 | 17:53:35.658 | 96 | 118 | bị throttle |
| 71 | b-burst | 17:53:35.958 | — | — | — | — | bị throttle |
| 72 | b-burst | 17:53:36.041 | — | — | — | — | bị throttle |
| 73 | b-burst | 17:53:36.453 | — | — | — | — | bị throttle |
| 74 | b-burst | 17:53:36.545 | — | — | — | — | bị throttle |
| 75 | b-burst | 17:53:36.897 | — | — | — | — | bị throttle |
| 76 | b-burst | 17:53:37.000 | — | — | — | — | bị throttle |
| 77 | b-burst | 17:53:37.449 | — | — | — | — | bị throttle |
| 78 | c-1min | 17:53:37.502 | 17:53:40.654 | 17:53:40.670 | 3153 | 3168 | bị throttle |
| 79 | c-1min | 17:54:38.590 | 17:54:38.633 | 17:54:38.658 | 44 | 68 | cho phép |
| 80 | c-1min | 17:55:39.399 | 17:55:39.445 | 17:55:39.468 | 46 | 70 | cho phép |
| 81 | c-1min | 17:56:40.167 | 17:56:40.232 | 17:56:40.260 | 66 | 93 | cho phép |
| 82 | c-1min | 17:57:40.439 | 17:57:40.482 | 17:57:40.503 | 43 | 63 | cho phép |
| 83 | c-1min | 17:58:41.619 | 17:58:41.668 | 17:58:41.696 | 49 | 77 | cho phép |
| 84 | c-1min | 17:59:42.069 | 17:59:42.113 | 17:59:42.138 | 44 | 69 | cho phép |
| 85 | c-1min | 18:00:42.835 | 18:00:42.879 | 18:00:42.899 | 44 | 64 | cho phép |
| 86 | c-1min | 18:01:43.984 | 18:01:44.034 | 18:01:44.061 | 51 | 77 | cho phép |
| 87 | c-1min | 18:02:44.791 | 18:02:44.828 | 18:02:44.846 | 36 | 55 | cho phép |
| 88 | c-1min | 18:03:45.551 | 18:03:45.595 | 18:03:45.617 | 44 | 66 | cho phép |
| 89 | c-1min | 18:04:46.302 | 18:04:46.356 | 18:04:46.370 | 53 | 68 | cho phép |
| 90 | c-1min | 18:39:18.960 | 18:39:19.007 | 18:39:19.028 | 47 | 68 | cho phép |
| 91 | c-1min | 18:40:19.726 | 18:40:19.758 | 18:40:19.764 | 32 | 38 | cho phép |
| 92 | c-1min | 18:41:20.532 | 18:41:20.570 | 18:41:20.583 | 38 | 51 | cho phép |
| 93 | c-1min | 18:42:20.957 | 18:42:21.002 | 18:42:21.017 | 45 | 59 | cho phép |
| 94 | c-1min | 18:43:22.103 | 18:43:22.142 | 18:43:22.164 | 38 | 60 | cho phép |
| 95 | c-1min | 18:44:22.884 | 18:44:22.937 | 18:44:22.963 | 52 | 79 | cho phép |
| 96 | c-1min | 18:45:23.644 | 18:45:23.692 | 18:45:23.709 | 48 | 65 | cho phép |
| 97 | c-1min | 18:46:24.443 | 18:46:24.496 | 18:46:24.509 | 53 | 66 | cho phép |
| 98 | c-1min | 18:47:25.232 | 18:47:25.253 | 18:47:25.274 | 21 | 42 | cho phép |
| 99 | c-1min | 18:48:26.007 | 18:48:26.056 | 18:48:26.071 | 48 | 64 | cho phép |
| 100 | c-1min | 18:49:26.793 | 18:49:26.830 | 18:49:26.844 | 36 | 50 | cho phép |
| 101 | c-1min | 18:50:27.581 | 18:50:27.602 | 18:50:27.608 | 22 | 27 | cho phép |
| 102 | c-1min | 18:51:28.396 | 18:51:28.437 | 18:51:28.450 | 42 | 54 | cho phép |
| 103 | c-1min | 18:52:29.126 | 18:52:29.174 | 18:52:29.189 | 47 | 62 | cho phép |
| 104 | c-1min | 18:53:29.911 | 18:53:29.936 | 18:53:29.951 | 24 | 40 | cho phép |
| 105 | d-5min | 18:58:30.715 | 18:58:30.748 | 18:58:30.766 | 34 | 52 | cho phép |
| 106 | d-5min | 19:03:31.524 | 19:03:31.569 | 19:03:31.582 | 46 | 59 | cho phép |
| 107 | d-5min | 19:08:32.360 | 19:08:32.406 | 19:08:32.420 | 46 | 60 | cho phép |
| 108 | d-5min | 19:13:33.168 | 19:13:33.210 | 19:13:33.231 | 42 | 63 | cho phép |
| 109 | d-5min | 19:18:34.011 | 19:18:34.077 | 19:18:34.101 | 67 | 90 | cho phép |
| 110 | d-5min | 19:23:34.791 | 19:23:34.846 | 19:23:34.868 | 55 | 78 | cho phép |
| 111 | d-5min | 19:32:29.305 | 19:32:29.340 | 19:32:29.359 | 34 | 54 | cho phép |
| 112 | d-5min | 19:37:30.147 | 19:37:30.196 | 19:37:30.216 | 49 | 69 | cho phép |
| 113 | d-5min | 19:42:30.934 | 19:42:30.975 | 19:42:31.001 | 42 | 67 | cho phép |
| 114 | d-5min | 19:47:31.718 | 19:47:31.772 | 19:47:31.793 | 54 | 76 | cho phép |
| 115 | d-5min | 19:52:32.475 | 19:52:32.525 | 19:52:32.542 | 50 | 67 | cho phép |
| 116 | d-5min | 19:57:33.229 | 19:57:33.255 | 19:57:33.261 | 26 | 32 | cho phép |
| 117 | e-10min | 20:07:34.004 | 20:07:34.054 | 20:07:34.072 | 50 | 69 | cho phép |
| 118 | e-10min | 20:17:34.808 | 20:17:34.855 | 20:17:34.870 | 47 | 62 | cho phép |
| 119 | e-10min | 20:27:35.623 | 20:27:35.669 | 20:27:35.685 | 46 | 62 | cho phép |
| 120 | e-10min | 20:37:36.415 | 20:37:36.443 | 20:37:36.451 | 28 | 36 | cho phép |

## Việc tiếp theo

- Ghi NFR-2 vào `docs/prd.md` sau khi chủ dự án duyệt. Báo cáo này không sửa prd.md.
- Khi app menu bar thật chạy, đo reload lúc app ở nền: số lần reload mỗi ngày và độ trễ khi gần hết ngân sách.
- Thiết kế app gộp các lần reload: tối đa một lần mỗi 5 giây, và gọi lần cuối khi đợt đồng bộ xong.
- Chủ dự án có thể tắt quyền Accessibility của Ghostty và kéo "Probe" về chỗ cũ trên thanh menu. Buổi đo không còn cần hai thay đổi này.

## Câu hỏi còn mở

- Ngân sách reload khi app chạy nền trên macOS 27 là bao nhiêu, và widget trễ bao lâu khi hết ngân sách?
- Có nên giữ ngưỡng 5 giây khi app chạy nền, hay cần ngưỡng riêng cho trường hợp đó?
