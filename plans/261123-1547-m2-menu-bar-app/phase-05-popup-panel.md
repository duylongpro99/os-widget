---
phase: 5
title: "Popup panel"
status: completed
priority: P1
effort: "5h"
dependencies: [2]
---

# Phase 5: Popup panel

## Goal

Khi có mục mới, một panel không kích hoạt duy nhất hiện dưới icon thanh menu với thẻ mục mới nhất và số mục còn lại, tự đóng sau 30 giây (dừng đếm khi chuột ở trong), không lấy focus bàn phím, và tôn trọng `priority: low`, cài đặt theo loại, chế độ yên lặng và việc danh sách đang mở.

## Context

- Phụ thuộc thử nghiệm C (đã đạt ngày 1): panel `NSPanel` với `styleMask` gồm `.nonactivatingPanel`, mở bằng `orderFrontRegardless()`, không gọi `NSApp.activate`, `hidesOnDeactivate = false`, `level = .floating` (mã ở `spikes/widget-probe/App/ProbeApp.swift`, hàm `showPanel`). Giữ đúng các cờ này; đổi kiểu viền hoặc mức cửa sổ phải kiểm lại focus.
- PRD: FR-6, FR-7, FR-8, FR-10, FR-10a, FR-10b, FR-10c; NFR-1 (5 giây). Đã chốt: popup hiển thị 30 giây; popup luôn mở cho mục không phải `low`, không dò trạng thái desktop (PRD §11).
- Nguồn mục mới: `store.announcement` (Phase 2), do sync engine gọi một lần mỗi vòng (Phase 3). Mỏ neo và trạng thái danh sách: `anchor` và `isListOpen` truyền vào `PopupController` (chữ ký từ Phase 1, giá trị do Phase 4 cung cấp).
- Làm song song được với Phase 3 và 4 sau Phase 2. Trong lúc chưa có Phase 3, kiểm bằng đường gỡ lỗi trong chính `PopupController`: bản Debug chạy với biến môi trường `OSWIDGET_DEBUG_ANNOUNCE=<giây>` sẽ gọi `store.announce` với một mục mẫu sau số giây đó (không sửa menu của Phase 4).

## Requirements

**Chính sách** (`OSWidgetKit/Sources/OSWidgetKit/Popup/PopupPolicy.swift`, hàm thuần):

- Đầu vào: các mục trong thông báo, `popupSettings` (loại bị tắt, `quietMode`), `isListOpen`, thời điểm hiện tại. Đầu ra: `.none` hoặc `.show(newest: Item, othersCount: Int)`.
- Lọc mục: bỏ `priority == "low"` (FR-10); bỏ `kind` nằm trong loại bị tắt (FR-10c); bỏ mục đã đọc hoặc hết hạn.
- Trả `.none` khi: danh sách đang mở (FR-10b, danh sách tự làm nổi bật ở Phase 4); đang trong chế độ yên lặng; không còn mục nào sau lọc.
- Khi popup đang hiện mà có thông báo mới: `othersCount` cộng dồn với số mục đang chờ trong popup (FR-8: thay nội dung bằng mục mới nhất, đếm lại 30 giây, hiện số mục còn lại). Logic cộng dồn nằm trong hàm thuần `merge(current:incoming:)` để test được.

**Panel** (`App/Popup/`):

