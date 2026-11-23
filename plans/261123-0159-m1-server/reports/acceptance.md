# Báo cáo nghiệm thu Giai đoạn 1: Server

- Ngày chạy: 2026-11-23, khoảng 11:51 (Asia/Saigon).
- Worker: https://os-widget.longdaobk17.workers.dev. Bản deploy mã mới là version `040e4e09-2287-42a3-96ce-3d62460912b6`; version đang chạy lúc nghiệm thu là `29517735-4f6f-4ceb-bdb6-b6c714f85db9`, cùng mã nhưng đã gỡ `SPIKE_TOKEN` (nguồn: Secret Change).
- Dung lượng: 656.64 KiB chưa nén, 216.96 KiB sau gzip.
- Secret của Worker: `CLIENT_TOKEN`, `PUBLISH_TOKEN`, `SUPABASE_SERVICE_ROLE_KEY`.
- Khoá dùng cho tiêu chí 6: khoá publishable (`sb_publishable_...`) của project, đặt vào header `apikey`. Khoá anon kiểu JWT cũ đã bị tắt trên project.
- Lệnh: `scripts/acceptance-server.sh https://os-widget.longdaobk17.workers.dev`, token lấy từ macOS Keychain, khoá lấy bằng `supabase projects api-keys`. Không token hay khoá nào xuất hiện trong đầu ra.
- Kết quả: sáu tiêu chí và hai kiểm tra thêm đều `PASS`, mã thoát 0. Mọi mục thử đã được `DELETE` ở cuối (204).

## Đầu ra

```text
run acceptance-20261123T115130-11737 against https://os-widget.longdaobk17.workers.dev
starting at seq 332
PASS 1 CLI publish bd6ead04-dd51-4419-ac59-e446c2e7f0f1 appears in GET /events as item.created with its item
PASS 2 invalid envelopes: no title -> 400 {"field":"","message":"missing field `title`"}; vocab without definition -> 400 {"field":"body.meanings[0]","message":"missing field `definition`"}; kind weather -> 400 {"field":"kind","message":"unknown kind `weather`, expected one of notification, vocab, generic"}
PASS 3 dedupe: first 201, second 200, same id 6907691a-08b0-424c-9ae6-38741c8b7a94, one item.created
PASS 4 read/unread/delete on 71840287-ed98-425e-88ef-0f4543ef95f7: 204 with item.read, item.unread, item.deleted; repeats add no event; PATCH after delete 404
PASS 5 tokens: none -> 401, client token on POST /items -> 403, publish token on GET /events -> 403, wrong token -> 401
PASS 6 anon key: events -> 200 array, items -> 401 no rows, rpc/purge_old_rows -> 401 rejected
PASS limit: since=0&limit=500 -> 200 with 24 events (max 100), limit=0 -> 400
PASS default ttl: expires_at - created_at = 604800s (7 days = 604800s)
checks failed: 0
cleanup: DELETE /items/bd6ead04-dd51-4419-ac59-e446c2e7f0f1 -> 204
cleanup: DELETE /items/6907691a-08b0-424c-9ae6-38741c8b7a94 -> 204
cleanup: DELETE /items/71840287-ed98-425e-88ef-0f4543ef95f7 -> 204
cleanup: DELETE /items/75c2bf88-68f7-491d-aef5-35ce1505a577 -> 204
exit 0
```

## Ghi chú

- Kiểm tra `limit=500` chỉ thấy 24 sự kiện vì nhật ký trên project hiện ngắn hơn 100 sự kiện (sự kiện cũ nhất còn lại có `seq` 315); điều kiện "tối đa 100" đúng nhưng việc hạ về 100 được chứng minh bằng unit test `limit_above_100_is_capped` của Worker, không phải bằng lần chạy này.
- Script đã chạy hai lần liên tiếp với cùng kết quả; lần đầu (run `acceptance-20261123T115021`) cũng 0 lỗi. Đầu ra ở trên là lần thứ hai, có ghi mã thoát.
