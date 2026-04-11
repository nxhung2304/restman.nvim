## **Status:**
- Review: Approved
- PR: Approved

## Metadata
- **Title:** Parser dispatcher + dynamic path params
- **Phase:** 1 — Parser core
- **GitHub Issue:** #6

---

## Description
Entry point của parser. Nhận `bufnr + cursor_line`, chạy thứ tự các sub-parsers (cURL → HTTP-style → DSL), combine với directives, handle dynamic path params.

- **Dispatch rule:** thử cURL trước (vì có block context), sau đó HTTP-style, cuối DSL. Parser đầu tiên return non-nil thắng.
- **Body precedence** (§2.3): visual selection > directive > prompt. Dispatcher nhận optional `visual_block` arg.
- **Dynamic params:**
  - Detect `:name`, `{name}`, `<name>` trong URL → prompt từng biến qua `vim.ui.input`.
  - **Session cache:** key = `file_path .. ":" .. param_name`, pre-fill prompt với value trước đó.
  - Template literal `${var}`, `#{var}` không resolve được → prompt.
- Nếu thiếu method hoàn toàn (chỉ có URL thô trong string) → prompt `vim.ui.select` với 9 methods. **Không default GET.**
- Trả về final request object: `{ method, url, headers, body, query, form, source }` — ready for http_client.

---

## Spec Reference
- Section: §2 toàn phần (rules), đặc biệt §2.2 dynamic params + §2.3 body precedence trong [`story.md`](../story.md).
- UX scenario: #3 path param prompt + session cache trong [`v1-usage.md`](../example/v1-usage.md).

---

## Acceptance Criteria
- [ ] `parse_current_line(bufnr, line)` return request object hoặc `nil`.
- [ ] Thứ tự dispatch đúng: cURL > HTTP-style > DSL.
- [ ] Body precedence: có visual → visual win; không visual + có directive → directive; không có gì + method POST → prompt.
- [ ] `/users/:id` → prompt 1 lần, cache; lần 2 cùng file cùng biến → pre-fill.
- [ ] URL trong string literal không có method → prompt method (có 9 option) + không silent default GET.
- [ ] Comment thường (không match pattern nào) → return `nil` (xem scenario 2 note: dòng comment chứa explicit pattern VẪN parse được, đó là nhiệm vụ của parser con).

---

## Implementation Checklist
- [ ] `lua/restman/parser/init.lua` — export `parse_current_line(bufnr, line, opts)`.
- [ ] Collect block lines cho cURL (join `\` continuations).
- [ ] Call các sub-parser, pick first non-nil.
- [ ] Merge với `directives.scan_above(...)`.
- [ ] Handle visual selection nếu `opts.visual_block`.
- [ ] Dynamic params: regex `:(%w+)`, `{(%w+)}`, `<(%w+)>` → loop `vim.ui.input`.
- [ ] Session cache: module-level table `M._param_cache[key]`.

---

## Notes
- Depends on: 002 (http), 003 (curl), 004 (dsl), 005 (directives).
- Env substitution (`{{VAR}}`) KHÔNG làm ở đây — để `env.lua`.
