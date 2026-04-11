## **Status:**
- Review: Pending
- PR: Todo

## Metadata
- **Title:** Commands & keymaps — `:Courier` subcommand dispatcher
- **Phase:** 4 — Wiring
- **GitHub Issue:** (to be filled after sync)

---

## Description
Wire toàn bộ các module thành UX user-facing. Đăng ký `:Courier` command duy nhất với subcommand, tab-completion, và default keymaps.

- **Command:** `nvim_create_user_command("Courier", dispatch, { nargs = "*", complete = complete_fn, range = true })`.
- **Subcommands:**
  - `send` — parse current line (visual selection nếu có range) → env apply → http_client.send → on complete → buffer.create → view.open(bufnr, config.response.default_view). Default view = `"float"`.
  - `repeat` — re-send request gần nhất (state RAM).
  - `env` — `picker.pick(env.list(), ..., on_select = env.set_active)`.
  - `history` — mở history picker (issue 014 sẽ inject handler).
  - `cancel` — `http_client.cancel()`.
  - `rails` / `rails refresh` — (issue 015 inject).
  - `health` — gọi `vim.cmd("checkhealth courier")`.
- **Tab-completion:** return list subcommand nếu đang gõ arg đầu, list sub-sub (`refresh`) nếu đang ở arg 2 và arg 1 = `rails`.
- **Range support cho `send`:** nếu user `V` chọn block rồi `:Courier send` → pass visual block vào parser dispatcher.
- **Default keymaps** (config được override, set qua `setup`):
  - `<leader>rs` → `:Courier send` (normal + visual mode).
  - `<leader>rr` → `:Courier repeat`.
  - `<leader>re` → `:Courier env`.
  - `<leader>rh` → `:Courier history`.
  - `<leader>rc` → `:Courier cancel`.
- **Pending guard:** nếu `http_client.is_pending()` khi user gọi `send` → `vim.ui.input` prompt `"Cancel previous request? [y/N]"`.
- **Last request state:** module-level `M._last = { request }`, update sau mỗi send thành công, dùng cho `repeat`.

---

## Spec Reference
- Section: §1 (commands + keymaps), §5 (cancel + pending guard), §4.5 (view default rule) trong [`story.md`](../story.md).
- UX scenario: toàn bộ — đây là glue layer trong [`v1-usage.md`](../example/v1-usage.md).

---

## Acceptance Criteria
- [ ] `:Courier <Tab>` gợi ý: `send repeat env history cancel rails health`.
- [ ] `:Courier rails <Tab>` gợi ý: `refresh`.
- [ ] `:Courier send` trên dòng cURL → float hiện response.
- [ ] `V` + `:Courier send` → body lấy từ visual (scenario #4).
- [ ] `<leader>rs` default hoạt động.
- [ ] `<leader>rc` khi có pending → hủy, notify.
- [ ] `<leader>rs` lần 2 khi pending → prompt cancel.
- [ ] `:Courier repeat` gửi lại đúng request gần nhất sau khi restart không work (`_last` RAM-only) — OK theo spec.
- [ ] `:Courier health` mở checkhealth.
- [ ] Chỉ có 1 top-level command `:Courier` (không có `:CourierSend`, ...).

---

## Implementation Checklist
- [ ] `lua/courier/init.lua` mở rộng — `setup()` gọi `commands.register()`, `keymaps.register(config)`.
- [ ] `lua/courier/commands.lua` — dispatch + complete.
- [ ] Keymap registration helper.
- [ ] Wire `send` flow: parse → env → http_client → buffer → view.
- [ ] Pending guard prompt.

---

## Notes
- Depends on: 006 (parser dispatcher), 007 (http_client), 008 (env), 009 (buffer), 010 (render), 011 (view), 012 (picker).
- History, rails handler để issue 014/015 wire vào (stub ở đây nếu module chưa có).
