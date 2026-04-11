# Courier.nvim — AI Context

> Đọc file này đầu tiên mỗi session. Nó là entry point tham chiếu cho mọi quyết định.

## Project
**Courier.nvim** — Neovim plugin đóng vai trò REST client với triết lý **one-key experience, frictionless**. Đặt con trỏ trên một dòng request → bấm 1 phím → nhận kết quả trong floating window.

- **Repo folder (hiện tại):** `postman.nvim/` — sẽ rename thành `courier.nvim/` trước khi publish.
- **Plugin name:** `courier.nvim` (đổi từ `postman.nvim` để tránh trademark của Postman Inc.).
- **Lua module:** `require("courier")`.

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

### Design principles
- **Explicit > Magic:** parser yêu cầu user viết đủ METHOD + URL. Không auto-default `GET`.
- **One command gốc:** `:Courier` với subcommand (`send`, `repeat`, `env`, `history`, `cancel`, `rails`, `health`). Không tạo nhiều top-level command.
- **Directive namespace:** `@courier.body`, `@courier.header`, `@courier.query`, `@courier.form` (tránh đụng JSDoc/YARD/phpDoc).
- **Buffer layer tách Window layer** cho response viewer: response ghi vào scratch buffer `courier://response/<n>`, view (float/split/vsplit/tab) chỉ là viewport.
- **Float là default view** cho `:Courier send`; split là default cho `:Courier history`.

### Out of scope v1.0
- ❌ SDK parsing (`axios.post`, `fetch`, `http.Get`) — dời v1.1, cần treesitter.
- ❌ Assertion testing, OpenAPI import, GraphQL, WebSocket — v2.0.

## Module Layout

```
lua/courier/
├── init.lua           -- setup(), expose API
├── config.lua         -- default + user config merge
├── parser/
│   ├── init.lua       -- entry: parse_current_line()
│   ├── curl.lua       -- raw cURL
│   ├── http.lua       -- "GET https://..." style
│   ├── dsl.lua        -- Rails/Sinatra/Express route DSL
│   └── directives.lua -- @courier.* comment directives
├── http_client.lua    -- vim.system + curl wrapper, cancel
├── env.lua            -- load .env.json, substitute {{VAR}}
├── ui/
│   ├── buffer.lua     -- scratch buffer layer + LRU
│   ├── render.lua     -- status/headers/body rendering
│   ├── view.lua       -- float|split|vsplit|tab, promote
│   └── picker.lua     -- Telescope | vim.ui.select abstraction
├── history.lua        -- persist, query, jump-to-source
├── integrations/
│   └── rails.lua      -- rails routes parser + cache
└── log.lua            -- vim.notify wrapper
```

## Key Conventions
- **History file:** `vim.fn.stdpath("data") .. "/courier/history.json"`, max 100 entries LRU.
- **Rails cache:** `.cache/courier/rails_routes.txt` (project root).
- **Response buffer:** max 10 buffer, LRU wipe.
- **User-Agent:** `courier.nvim/1.0`.
- **Timeout default:** 30s.

## Commands to Run
```sh
# Test (khi có test suite)
make test

# Lint
stylua lua/ tests/

# Check plugin health
:checkhealth courier
```

## Workflow AI

Khi user yêu cầu "làm task tiếp theo" hoặc "implement issue X":

1. **Đọc spec section liên quan** trong `specs/story.md` (section được tham chiếu bởi issue).
2. **Đọc kịch bản UX tương ứng** trong `specs/example/v1-usage.md` để hiểu hành vi đích.
3. **Check dependency:** các module trong `lua/courier/` mà task này phụ thuộc đã có chưa.
4. **Implement** theo Architecture Rules ở trên.
5. **Test** nếu có test framework, hoặc describe manual test case.
6. **Tick checkbox DoD** tương ứng trong `specs/story.md`.
7. **Update issue** (local file hoặc GitHub issue) — đánh dấu done.

Khi user hỏi "task nào tiếp theo":
1. Scan `specs/issues/` (hoặc `gh issue list`) để lấy list task chưa done.
2. Check thứ tự implement đề xuất ở cuối `specs/story.md` (§Next Step).
3. Lọc các task không bị block bởi dependency.
4. Đề xuất task đầu tiên trong danh sách đã lọc.

## Git / GitHub
- **Active GitHub account:** `nguyenxuanhung-rightsvn` (check lại bằng `gh auth status` nếu nghi ngờ).
- **MCP GitHub server:** có available (`mcp__github__*`). Ưu tiên MCP cho việc tạo/query issue, PR. Dùng `gh` CLI khi MCP không đủ.
- **Branch:** `main` (hoặc `master` nếu repo đã có sẵn).
- **Không tự push/tạo PR** khi chưa được user yêu cầu rõ ràng.

## Decision Log (các quyết định quan trọng đã chốt)
1. **Tên plugin:** `courier.nvim` (không dùng `postman` vì trademark, chọn `courier` vì giữ metaphor "người đưa tin").
2. **Command style:** subcommand pattern `:Courier <action>`, không dùng `:CourierAction` CamelCase.
3. **Response viewer:** float-first, promotable sang split/vsplit/tab bằng `s`/`v`/`t` trong buffer.
4. **Parser scope v1.0:** 4 pattern (cURL, HTTP-style, Framework DSL, URL thô prompt method). SDK parsing dời v1.1.
5. **Directive namespace:** `@courier.*` để tránh đụng JSDoc/YARD.
6. **History metadata:** bao gồm `file` + `line` để jump-back-to-source từ picker.
