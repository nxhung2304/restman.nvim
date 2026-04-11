## **Status:**
- Review: Approved
- PR: Approved

## Metadata
- **Title:** Parser — HTTP-style prefix (`GET https://...`)
- **Phase:** 1 — Parser core
- **GitHub Issue:** #2

---

## Description
Parser nhận diện pattern `METHOD URL` — token đầu dòng là HTTP verb, phần còn lại là URL (absolute hoặc relative).

- Support tất cả 9 methods: GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS/CONNECT/TRACE.
- URL có thể absolute (`http(s)://...`) hoặc relative (`/api/...`) — relative sẽ được env layer ghép base_url sau.
- URL có thể nằm trong quote (`"..."`, `'...'`) hoặc trần.
- Bỏ qua line comment thuần (không match pattern này), **nhưng** dòng comment chứa pattern `METHOD URL` vẫn được parse (xem scenario 2 — explicit pattern thắng quy tắc skip comment).
- Trả về struct: `{ method, url, headers = {}, body = nil, source = { file, line } }`.

---

## Spec Reference
- Section: §2.1 bảng pattern (row 2), §2.2 quy tắc parse URL trong [`story.md`](../story.md).
- UX scenario: #2 relative URL + env substitution, #5 POST với directive body trong [`v1-usage.md`](../example/v1-usage.md).

---

## Acceptance Criteria
- [ ] `GET https://api.com/users` → `{ method="GET", url="https://api.com/users" }`.
- [ ] `POST /users` → `{ method="POST", url="/users" }` (relative giữ nguyên).
- [ ] `delete '/api/x'` (lowercase + quote) → `{ method="DELETE", url="/api/x" }`.
- [ ] `# GET /api/v1/users/42` (dòng comment) → vẫn parse ra được.
- [ ] Dòng không có verb hợp lệ → return `nil` (không throw).
- [ ] `source.line` là 1-indexed.

---

## Implementation Checklist
- [ ] `lua/restman/parser/http.lua` — function `parse(line, line_number, file_path)`.
- [ ] Regex/gmatch cho 9 methods.
- [ ] Strip quote nếu URL bọc quote.
- [ ] Unit test (manual hoặc `plenary.busted` nếu có) các case trên.

---

## Notes
- Không resolve env variable ở issue này (để `env.lua` làm).
- Không prompt path param ở issue này (để `parser/init.lua` làm).
