## **Status:**
- Review: Pending
- PR: Todo

## Metadata
- **Title:** Project scaffold & config
- **Phase:** 0 — Foundation
- **GitHub Issue:** (to be filled after sync)

---

## Description
Khởi tạo skeleton plugin courier.nvim để các module sau có chỗ drop vào.

- Tạo thư mục `lua/courier/` với các module stub (init, config, parser/, ui/, ...).
- `init.lua` expose `setup(user_config)` — merge user config với default, check Neovim ≥ 0.10 (fail fast).
- `config.lua` chứa default config: keymaps, response view, timeout, history, rails paths.
- `log.lua` wrap `vim.notify` với level (debug/info/warn/error) và prefix `[Courier]`.
- Tạo `plugin/courier.lua` entry tối thiểu (chỉ đăng ký `:Courier` command stub, để module sau wire thực sự).
- Tạo `stylua.toml` + `.gitignore` (ignore `.cache/`, `*.log`).

---

## Spec Reference
- Section: §1 One-Key Experience & Cấu hình, §🏗️ Kiến trúc Module trong [`specs/story.md`](../story.md).
- UX scenario: setup chung trong [`specs/example/v1-usage.md`](../example/v1-usage.md).

---

## Acceptance Criteria
- [ ] `require("courier").setup({})` chạy không crash trên Neovim 0.10.
- [ ] Neovim < 0.10 → `setup` notify ERROR + return sớm (không đăng ký command).
- [ ] User config được deep-merge với default (user key override, default key giữ).
- [ ] `log.info/warn/error/debug` prefix `[Courier]` và gọi đúng level của `vim.notify`.
- [ ] `stylua lua/` chạy clean.

---

## Implementation Checklist
- [ ] Tạo cây thư mục `lua/courier/**` + `plugin/courier.lua`.
- [ ] `config.lua` — default table + `merge(user)` helper.
- [ ] `init.lua` — `setup()`, version check, export module API.
- [ ] `log.lua` — wrapper `vim.notify`.
- [ ] `.gitignore`, `stylua.toml`.
- [ ] Smoke test: load plugin trong nvim, gọi `:lua require("courier").setup({})` không lỗi.

---

## Notes
- Blocker cho mọi issue khác. Phải done trước.
- Không đăng ký subcommand thật ở issue này — chỉ scaffold.
