## **Status:**
- Review: Approved
- PR: Approved

## Metadata
- **Title:** Commands & keymaps — `:Restman` subcommand dispatcher
- **Phase:** 4 — Wiring
- **GitHub Issue:** #13

---

## Description
Wire toàn bộ các module thành UX user-facing. Đăng ký `:Restman` command duy nhất với subcommand, tab-completion, và default keymaps.

- **Command:** `nvim_create_user_command("Courier", dispatch, { nargs = "*", complete = complete_fn, range = true })`.
- **Subcommands:**
  - `send` — parse current line (visual selection nếu có range) → env apply → http_client.send → on complete → buffer.create → view.open(bufnr, config.response.default_view). Default view = `"float"`.
  - `repeat` — re-send request gần nhất (state RAM).
  - `env` — `picker.pick(env.list(), ..., on_select = env.set_active)`.
  - `history` — mở history picker (issue 014 sẽ inject handler).
  - `cancel` — `http_client.cancel()`.
  - `rails` / `rails refresh` — (issue 015 inject).
  - `health` — gọi `vim.cmd("checkhealth restman")`.
- **Tab-completion:** return list subcommand nếu đang gõ arg đầu, list sub-sub (`refresh`) nếu đang ở arg 2 và arg 1 = `rails`.
- **Range support cho `send`:** nếu user `V` chọn block rồi `:Restman send` → pass visual block vào parser dispatcher.
- **Default keymaps** (config được override, set qua `setup`):
  - `<leader>rs` → `:Restman send` (normal + visual mode).
  - `<leader>rr` → `:Restman repeat`.
  - `<leader>re` → `:Restman env`.
  - `<leader>rh` → `:Restman history`.
  - `<leader>rc` → `:Restman cancel`.
- **Approved guard:** nếu `http_client.is_pending()` khi user gọi `send` → `vim.ui.input` prompt `"Cancel previous request? [y/N]"`.
- **Last request state:** module-level `M._last = { request }`, update sau mỗi send thành công, dùng cho `repeat`.

---

## Spec Reference
- Section: §1 (commands + keymaps), §5 (cancel + pending guard), §4.5 (view default rule) trong [`story.md`](../story.md).
- UX scenario: toàn bộ — đây là glue layer trong [`v1-usage.md`](../example/v1-usage.md).

---

## Acceptance Criteria
- [ ] `:Restman <Tab>` gợi ý: `send repeat env history cancel rails health`.
- [ ] `:Restman rails <Tab>` gợi ý: `refresh`.
- [ ] `:Restman send` trên dòng cURL → float hiện response.
- [ ] `V` + `:Restman send` → body lấy từ visual (scenario #4).
- [ ] `<leader>rs` default hoạt động.
- [ ] `<leader>rc` khi có pending → hủy, notify.
- [ ] `<leader>rs` lần 2 khi pending → prompt cancel.
- [ ] `:Restman repeat` gửi lại đúng request gần nhất sau khi restart không work (`_last` RAM-only) — OK theo spec.
- [ ] `:Restman health` mở checkhealth.
- [ ] Chỉ có 1 top-level command `:Restman` (không có `:RestmanSend`, ...).

---

## Implementation Checklist
- [ ] `lua/restman/init.lua` mở rộng — `setup()` gọi `commands.register()`, `keymaps.register(config)`.
- [ ] `lua/restman/commands.lua` — dispatch + complete.
- [ ] Keymap registration helper.
- [ ] Wire `send` flow: parse → env → http_client → buffer → view.
- [ ] Approved guard prompt.

---

## Notes
- Depends on: 006 (parser dispatcher), 007 (http_client), 008 (env), 009 (buffer), 010 (render), 011 (view), 012 (picker).
- History, rails handler để issue 014/015 wire vào (stub ở đây nếu module chưa có).
