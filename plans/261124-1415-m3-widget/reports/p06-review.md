# Review nhánh `widget-acceptance` trước khi merge

Session `m3-widget-p06-review`, ngày 2026-11-27 (Asia/Saigon). Phạm vi: toàn bộ diff `main...widget-acceptance` (main `b44cd2f`, nhánh lúc bắt đầu `4ed841b`), cùng đếm lại reload nửa ngày và mục 7 của checklist. Nhánh chỉ đổi script và tài liệu, không đổi mã sản phẩm.

## Kết luận

**Merge được.** Đếm lại đạt ngưỡng của operator và mục 7 đạt; review thấy hai lỗi nhỏ, đều đã sửa trên nhánh, mỗi lỗi một commit. Không thấy lỗi nào chặn merge.

| Kiểm | Kết quả |
|---|---|
| Đếm lại 12 giờ dùng thật (2026-11-27 08:56:41 tới 20:56:41, ngưỡng 20) | PASS: 12 yêu cầu, nhỏ nhất 5290 ms giữa hai yêu cầu, 100% có timeline trong 5 s (lớn nhất 178 ms), 0 lần bấm nút |
| Mục 7, đêm 2026-11-26 tới 27 | Đạt: ngủ 22:07:16, thức 08:56:12; `sync.applied new=2` 08:56:13.801, một `widget.reload` 08:56:13.838, timeline 08:56:13.872 (cỡ vừa) và 08:56:13.989 (cỡ lớn) |
| `bash -n`, `shellcheck` hai script | Không báo gì (trước và sau khi sửa) |
| Tên và đường dẫn trong tài liệu | Khớp mã, kiểm bằng `git grep` và `ls` |
| Secrets trong diff và commit | Không có (`sb_secret_`, `eyJhbGci`, `postgres://`, `Bearer` kèm token dài) |
| Mã quyết định, plan, phase trong commit message | Không có |

Số đo chi tiết ở [reload-day.md](./reload-day.md) và [acceptance.md](./acceptance.md).

## Phát hiện và sửa

1. **Comment trong `scripts/acceptance-widget.sh` nói sai số reload mỗi lần bấm.** Ở nhánh `day` comment ghi mỗi lần bấm nút trên widget gây "about one reload"; log nghiệm thu cho thấy khoảng 2 (một `changed` sau khi app rút hộp thư, một `trailing` khoảng 5 s sau khi sync áp lại trạng thái từ server, ví dụ 16:08:14.899 và 16:08:20.055 ngày 24/11; lần đếm lại cũng thấy 11:56:09.095 và 11:56:14.385). Chỉ là comment, không đổi hành vi. Sửa ở `ba8791e`.
2. **Tài liệu nói `n_today` chỉ về 1 khi app chạy lại.** `WidgetReloadPolicy` đếm theo ngày giờ máy (`calendar.startOfDay`, đặt lại `reloadsToday = 0` khi sang ngày mới), và log có `widget.reload n_today=1` lúc 2026-11-27 00:07:31 trong khi app vẫn chạy. Ai đọc `n_today` như số trong 24 giờ hay từ lúc app chạy sẽ hiểu sai. Sửa câu trong architecture §6, acceptance.md và reload-day.md ở `40125c0`.

Đã xem và không coi là lỗi:

- `acceptance-widget.sh day` chỉ đếm lần bấm từ file khi `--input` là tham số đầu. Đó là cách gọi duy nhất trong tài liệu; với `--start`/`--end` script dùng `log show`.
- Dòng `per hour` của `widget-reload-count.sh` không ghi ngày. reload-day.md đã ghi chú; cửa sổ đếm lại nằm trong một ngày nên không lẫn.
- Ngưỡng 20 của lần đếm lại truyền bằng `MAX_REQUESTS=20`, biến môi trường script đã hỗ trợ; mặc định 40 không đổi. `scripts/widget-reload-count.sh` không bị sửa.
- `check_tap` chờ `widget.inbox_drained` bất kỳ sau lần bấm, không theo id. Trong lúc nghiệm thu chỉ có một lần bấm mỗi lượt nên không sai kết quả; chỉ đáng sửa nếu script được chạy song song với thao tác khác.

## Ghi nhận ngoài phạm vi

- Roadmap Giai đoạn 2 còn ghi "Còn chờ: … một đêm ngủ máy (bắt kịp sau khi thức)". Đêm 26–27/11 chứng minh app bắt kịp sau khi thức (xem mục 7). Session này không sửa phần Giai đoạn 2; giám sát quyết có cập nhật không.
- Lúc thức tối 17:59 tới 20:06 ngày 27/11 app chỉ có `sync.retry reason=network`; hai thẻ tới ở vòng 20:06:57 với một reload. Không phải lỗi widget, nhưng cho thấy lúc máy gập có lúc không có mạng khi thức tối.

## Dọn dẹp

- `log stream` PID 6328 đã dừng lúc 2026-11-27 21:11 (`kill 6328`, `ps -p 6328` rỗng). File `~/Library/Logs/os-widget/widget-day-20261124.ndjson` được giữ.
- File log cắt cho lần đếm lại và đêm 26–27 nằm trong thư mục tạm của session, ngoài repo.
- Session này không publish, không xoá dữ liệu thật, không đụng app đã cài hay WidgetProbe.
