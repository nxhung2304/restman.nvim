## **Status:**
- Review: Pending
- PR: Todo

## Metadata
- **Title:** Parser — Framework route DSL (Rails/Sinatra/Express)
- **Phase:** 1 — Parser core
- **GitHub Issue:** (to be filled after sync)

---

## Description
Parser nhận diện route DSL patterns:

- **Rails/Sinatra:** `get '/users'`, `post '/login'`, `delete "/items/:id"`.
- **Express:** `router.get('/x')`, `app.post('/y')`, `router.delete("/z")`.

Rule: method lấy từ tên hàm (lowercase). URL là string literal đầu tiên sau hàm (first arg), bọc trong `'...'`, `"..."` hoặc `` `...` ``.

- Trả về struct giống http parser: `{ method, url, source }`.
- URL nếu không absolute → để env layer ghép base_url.

---

## Spec Reference
- Section: §2.1 bảng pattern (row 3) trong [`story.md`](../story.md).
- UX scenario: #3 path param prompt, #6 rails routes picker (cùng kiểu string literal) trong [`v1-usage.md`](../example/v1-usage.md).

---

## Acceptance Criteria
- [ ] `get '/articles/:slug/comments/:comment_id'` → `{ method="GET", url="/articles/:slug/comments/:comment_id" }`.
- [ ] `post '/login'` → method `POST`.
- [ ] `router.delete('/items/:id')` → method `DELETE`.
- [ ] `app.patch("/users/:id")` → method `PATCH`.
- [ ] Case không match (ví dụ `get_user('/u')` — không phải verb hàm) → return `nil`.
- [ ] Đè lên case dễ lầm: `getUser(...)` → `nil`.

---

## Implementation Checklist
- [ ] `lua/courier/parser/dsl.lua` — function `parse(line, line_number, file_path)`.
- [ ] Pattern: `^%s*(get|post|put|patch|delete|head|options)%s*[%(%s]+['"`]([^'"`]+)['"`]` (điều chỉnh cho Lua pattern engine — có thể phải dùng vim.regex hoặc nhiều gmatch).
- [ ] Pattern Express: `[%w]+%.(get|post|...)%(['"`]([^'"`]+)['"`]`.
- [ ] Word boundary để tránh match `getUser`, `get_user`.
- [ ] Unit test các case acceptance.

---

## Notes
- Không parse arguments khác của function (callback, options) — chỉ method + url.