- Một `NSPanel` duy nhất tạo một lần và dùng lại; không bao giờ có hai panel (FR-8).
- Cờ theo thử nghiệm C ở trên, cộng `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` để hiện trên mọi Space và trên app toàn màn hình (FR-6: hiện bất kể desktop có đang bị che). `canBecomeKey` trả `false` qua lớp con `NSPanel` để bấm nút trong panel không lấy focus bàn phím. Không phát âm thanh (FR-7).
- Vị trí: mép trên panel ngay dưới khung `anchor()`, căn giữa theo icon, giữ trong `visibleFrame` của màn hình chứa icon. `anchor()` trả `nil` (icon bị ẩn do tràn thanh menu hoặc tai thỏ) thì đặt góc trên bên phải của màn hình chính.
- Nội dung SwiftUI qua `NSHostingView`: `CardView` của Phase 4 cho mục mới nhất; dòng "+N mục khác" khi `othersCount > 0`, bấm vào thì đóng popup và mở danh sách; nút đóng.
- Hẹn giờ 30 giây. `NSTrackingArea` dừng đếm khi chuột vào panel và đếm tiếp phần còn lại khi chuột ra (FR-6). Mục mới tới thì đếm lại từ 30 giây.
- Bấm thẻ: `store.markRead` cho mục đó, mở `url` nếu `URLPolicy.isOpenable`, đóng popup (FR-10a). Tự đóng hoặc bấm nút đóng: không đổi trạng thái đã đọc, dấu báo vẫn còn (FR-10a).
- Danh sách được mở khi popup đang hiện: đóng popup.
- Log (subsystem `local.oswidget.app`, category `popup`): `popup.shown id=<id> others=<n> latency_ms=<giờ máy lúc hiện trừ created_at>`, `popup.suppressed reason=<low|kind|quiet|list_open>`, `popup.closed reason=<timeout|button|click|list>`. Dòng `popup.shown` là số đo cho PRD §10.1 ở Phase 6.

## Files to Create / Modify

Đường dẫn tương đối với `apps/macos/`.

- Modify: `App/Popup/PopupController.swift` (khung từ Phase 1)
- Create: `App/Popup/PopupPanel.swift`, `App/Popup/PopupContentView.swift`
- Create: `OSWidgetKit/Sources/OSWidgetKit/Popup/PopupPolicy.swift`, `OSWidgetKit/Tests/OSWidgetKitTests/PopupPolicyTests.swift`

## Tasks & Steps

- [ ] `PopupPolicy` và `merge`, test trước (bảng dưới).
- [ ] `PopupPanel` (lớp con `NSPanel`) với cờ của thử nghiệm C, vị trí theo mỏ neo.
- [ ] `PopupContentView` nhúng `CardView`, dòng "+N", nút đóng.
- [ ] `PopupController`: quan sát `store.announcement`, gọi chính sách, hẹn giờ, theo dõi chuột, log.
- [ ] Đường gỡ lỗi `OSWIDGET_DEBUG_ANNOUNCE` (chỉ `#if DEBUG`, trong `PopupController.swift`) để kiểm khi Phase 3 chưa xong.
- [ ] Kiểm focus bằng tay (mục Verification).

| Test (`PopupPolicyTests`) | Kiểm |
|---|---|
| Một mục `normal` | `.show(newest, 0)` |
| Ba mục cùng lúc (máy thức dậy) | `.show(mục có created_at mới nhất, 2)` |
| `priority: low` | Bị lọc; chỉ toàn mục `low` thì `.none` |
| Loại bị tắt | Mục `kind` đó bị lọc, loại khác vẫn hiện |
| Chế độ yên lặng | `quietMode` bật thì `.none`; tắt thì hiện |
| Danh sách đang mở | `.none` |
| `kind` lạ | Vẫn hiện (thẻ dự phòng) |
| Gộp khi đang hiện | Popup đang hiện mục A với `others = 1`, thông báo mới gồm B: hiện B với `others = 2` |

## Verification

