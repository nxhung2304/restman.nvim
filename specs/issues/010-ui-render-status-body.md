## **Status:**
- Review: Approved
- PR: Draft

## Metadata
- **Title:** UI — Render status/headers/body + syntax highlight
- **Phase:** 3 — UI
- **GitHub Issue:** #10

---

## Description
Render response vào một bufnr đã tạo sẵn. Định dạng theo mock trong §4.3:

```
POST https://api.com/users
201 Created   •   142ms   •   1.2 KB
──────────────────────────────
[H] Headers (3)   [B] Body   [R] Raw

<body content>
```

- **Status line color:** dùng `nvim_buf_add_highlight` hoặc extmark, class-based:
  - 2xx → `DiagnosticOk` / link custom `RestmanOk` green.
  - 3xx → `WarningMsg` yellow.
  - 4xx/5xx → `ErrorMsg` red.
- **Body prettify + highlight:**
  - JSON → `vim.json.decode` + `vim.inspect` hoặc custom pretty; set `filetype=json` cho buffer → treesitter tự highlight.
  - HTML → `filetype=html`.
  - XML → `filetype=xml`.
  - plain/unknown → không highlight.
- **Toggle states** (lưu trong buffer var `b:restman_view_mode`):
  - Body view (default) — chỉ body.
  - Headers expanded — hiện headers block phía trên body.
  - Raw — dump raw response (trước khi prettify).
- **Size format:** `format_bytes(n)` → `"256 B"`, `"1.2 KB"`, `"3.4 MB"`.
- **Error response render:** nếu `response.error = { kind, message }` → format:
  ```
  GET http://...
  ❌ Network error: timeout after 30000ms
  
  Hint: ...
  ```
  Không có body block.

---

## Spec Reference
- Section: §4.3 Nội dung hiển thị, §4.4 keymap (chỉ làm hiển thị, keymap để issue 011 wire), §5 error handling trong [`story.md`](../story.md).
- UX scenario: #1 render JSON, #8 error rendering trong [`v1-usage.md`](../example/v1-usage.md).

---

## Acceptance Criteria
- [ ] `render(bufnr, request, response)` populate lines + highlights.
- [ ] Status 201 hiện xanh, 404 hiện đỏ, 301 vàng.
- [ ] JSON body được pretty-print (2-space indent) + filetype=json.
- [ ] HTML body có filetype=html.
- [ ] Toggle `mode='raw'` → thay nội dung = raw string từ `response.raw`.
- [ ] Error response render theo format có emoji + hint, không có body block.
- [ ] `render` có thể gọi lại nhiều lần trên cùng bufnr (đổi toggle không leak extmark).

---

## Implementation Checklist
- [ ] `lua/restman/ui/render.lua` — `render(bufnr, req, res, opts)`.
- [ ] Helper `format_status(code)` → `{ text, hl_group }`.
- [ ] Helper `format_bytes(n)`.
- [ ] Helper `prettify(body, content_type)`.
- [ ] Clear extmark namespace trước khi re-render (`nvim_buf_clear_namespace`).
- [ ] Set `vim.bo[bufnr].filetype` theo content type.

---

## Notes
- Depends on: 009 (buffer layer provide bufnr).
- Treesitter parser cho JSON/HTML là built-in Neovim 0.10 — không cần install thêm.
