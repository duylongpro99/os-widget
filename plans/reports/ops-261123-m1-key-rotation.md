# Xoay khoá secret Supabase của Worker

Ngày 2026-11-23, session `m1-server-key-rotation`, theo quyết định D4 của chủ dự án ("Xoay khoá sau khi merge").

## Kết quả

Worker `os-widget` đã chuyển sang khoá secret mới và vượt mọi kiểm tra nghiệm thu. Khoá cũ đã bị thu hồi. Không có thay đổi mã, không có commit.

| Mục | Giá trị |
|-----|---------|
| Khoá cũ đã thu hồi | `351fb2b9-bbd1-4d9f-96c7-18b874b492e1`, tên `default`, loại `secret` |
| Khoá mới | `2dd10c5a-6c73-4d29-9df4-ebd55998c250`, tên `os_widget_worker_20261123`, loại `secret` |
| Phiên bản Worker đang chạy | `49c28da1-b647-4b1b-9767-a2719c4d884a` (100%, nguồn "Secret Change", 2026-11-23T06:31:45Z), thay cho `29517735` |
| Secret của Worker | `CLIENT_TOKEN`, `PUBLISH_TOKEN`, `SUPABASE_SERVICE_ROLE_KEY` |

## Các bước đã làm

1. Liệt kê khoá bằng `supabase projects api-keys -o json`, chỉ lọc `id`, `name`, `type`. Dự án có đúng một khoá loại `secret` (`351fb2b9…`, `default`), đó là khoá Worker đang dùng.
2. Supabase CLI 2.122.0 không có lệnh tạo khoá, nên tạo khoá bằng Management API `POST /v1/projects/gykrhmpliphrcpiryzuq/api-keys?reveal=true`. Token đăng nhập đọc bằng `security` từ mục Keychain "Supabase CLI" (theo quyết định D3) và ghi vào file header `chmod 600` trong scratchpad, xoá ngay sau lệnh. Phản hồi chỉ nằm trong biến shell; giá trị khoá đi qua `jq -r .api_key | npx wrangler@4.166.0 secret put SUPABASE_SERVICE_ROLE_KEY` rồi biến bị `unset`.
   - Lần gọi đầu trả 400 và không tạo khoá: tên `os-widget-worker-20261123` trong brief không hợp lệ vì Supabase chỉ cho chữ thường, chữ số và gạch dưới. Đã đổi thành `os_widget_worker_20261123`.
3. Chạy `scripts/acceptance-server.sh https://os-widget.longdaobk17.workers.dev` với token lấy từ Keychain (`os-widget-publish-token`, `os-widget-client-token`) và khoá publishable lấy qua CLI (lọc theo `type`), không in giá trị nào.
4. Sau khi nghiệm thu đạt, xoá khoá cũ bằng `DELETE /v1/projects/gykrhmpliphrcpiryzuq/api-keys/351fb2b9-bbd1-4d9f-96c7-18b874b492e1` (200). Sau đó `GET /items` với token client trả 200; vì khoá cũ đã mất, điều này cũng xác nhận Worker dùng khoá mới.
5. Danh sách khoá cuối chỉ còn một khoá `secret`: khoá mới.

## Nghiệm thu

```text
run acceptance-20261123T133230-47787 against https://os-widget.longdaobk17.workers.dev
starting at seq 372
PASS 1 CLI publish ae22465e-47c1-43dc-add1-6545daf47f73 appears in GET /events as item.created with its item
PASS 2 invalid envelopes: no title -> 400 {"field":"","message":"missing field `title`"}; vocab without definition -> 400 {"field":"body.meanings[0]","message":"missing field `definition`"}; kind weather -> 400 {"field":"kind","message":"unknown kind `weather`, expected one of notification, vocab, generic"}
PASS 3 dedupe: first 201, second 200, same id 98cfb590-448e-43be-9ae7-7eff39d80991, one item.created
PASS 4 read/unread/delete on 2ff9823b-d9c8-4125-a44f-97ff9ed6a8fd: 204 with item.read, item.unread, item.deleted; repeats add no event; PATCH after delete 404
PASS 5 tokens: none -> 401, client token on POST /items -> 403, publish token on GET /events -> 403, wrong token -> 401
PASS 6 anon key: events -> 200 array, items -> 401 no rows, rpc/purge_old_rows -> 401 rejected
PASS limit: since=0&limit=500 -> 200 with 64 events (max 100), limit=0 -> 400
PASS default ttl: expires_at - created_at = 604800s (7 days = 604800s)
checks failed: 0
cleanup: DELETE /items/ae22465e-47c1-43dc-add1-6545daf47f73 -> 204
cleanup: DELETE /items/98cfb590-448e-43be-9ae7-7eff39d80991 -> 204
cleanup: DELETE /items/2ff9823b-d9c8-4125-a44f-97ff9ed6a8fd -> 204
cleanup: DELETE /items/fa5524a7-c0bf-45fe-a89d-99bb61de6786 -> 204
```

Mã thoát 0. Sau khi thu hồi khoá cũ: `GET /items` trả 200, tổng 0 mục, 0 mục nguồn `acceptance`.

## Danh sách khoá cuối

```text
{"id":"anon","name":"anon","type":"legacy"}
{"id":"service_role","name":"service_role","type":"legacy"}
{"id":"45f9a31c-fe8e-4374-b8e5-30cb5ce779de","name":"default","type":"publishable"}
{"id":"2dd10c5a-6c73-4d29-9df4-ebd55998c250","name":"os_widget_worker_20261123","type":"secret"}
```

Hai khoá `legacy` vẫn được API liệt kê; theo brief, khoá JWT kiểu cũ đã bị tắt trên dự án, nên không đụng tới.

## Kiểm tra cuối

- `wrangler secret list`: `CLIENT_TOKEN`, `PUBLISH_TOKEN`, `SUPABASE_SERVICE_ROLE_KEY`.
- Không còn file tạm chứa bí mật trong scratchpad; script nghiệm thu tự xoá thư mục tạm của nó.
- `git status --short` giống lúc bắt đầu, chỉ thêm báo cáo này.
- Không có tiến trình wrangler/workerd nào của session này còn chạy. Các tiến trình `wrangler dev` đang chạy thuộc dự án `cris_blog`, không đụng tới.
- Không có khoá, token hay mật khẩu nào bị in ra, kể cả một phần.

## Câu hỏi còn mở

- Không có.
