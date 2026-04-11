## **Status:**
- Review: Pending
- PR: Todo

## Metadata
- **Title:** Parser — `@courier.*` comment directives
- **Phase:** 1 — Parser core
- **GitHub Issue:** (to be filled after sync)

---

## Description
Parser đọc comment block **liền kề phía trên** dòng request, trích directive:

- `@courier.body` — JSON body (có thể multiline).
- `@courier.header Key: Value` — thêm header (merge vào env headers, override nếu trùng key).
- `@courier.query key=value` — query string param.
- `@courier.form key=value` — form-urlencoded param.

**Quy tắc scan:**
- Bắt đầu từ `line - 1`, đi lên.
- Dừng khi gặp: blank line, line không phải comment, hoặc đã đi quá 20 dòng (hard limit).
- Hỗ trợ comment prefix: `//`, `#`, `--`, `/*...*/` (block comment Lua/C).
- Multi-line `@courier.body`: các dòng comment tiếp theo không có directive mới sẽ được join vào body đang mở, cho tới khi parse được JSON hợp lệ hoặc gặp directive khác.

---

## Spec Reference
- Section: §2.3 Body & Headers — Nguồn dữ liệu trong [`story.md`](../story.md).
- UX scenario: #4 (directive bị visual override), #5 multiline `@courier.body` trong [`v1-usage.md`](../example/v1-usage.md).

---

## Acceptance Criteria
- [ ] Single-line body: `-- @courier.body { "name": "Alice" }` → `body = { name = "Alice" }`.
- [ ] Multi-line body gộp đúng cho scenario 5 trong v1-usage.md.
- [ ] `-- @courier.header X-Trace-Id: abc` → `headers = { ["X-Trace-Id"] = "abc" }`.
- [ ] `@courier.query page=2` và `@courier.query size=10` → `query = { page="2", size="10" }`.
- [ ] `@courier.form name=Alice` → `form = { name="Alice" }` (dùng cho POST form-urlencoded).
- [ ] Directive không namespace (`@body`, `@header`) bị ignore.
- [ ] Stop đúng khi gặp blank line.
- [ ] Dùng `vim.json.decode` (không `vim.fn.json_decode`).

---

## Implementation Checklist
- [ ] `lua/courier/parser/directives.lua` — function `scan_above(bufnr, line)` return `{ body?, headers?, query?, form? }`.
- [ ] Comment-prefix detection: strip `//|#|--|/\*|\*` khỏi đầu line.
- [ ] Multi-line body: progressive parse (try decode, nếu fail → accumulate next line).
- [ ] Unit test multiline body với scenario #5.

---

## Notes
- Phải work với bất kỳ file type nào (JS comment `//`, Ruby/Python `#`, Lua `--`, C block `/* */`).
- Body parse error (JSON invalid) → log warn, return `body = nil` và để source khác (prompt) lo.
