---
phase: 1
title: "Chuẩn bị công cụ và tài khoản"
status: completed
priority: P1
effort: "1h"
dependencies: []
---

# Phase 1: Chuẩn bị công cụ và tài khoản

## Goal

Gom mọi điều kiện tiên quyết lên đầu, để các phase sau không phải dừng giữa chừng vì thiếu công cụ, tài khoản hoặc hạn mức chưa rõ.

## Context

Kiểm tra máy ngày 2026-11-22: đã có `cargo`, `rustup`, `node`/`npx`, `supabase` CLI, `psql`, `xcodebuild`, `git`. Chưa có target `wasm32-unknown-unknown`, `wrangler`, `worker-build`, `xcodegen`.

## Files to Create / Modify

- Create: `plans/261122-0754-m0-kiem-chung-worker-rust/reports/limits.md`

## Tasks & Steps

- [x] Cài target Wasm: `rustup target add wasm32-unknown-unknown`.
- [x] Cài `worker-build`: `cargo install worker-build`.
- [x] Chạy `npx wrangler --version` và ghi phiên bản; mọi lệnh wrangler sau đó dùng `npx wrangler@<phiên bản đó>`.
- [x] Người dùng đăng nhập Cloudflare: `! npx wrangler login` (tương tác, không tự chạy được). Xác nhận bằng `npx wrangler whoami`.
- [x] Người dùng đăng nhập Supabase: `! supabase login`. Tạo hoặc chọn một project ở gói miễn phí; ghi project ref và URL. Khoá service role chỉ giữ trong trình quản lý secret, không ghi vào file nào trong repo.
- [x] Cài XcodeGen: `brew install xcodegen`.
- [x] Người dùng đăng nhập Apple ID trong Xcode (Settings → Accounts) và lấy Team ID của Personal Team (10 ký tự). Team ID: `22LZWPB3XL`.
- [x] Tra tài liệu hạn mức hiện hành của Cloudflare Workers gói miễn phí và ghi vào `reports/limits.md`, mỗi dòng kèm URL nguồn và ngày tra:
  - CPU mỗi request, và CPU khởi động Wasm có bị tính hay không.
  - Dung lượng Worker tối đa sau nén.
  - Số Cron Trigger và nhịp tối thiểu.

## Verification

- `rustup target list --installed | grep wasm32-unknown-unknown`
- `command -v worker-build xcodegen`
- `npx wrangler whoami` in ra tài khoản.
- `supabase projects list` có project dùng cho os-widget.
- `reports/limits.md` có đủ ba mục, mỗi mục có URL nguồn.

## Risk Assessment

- Người dùng chưa có tài khoản Cloudflare, Supabase hoặc Apple ID: dừng và hỏi (điều kiện dừng của plan).
- Hạn mức dung lượng trong tài liệu khác với giả định khoảng 3 MB: dùng con số trong tài liệu làm ngưỡng ở Phase 5.
