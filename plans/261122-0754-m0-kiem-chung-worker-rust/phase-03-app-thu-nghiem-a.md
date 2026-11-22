---
phase: 3
title: "App thử nghiệm A (kèm panel C)"
status: completed
priority: P1
effort: "2h"
dependencies: [1, 2]
---

# Phase 3: App thử nghiệm A (kèm panel C)

## Goal

Cài lên một máy Mac một app tối giản có widget extension dùng App Group dạng `<TeamID>.os-widget`, ký bằng tài khoản Apple miễn phí, và ghi ngày cài để bắt đầu đồng hồ 7 ngày. App có thêm một panel không kích hoạt để kiểm thử nghiệm C trên cùng project.

## Context

- Trả lời câu hỏi A trong `docs/roadmap.md`: App Groups có dùng được với tài khoản miễn phí không, và sau 7 ngày app còn chạy không.
- Đây là mã bỏ đi được, đặt riêng trong `spikes/`, không thuộc client chính thức của Giai đoạn 2.
- Dùng XcodeGen để project tạo lại được từ `project.yml` mà không phải thao tác GUI nhiều.

## Files to Create / Modify

- Create: `spikes/widget-probe/project.yml`
- Create: `spikes/widget-probe/App/ProbeApp.swift`
- Create: `spikes/widget-probe/App/App.entitlements`
- Create: `spikes/widget-probe/Widget/ProbeWidget.swift`
- Create: `spikes/widget-probe/Widget/Widget.entitlements`
- Create: `plans/261122-0754-m0-kiem-chung-worker-rust/reports/a-c-results.md`

## Tasks & Steps

- [x] `project.yml`: hai target, app macOS và widget extension; deployment target macOS 26; `DEVELOPMENT_TEAM` lấy từ Team ID ở Phase 1; ký tự động.
- [x] Entitlements của cả hai target: App Sandbox, `com.apple.security.application-groups = [$(TeamIdentifierPrefix)os-widget]`.
- [x] App là agent (`LSUIElement = YES`), có `NSStatusItem` với ba mục menu:
  - "Ghi dữ liệu": ghi chuỗi thời điểm hiện tại vào `UserDefaults(suiteName: "<TeamID>.os-widget")`, sau đó gọi `WidgetCenter.shared.reloadAllTimelines()`.
  - "Mở panel sau 10 giây": sau 10 giây mở một `NSPanel` kiểu `.nonactivatingPanel` bằng `orderFrontRegardless()`, không gọi `NSApp.activate`.
  - "Ghi log reload": ghi thời điểm mỗi lần gọi reload vào App Group, để dùng lại khi đo B.
- [x] Widget đọc chuỗi từ App Group và hiển thị; nếu không đọc được thì hiện "App Group: lỗi" để thấy rõ thất bại.
- [x] `xcodegen generate`, sau đó build bằng `xcodebuild -scheme <app> -configuration Debug -allowProvisioningUpdates build`.
- [x] Copy app vào `/Applications`, mở app, thêm widget lên desktop (người dùng làm qua "Edit Widgets").
- [x] Ghi vào `reports/a-c-results.md`: ngày giờ cài, phiên bản macOS và Xcode, ngày hết hạn của provisioning profile (xem bằng `security cms -D -i <app>/Contents/embedded.provisionprofile`), kết quả ngày 1 (widget có hiện chuỗi vừa ghi không). Không có provisioning profile nào được nhúng, nên ghi chú điều đó thay cho ngày hết hạn; chứng chỉ ký hết hạn 2027-11-22.

## Verification

- Bấm "Ghi dữ liệu" thì widget hiện đúng chuỗi thời điểm vừa ghi, không phải "App Group: lỗi".
- `reports/a-c-results.md` có ngày cài và ngày hết hạn profile.
- Kiểm C (có thể làm ngay hoặc vào ngày 8): mở TextEdit và đang gõ, bấm "Mở panel sau 10 giây"; khi panel hiện, ký tự gõ tiếp vẫn vào TextEdit. Ghi kết quả vào cùng file.

## Risk Assessment

- Build lỗi vì tài khoản miễn phí không cấp App Group cho widget: đây là một kết quả của A, không phải lỗi cần lách. Ghi lỗi nguyên văn vào `a-c-results.md` và đánh A là thất bại (phương án dự phòng: widget lấy dữ liệu qua localhost).
- XcodeGen sinh project sai cho widget extension: chỉnh `project.yml`. Không chuyển sang tạo project bằng tay trừ khi người dùng đồng ý.
