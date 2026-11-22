---
title: "Lập plan M0: kiểm chứng Worker Rust"
date: 2026-11-22
summary: "Tạo plan 6 phase cho Giai đoạn 0: chỉ thử nghiệm D chặn Giai đoạn 1, A khởi động song song"
---

# Lập plan M0: kiểm chứng Worker Rust

## What happened
Phiên `m0-advise` dùng ak-advise rà Giai đoạn 0 của `docs/roadmap.md`, sau đó tạo plan `plans/261122-0754-m0-kiem-chung-worker-rust` (6 phase, `ak plan validate` OK).

## Decision
- Chỉ thử nghiệm D (Worker Rust với Supabase) chặn Giai đoạn 1. A và B chặn Giai đoạn 2/3; C chặn Giai đoạn 2.
- Mã của D viết luôn thành khung Giai đoạn 1 (Cargo workspace có crate `envelope` và `worker`), không phải mã bỏ đi.
- Ngưỡng đạt của D: CPU p99 ≤ 5 ms ở cả hai endpoint và dung lượng gói Wasm sau nén trong hạn mức miễn phí; trượt thì chuyển Worker sang TypeScript, giữ nguyên API và schema.
- A và C gộp vào một app thử nghiệm (`spikes/widget-probe`, dựng bằng XcodeGen), cài từ ngày 1 để đồng hồ 7 ngày chạy sớm.

## Next steps
- Phase 1: chuẩn bị công cụ (target wasm32, worker-build, xcodegen), đăng nhập Cloudflare, Supabase, Apple ID; tra hạn mức Workers gói miễn phí.
- Ngày 8 sau khi cài app A: kiểm tra A và C.

> Historical work record — not durable authority. Prefer docs/specs/ADRs for current decisions.
