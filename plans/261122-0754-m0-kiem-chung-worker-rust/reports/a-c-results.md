# Kết quả thử nghiệm A và C

App thử nghiệm: `spikes/widget-probe/`, gồm target `WidgetProbe` (app agent trên thanh menu) và widget extension `ProbeWidget`, trên branch `widget-probe-app`.

## Môi trường

- macOS 26.6.2
- Xcode 27.2 (build 27B52), xcodegen 2.48.0
- Ký tự động bằng Personal Team `22LZWPB3XL` (tài khoản Apple miễn phí), chứng chỉ "Apple Development" tạo ngày 2026-11-22 và hết hạn 2027-11-22.

## A. App Group với tài khoản miễn phí

| Mục | Giá trị |
|---|---|
| Team ID | `22LZWPB3XL` (Personal Team) |
| App Group | `22LZWPB3XL.os-widget` |
| Ngày giờ cài vào /Applications | 2026-11-22 21:47:25 +0700 |
| Mở app lần đầu | 2026-11-22 21:47:36 +0700 |
| Provisioning profile | Không có. Xcode ký mà không tạo hay nhúng `embedded.provisionprofile` vào app lẫn widget, nên không có ngày hết hạn profile. |
| Entitlement thực cấp (app) | `com.apple.security.app-sandbox = true`, `com.apple.security.application-groups = [22LZWPB3XL.os-widget]`, `get-task-allow = true` |
| Entitlement thực cấp (widget) | Giống app |

Bằng chứng khi cài:

- `codesign --verify --deep --strict` đạt. `spctl -a` báo `rejected`, điều này là bình thường với bản ký development chưa notarize, và app vẫn mở được vì được build ngay trên máy.
- Group container `~/Library/Group Containers/22LZWPB3XL.os-widget` được tạo khi app chạy lần đầu.
- `pluginkit -m -i local.oswidget.probe.widget` thấy widget đã đăng ký.

Nhận xét: vì không có provisioning profile, mốc 7 ngày của profile miễn phí có thể không áp dụng cho app macOS dạng này. Kiểm ngày 8 sẽ trả lời câu này bằng thực tế.

### Ngày 1 (2026-11-22)

_Chờ operator thêm widget và bấm "Ghi dữ liệu"._

### Ngày 8 (2026-11-30)

_Chưa đến. Kiểm: app còn chạy không, mở lại được không, bấm "Ghi dữ liệu" thì widget có cập nhật không._

## C. Panel không kích hoạt

_Chờ operator kiểm bằng TextEdit._