- `cd apps/macos/OSWidgetKit && swift test` pass, gồm `PopupPolicyTests`.
- App build được. Kiểm bằng tay (với Phase 3 đã ghép; trước đó dùng `OSWIDGET_DEBUG_ANNOUNCE`, trừ kiểm "thay nội dung" cần publish thật):
  - **Focus:** mở TextEdit, gõ liên tục; ở máy khác hoặc ở Terminal chạy `sleep 5; os-widget publish --source m2-test --title "focus" --summary "phase 5" --ttl 3600`. Panel hiện dưới icon; ký tự gõ tiếp vẫn vào TextEdit; `lsappinfo front` chạy trước và sau khi panel hiện cùng trả TextEdit.
  - **30 giây:** không chạm thì panel đóng sau khoảng 30 giây; để chuột trong panel 40 giây thì panel không đóng, rút chuột ra thì đóng sau phần còn lại.
  - **Thay nội dung:** publish mục thứ hai khi panel đang hiện: vẫn một panel, nội dung đổi, "+1 mục khác".
  - **Low, loại bị tắt, yên lặng, danh sách mở:** mỗi trường hợp publish một mục; không có panel, log có `popup.suppressed` đúng lý do; mục vẫn vào danh sách và dấu báo.
  - **Toàn màn hình:** một app ở chế độ toàn màn hình; panel vẫn hiện trên app đó.
  - **Đóng không tính đã đọc:** sau khi panel tự đóng, mục vẫn chưa đọc và chấm báo còn.

## Risk Assessment

- Lớp con `NSPanel` với `canBecomeKey = false` khác cấu hình đã kiểm ở thử nghiệm C (C dùng `NSPanel` gốc): làm cho panel ít khả năng lấy focus hơn chứ không nhiều hơn, nhưng vẫn phải chạy lại kiểm focus ở trên trước khi coi phase là xong. Nếu panel lấy focus, quay về đúng cấu hình C và dừng hỏi.
- `.fullScreenAuxiliary` có thể làm panel không hiện trên Space toàn màn hình ở một số bản macOS; nếu kiểm thất bại, ghi lại và giữ hành vi trên desktop thường (FR-6 vẫn đạt khi desktop bị cửa sổ thường che).
- Nút trong `NSHostingView` của panel không kích hoạt có thể cần `acceptsFirstMouse` để bấm lần đầu có tác dụng: đặt `acceptsFirstMouse(for:)` trả `true` ở view chứa.

## Rollback

Trả `PopupController.swift` về khung của Phase 1 và xoá các file còn lại của phase. App vẫn chạy với danh sách và dấu báo, chỉ không có popup.

## Ghi chú

- Quyết định của operator (2026-11-23, khoảng 21:05): "Cook ngay, chưa ký/cài (Đề xuất)". Phase này chỉ kiểm bằng `swift test` và build Debug không ký; app chưa chạy.
- Ghép với Phase 4: popup dùng `CardView(item:)` (thẻ tạm đã xoá), `URLPolicy.openableURL` để mở `url` của mục, và `View.onCardClick(tap:link:)`: bấm thẻ thì đánh dấu đã đọc, mở `url` nếu được phép, đóng popup; bấm liên kết trong thẻ thì đánh dấu đã đọc, chỉ mở liên kết đó, đóng popup. Nút đóng không đánh dấu đã đọc. Dòng "+N mục khác" đóng popup rồi gửi `Notification.Name.openItemListRequested` để thanh menu mở danh sách. Panel rộng bằng `CardMetrics.width` cộng cột nút đóng.
- Phase 5 chỉ quan sát `ItemStore.announcement`; Phase 3 gọi `announce` tối đa một lần mỗi vòng sync nên giới hạn "chỉ giữ thông báo mới nhất" do bên gọi xử lý.
- Hoãn tới Phase 6 (cần app chạy), theo báo cáo cook: kiểm focus với TextEdit và `lsappinfo front` (lần đầu kiểm lớp con có `canBecomeKey = false`); tự đóng sau 30 giây và dừng đếm khi chuột trong panel; thay nội dung với "+1 mục khác" (cần Phase 3); không hiện với `low`, loại bị tắt, chế độ yên lặng, danh sách mở, kèm log `popup.suppressed`; hiện trên app toàn màn hình; tự đóng không đánh dấu đã đọc; nút bấm có tác dụng ngay lần đầu và panel vừa nội dung (kể cả khi ảnh trong thẻ tải xong sau); bấm liên kết trong thẻ chỉ mở liên kết đó; "+N" mở danh sách.
- Báo cáo: [cook](../reports/cook-261123-m2-p05.md), [review](../reports/review-261123-m2-p05.md).
