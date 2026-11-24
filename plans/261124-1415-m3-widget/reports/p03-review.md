# Báo cáo review phase 3: chính sách reload và đếm reload

Nhánh `widget-reload-policy` (head cook 9c9e2f3) đã review, sửa hai lỗi nhỏ và merge vào main bằng `--no-ff` (merge `e848349`). Phase 3 đánh dấu Completed.

## Phát hiện và sửa

| # | Phát hiện | Sửa |
|---|---|---|
| 1 | Đồng hồ máy bị lùi sau một lần reload (chỉnh giờ tay, đồng bộ NTP lớn): `offer` hẹn ở `lastReloadAt + 5 s`, có thể xa hàng giờ so với giờ mới; reloader ngủ tới lúc đó và mọi thay đổi trong khoảng ấy bị giữ lại. | `d1bf8b2`: khi thời gian trôi âm thì hẹn ở `now + 5 s`. Test mới `aClockSetBackWaitsOneIntervalFromNow` (trượt trên mã cũ, đạt trên mã mới). |
| 2 | Script đo khoảng cách giữa hai yêu cầu bằng dấu thời gian log, nhưng reloader ghi log sau lệnh `reloadTimelines` và đọc hộp thư sau khi lấy giờ. Lần reload đầu mất thời gian đọc file và gọi WidgetKit lâu hơn lần trailing, nên khoảng cách đúng 5 s có thể hiện thành 4997–4999 ms và script kết luận FAIL dù chính sách đúng. | `b1c51de`: đọc hộp thư trước khi lấy giờ, ghi log trước khi gọi WidgetKit. Dấu thời gian log bám sát thời điểm của chính sách. |

## Đã kiểm

- Chính sách: lần đầu luôn `.reloadNow`; snapshot giống nhau `.skip`; đợt dồn chỉ một `.schedule`, `fire` dùng snapshot mới nhất; đổi rồi đổi lại thì `fire` trả `false`; đồng hồ lùi (sau sửa). `WidgetSnapshot` không chứa giờ hiện tại và có `unreadCount` của mọi mục hiển thị, nên đổi số chưa đọc kích hoạt reload đúng quyết định của giám sát.
- Reloader là lớp vỏ mỏng: dựng snapshot, hỏi chính sách, hẹn một `Task.sleep`, gọi reload, ghi log. Không có quyết định nào nằm ngoài `WidgetReloadPolicy`. Đăng ký lại `withObservationTracking` mỗi lần báo, chỉ theo dõi `store.items`.
- Log: `widget.reload` ở mức `notice` (lưu lại, `log show --info` đọc được), chỉ có số đếm và lý do; dòng skip ở `debug`. Không có nội dung mục. Dòng `widget.timeline` của phase 4 trên main đúng định dạng script đọc.
- Script: `bash -n`, `shellcheck` sạch. Trên mẫu in đúng `requests=7 min_gap_ms=5000 within_5s=85.7 timelines=9 verdict=FAIL`; đầu vào rỗng cho PASS; một lần `--last 5m` trên log thật chạy được (0 dòng). Điều kiện PASS khớp D9: ≤ 40 yêu cầu, khoảng cách nhỏ nhất ≥ 5000 ms, ≥ 95% yêu cầu có timeline trong 5 s.
- Mutation: bỏ khoảng 5 s tối thiểu trong `offer` thì 6 kỳ vọng trượt; đã trả lại.
- Main sau merge (cây giống nhánh đã merge main): `swift test` 168 pass, `cargo test --workspace` 151 pass, `xcodebuild` Debug không ký với derivedDataPath ngoài repo: BUILD SUCCEEDED.

## Ghi chú cho Phase 6

- Khoảng 24 giờ không có yêu cầu nào thì script in PASS. Khi đếm ngày thật, kiểm thêm `requests > 0` (app có chạy bản mới) trước khi tin kết luận.
- `within_5s` được làm tròn một chữ số trước khi so với 95; với ≤ 40 yêu cầu không có tỉ lệ nào bị làm tròn qua ngưỡng, nên không sửa.
