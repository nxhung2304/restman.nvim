## **Status:**
- Review: Approved
- PR: Approved

## Metadata
- **Title:** UI — View layer (float/split/vsplit/tab + promote + keymaps)
- **Phase:** 3 — UI
- **GitHub Issue:** #11

---

## Description
Window layer của response viewer. Nhận `bufnr` từ buffer layer, mở trong một view mode (float/split/vsplit/tab). Hỗ trợ "promote" giữa các mode mà không mất buffer state.

- **API:**
  - `open(bufnr, mode)` — mode ∈ `"float" | "split" | "vsplit" | "tab"`.
  - `promote(new_mode)` — lấy bufnr của view hiện tại, đóng view, mở bằng mode mới.
  - `close()` — đóng view hiện tại (không wipe buffer).
- **Float:** `nvim_open_win` với config center, width = `0.8 * vim.o.columns`, height = `0.7 * vim.o.lines`, border `rounded`. Config override được từ `config.response.float`.
- **Split:** `botright vsplit` hoặc `vsplit` theo position, size từ config (default 80 cols).
- **Tab:** `tabnew` + `buffer <bufnr>`.
- **Keymap trong response buffer** (set buffer-local khi view mở):

  | Phím | Hành động |
  |------|-----------|
  | `q`, `<Esc>` | `close()` |
  | `H` | Toggle headers (gọi `render` với `opts.headers = not current`) |
  | `B` | Scroll tới body section |
  | `R` | Toggle raw (gọi `render` với `opts.mode='raw'/'pretty'`) |
  | `y` | Copy body → `+` register |
  | `yy` | Copy full (status + headers + body) |
  | `<CR>` | Save to file — `vim.ui.input` path |
  | `s` | `promote("split")` |
  | `v` | `promote("vsplit")` |
  | `t` | `promote("tab")` |
  | `<C-o>` | Gọi `picker.open_buffer_list()` để switch sang response buffer khác |

---

## Spec Reference
- Section: §4.2 Default view, §4.4 keymap table, §4.5 view-specific rules trong [`story.md`](../story.md).
- UX scenario: #1 float default, #7 history split, promote behavior trong [`v1-usage.md`](../example/v1-usage.md).

---

## Acceptance Criteria
- [ ] `open(bufnr, "float")` tạo float ở giữa, đúng size, border rounded.
- [ ] `open(bufnr, "split")` tạo vertical split bên phải 80 cols.
- [ ] `s` từ float → float đóng, split mở với cùng bufnr, scroll position giữ nguyên.
- [ ] `v` và `t` tương tự.
- [ ] `q`/`<Esc>` đóng view nhưng `:ls` vẫn thấy buffer `restman://response/N`.
- [ ] `y` copy body sang clipboard (`+` register).
- [ ] `H` toggle headers section (verify bằng 2 lần bấm).
- [ ] `R` toggle raw/pretty.
- [ ] Buffer-local keymap không leak sang buffer khác.

---

## Implementation Checklist
- [ ] `lua/restman/ui/view.lua` — `open`, `close`, `promote`, internal `_setup_keymaps(bufnr)`.
- [ ] State `M._current = { bufnr, winid, mode }`.
- [ ] Promote: capture scroll position (`nvim_win_get_cursor`), đóng cũ, mở mới, restore cursor.
- [ ] Keymap set qua `vim.keymap.set(..., { buffer = bufnr })`.

---

## Notes
- Depends on: 009 (buffer), 010 (render — để toggle gọi lại), 012 (picker — `<C-o>` action).
- `:Restman send` → default `"float"`; `:Restman history` → default `"split"` (wire ở issue 013).
