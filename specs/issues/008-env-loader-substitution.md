## **Status:**
- Review: Approved
- PR: Approved

## Metadata
- **Title:** Env loader — `.env.json` + `{{VAR}}` substitution
- **Phase:** 2 — Execution
- **GitHub Issue:** #8

---

## Description
Module quản lý environment: load `.env.json`, pick active env, substitute variables, merge headers/base_url vào request.

- **Project root detection:** đi lên từ `vim.fn.expand("%:p:h")` cho tới khi gặp `.git/` hoặc `/`.
- **Load:** `vim.json.decode(vim.fn.readfile(...))`. Lazy, cache trong module, `reload()` để ép re-read.
- **Active env:** state module-level, khởi tạo từ `default` trong file. `:Restman env` đổi active.
- **Variable substitution:**
  - `{{VAR_NAME}}` → lookup `environments[active].variables.VAR_NAME`.
  - `{{$env.VAR}}` → `vim.env.VAR` hoặc `os.getenv("VAR")`.
  - Substitute trong: `url`, `headers` (cả key và value), `body` (string), `query`, `form`.
  - Unknown variable → giữ nguyên `{{VAR}}` + log warn (không throw).
- **Base URL merge:** nếu `request.url` là relative (`/...`) → prepend `env.base_url`. Nếu env rỗng + relative URL → prompt user nhập 1 base URL (cache session).
- **Header merge:** env headers merge vào request headers, request headers override (trùng key).
- **Error handling** (§3.1 table): file không tồn tại / parse lỗi / default trỏ sai → log + fallback env rỗng, không crash.

---

## Spec Reference
- Section: §3 Environment & Smart Defaults (đặc biệt bảng error handling) trong [`story.md`](../story.md).
- UX scenario: #2 relative URL + substitution, #8 (timeout không liên quan env nhưng check fallback) trong [`v1-usage.md`](../example/v1-usage.md).

---

## Acceptance Criteria
- [ ] Load `.env.json` đúng bằng `vim.json.decode`, reject `vim.fn.json_decode`.
- [ ] `{{USER_ID}}` → `"42"` khi env active là `local`.
- [ ] `{{$env.HOME}}` → value của `$HOME`.
- [ ] Relative `/api/users` + env `local` → `http://localhost:3000/api/users`.
- [ ] File `.env.json` không tồn tại → notify INFO 1 lần, `apply_to(request)` trả request nguyên vẹn (no merge).
- [ ] File JSON lỗi → notify ERROR, không crash.
- [ ] `default` trỏ tới env không tồn tại → ERROR + fallback.
- [ ] `set_active(name)` persist qua `:Restman env`, ảnh hưởng toàn Neovim (global).
- [ ] `reload()` re-read file trên disk.

---

## Implementation Checklist
- [ ] `lua/restman/env.lua` — export `apply_to(request)`, `set_active(name)`, `get_active()`, `list()`, `reload()`.
- [ ] Project root search helper.
- [ ] Substitute helper `gsub_vars(str, env_active)`.
- [ ] Deep substitute cho table (headers, query, form, body-if-string).
- [ ] Session cache cho prompted base_url.

---

## Notes
- **Body JSON substitute note:** nếu body là parsed table (từ directive), substitute recursive vào từng string value. Nếu body là raw string → simple gsub.
- Depends on: 001 (scaffold), 006 (parser dispatcher trả request object).
