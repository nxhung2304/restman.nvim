## **Status:**
- Review: Pending
- PR: Todo

## Metadata
- **Title:** Health check — `:checkhealth courier`
- **Phase:** 7 — Diagnostics
- **GitHub Issue:** (to be filled after sync)

---

## Description
Module health cho `vim.health` API. Report trạng thái plugin, dependencies, env load, telescope availability.

- **Check items:**
  1. **Neovim version:** ≥ 0.10 required → OK / WARN nếu cũ.
  2. **curl CLI:** `vim.fn.executable("curl")` + `curl --version` → OK / FAIL (plugin sẽ không work).
  3. **env loaded:** env file path, active env name, base_url, variables count → OK / MISSING.
  4. **Telescope:** `pcall(require, "telescope")` → OK / MISSING (not blocker, chỉ info).
  5. **history file:** path, entry count, file size → OK / MISSING.
  6. **Rails project:** `config/routes.rb` tồn tại / không → INFO.
- **API:**
  - `check()` register với `vim.health` → `:checkhealth courier` gọi.
- **Report format:**

```
courier.nvim

- Neovim version: OK ✅
  - nvim 0.10.0
- curl CLI: OK ✅
  - curl 8.5.0
- Environment: MISSING ⚠️
  - No .env.json found at /path/to/.git/../.env.json
- Telescope: MISSING ℹ️
  - Telescope not found. Fallback to vim.ui.select.
- History: OK ✅
  - 42 entries, 8.4 KB
- Rails project: ℹ️
  - Not a Rails project (config/routes.rb not found)
```

- **WARN** khi version thấp hoặc env không load nhưng plugin vẫn work (degraded).
- **FAIL** chỉ khi curl thiếu — plugin không thể gửi request.

---

## Spec Reference
- Section: §5 error handling, §3.1 env missing behavior, §7.2 Telescope optional, DoD Chất lượng (check health) trong [`story.md`](../story.md).

---

## Acceptance Criteria
- [ ] `:checkhealth courier` hiển thị 6 section đúng format.
- [ ] Neovim 0.9.x → WARN.
- [ ] curl không có → FAIL (icon `✗`).
- [ ] Telescope có → OK, không → INFO (`ℹ️`).
- [ ] env file không tồn tại → MISSING (`⚠️`).
- [ ] history file trống → 0 entries, 0 B.
- [ ] Rails project check correct.

---

## Implementation Checklist
- [ ] `lua/courier/health.lua` — export `check()`.
- [ ] Gọi `vim.health.report_start("courier.nvim")`.
- [ ] Các check: `vim.version.parse`, `vim.fn.executable`, `vim.loop.fs_stat`.
- [ ] Format helper: `vim.health.report_ok`, `report_warn`, `report_error`, `report_info`.
- [ ] Wire vào `plugin/courier.lua` — `vim.api.nvim_create_autocmd("FileType", { pattern = "courier-health", callback = ... })` hoặc cách đơn giản hơn: gọi `vim.schedule`.

---

## Notes
- Depends on: 008 (env), 012 (Telescope check), 014 (history file path).
- Zero dependency trên các module khác (có thể import trực tiếp).
