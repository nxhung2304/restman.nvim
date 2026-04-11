## **Status:**
- Review: Approved
- PR: Approved

## Metadata
- **Title:** Parser — Raw cURL
- **Phase:** 1 — Parser core
- **GitHub Issue:** #3

---

## Description
Parser nhận diện raw cURL command và trích xuất method, URL, headers, body.

- Support flags: `-X/--request`, `-H/--header`, `-d/--data`, `-d @file.json`, `--data-raw`, `--data-binary`.
- Method rule:
  - Có `-X` → dùng value.
  - Không có `-X` nhưng có `-d` → `POST`.
  - Không có gì → `GET`.
- Multi-line cURL (dòng kết thúc bằng `\`) → join lại trước khi parse.
- URL: absolute luôn (không như HTTP-style, cURL thường dùng absolute).
- Headers: parse từng `-H "Key: Value"` thành map, support cả single quote.
- Body: lấy từ `-d`, nếu là `@file.json` → đọc file.

---

## Spec Reference
- Section: §2.1 bảng pattern (row 1) trong [`story.md`](../story.md).
- UX scenario: #1 raw cURL trong markdown note trong [`v1-usage.md`](../example/v1-usage.md).

---

## Acceptance Criteria
- [ ] `curl -X GET http://a.com/u/42 -H "Accept: application/json"` parse đúng method + url + 1 header.
- [ ] `curl http://a.com/u -d '{"k":1}'` → method = `POST`, body = `{"k":1}`.
- [ ] `curl -X PUT http://a.com/u -H "A: 1" -H "B: 2" -d @/tmp/body.json` — 2 headers, body đọc từ file.
- [ ] Multi-line cURL (backslash continuation) join đúng trước parse.
- [ ] Không phải cURL line → return `nil`.

---

## Implementation Checklist
- [ ] `lua/restman/parser/curl.lua` — function `parse(lines_block, start_line, file_path)` nhận vào một block lines để hỗ trợ multi-line.
- [ ] Helper shell-split tối thiểu (handle `"..."`, `'...'`, escaped quote).
- [ ] File-body read `-d @path` — nếu file không tồn tại → log warn, body = nil.
- [ ] Unit test từng case trên.

---

## Notes
- Parser này cần block context (multi-line). `parser/init.lua` sẽ gom các dòng liên tiếp kết thúc bằng `\` trước khi gọi.
