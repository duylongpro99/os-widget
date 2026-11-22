# Kết quả thử nghiệm A và C

App thử nghiệm: `spikes/widget-probe/`, gồm target `WidgetProbe` (app agent trên thanh menu) và widget extension `ProbeWidget`.

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

**Đạt.** Operator thêm widget "Probe" lên desktop qua "Edit Widgets", bấm "Ghi dữ liệu", và widget hiện mốc thời gian vừa ghi, không phải "App Group: lỗi". Lời operator (khoảng 21:5x ngày 2026-11-22, nguyên văn): "đã xong, proble hiện thời gian".

| Câu hỏi | Kết quả |
|---|---|
| Widget hiện mốc thời gian hay "App Group: lỗi" | Hiện mốc thời gian |
| Độ trễ từ lúc bấm đến lúc widget đổi | Không được báo |
| Hộp thoại xin quyền truy cập dữ liệu app khác | Không được báo |
| Chuỗi "App Group: …" trong menu | Không được báo |

Kết luận ngày 1: App Group dạng `<TeamID>.os-widget` dùng được giữa app và widget khi ký bằng tài khoản Apple miễn phí, không cần provisioning profile.

### Ngày 8 (2026-11-30)

_Chưa đến. Kiểm: app còn chạy không, mở lại được không, bấm "Ghi dữ liệu" thì widget có cập nhật không._

## C. Panel không kích hoạt

### Ngày 1 (2026-11-22)

**Đạt.** Operator gõ liên tục trong TextEdit, bấm "Mở panel sau 10 giây" trên menu Probe. Panel `.nonactivatingPanel` mở bằng `orderFrontRegardless()`, không gọi `NSApp.activate`.

| Câu hỏi | Kết quả |
|---|---|
| Panel có hiện không | Có, sau 10 giây. Lời operator: "panel có hiện sau 10s" |
| Ký tự gõ tiếp có vẫn vào TextEdit không | Có. Lời operator (2026-11-22 21:56): "Vẫn vào TextEdit" |
| Thanh menu còn ghi "TextEdit" không | Không báo riêng; lựa chọn operator chọn có ghi thanh menu vẫn là TextEdit |

Kết luận: popup dạng panel không kích hoạt không cướp focus khi người dùng đang gõ ở app khác.
