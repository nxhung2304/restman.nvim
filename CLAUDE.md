# Restman.nvim — AI Context

> Đọc file này đầu tiên mỗi session. Nó là entry point tham chiếu cho mọi quyết định.

## Project
**Restman.nvim** — Neovim plugin đóng vai trò REST client với triết lý **one-key experience, frictionless**. Đặt con trỏ trên một dòng request → bấm 1 phím → nhận kết quả trong floating window.

- **Repo folder:** `restman.nvim/`
- **Plugin name:** `restman.nvim`.
- **Lua module:** `require("restman")`.

## Current Phase
**v1.0 MVP** — đang chuẩn bị implement.

- 📘 **Spec chính:** [`specs/story.md`](./specs/story.md) — scope, architecture, DoD.
- 🎥 **UX đích đến:** [`specs/example/v1-usage.md`](./specs/example/v1-usage.md) — 8 kịch bản demo.
- ✅ **Single source of truth cho progress:** checkbox DoD trong `specs/story.md`.
- 📋 **Task list:** `specs/issues/` (generate từ spec bằng `/generate-issues`).

## Architecture Rules (bắt buộc tuân thủ)

### Neovim & dependencies
- **Neovim ≥ 0.10** (required). Check ở `setup()`, fail fast nếu thấp hơn.
- **JSON:** luôn dùng `vim.json.encode/decode`. **KHÔNG** dùng `vim.fn.json_encode/decode` (chậm + edge case khác).
- **Async:** `vim.system` là first-class. `plenary.job` chỉ fallback.
- **Telescope:** optional. Luôn `pcall(require, "telescope")` + fallback `vim.ui.select`.

### Mcp
Github: https://github.com/nxhung2304/courier.nvim

