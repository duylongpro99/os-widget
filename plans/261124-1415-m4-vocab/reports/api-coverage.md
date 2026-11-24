# Độ phủ trường của Free Dictionary API trên 20 từ mẫu

Ngày đo: 2026-11-24 (Asia/Saigon), trong lúc viết plan M4. Nguồn: `GET https://api.dictionaryapi.dev/api/v2/entries/en/<word>`, 20 request chỉ đọc, tuần tự, cách nhau 0,4 giây, header `User-Agent: vocab-coverage-check`. Đầu ra thô của từng từ nằm ở [api-samples/](api-samples/) và được dùng làm fixture cho Phase 5.

## Từ mẫu

18 từ thuộc loại đáng học (`serendipity`, `ephemeral`, `ubiquitous`, `meticulous`, `resilient`, `candid`, `benevolent`, `eloquent`, `mitigate`, `ambiguous`, `pragmatic`, `scrutinize`, `tenacious`, `vindicate`, `lucid`, `ostentatious`, `quintessential`, `garrulous`) và 2 dạng biến tố như khi tách từ sách (`wandered`, `lanterns`).

## Kết quả

Cả 20 request trả 200, mỗi từ một entry.

| Trường envelope | Lấy từ API | Số từ có | Ghi chú |
|---|---|---|---|
| `word` | `word` | 20/20 | API trả đúng dạng đã hỏi, kể cả `wandered`, `lanterns`. |
| `ipa` | `phonetic`, nếu rỗng thì `phonetics[].text` đầu tiên khác rỗng | 17/20 | `phonetic` ở gốc chỉ có 14/20; lấy thêm từ `phonetics[]` được 3 từ. Thiếu: `resilient`, `vindicate`, `lanterns`. |
| `pos` | `meanings[].partOfSpeech` | 20/20 | Nghĩa đầu tiên thường không phải nghĩa chính: `candid`, `lucid`, `ephemeral` có `noun` 1 định nghĩa trước `adjective` 3 định nghĩa. Plan chọn nhóm nghĩa có nhiều định nghĩa nhất. |
| `meanings[].definition` | `definitions[].definition` | 20/20 | |
| `meanings[].examples` | `definitions[].example` | 9/20 | Tuỳ chọn trong envelope. |
| `synonyms` | `meanings[].synonyms` và `definitions[].synonyms` | 14/20 | |
| `antonyms` | như trên | 8/20 | |
| `audio_url` | `phonetics[].audio` khác rỗng | 15/20 | Cả 15 đều là `https://api.dictionaryapi.dev/media/pronunciations/en/<word>-<uk|us|au>.mp3`. `resilient` có audio nhưng không có IPA. |
| `context` | Không có | 0/20 | API không cung cấp câu ngữ cảnh; chỉ sách cung cấp (Phase 6). |

**Đủ trường bắt buộc** (`word`, `ipa`, `pos`, ít nhất một `definition`): 17/20 (85%). Ba từ còn lại bị bỏ khi nạp theo quy tắc "từ không bổ sung đủ trường bắt buộc thì không được nạp" (architecture §4.4).

## Hệ quả cho plan

- API đủ dùng làm nguồn đầu tiên (quyết định D4 của operator); khoảng 15% từ sẽ bị bỏ vì thiếu IPA.
- Dạng biến tố tra được trực tiếp, nên nạp từ sách không cần bước đưa về dạng gốc ở bản đầu.
- `audio_url` có ở 75% từ; bộ đọc của hệ thống là đường phát âm dự phòng bắt buộc (architecture §6).
- Dữ liệu API lấy từ Wiktionary theo giấy phép CC BY-SA; dùng cá nhân, không phân phối lại, nên chỉ ghi `origin` là `dictionaryapi.dev`.
