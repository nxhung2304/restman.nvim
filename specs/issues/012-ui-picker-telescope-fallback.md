## **Status:**
- Review: Approved
- PR: Approved

## Metadata
- **Title:** UI — Picker abstraction (Telescope + `vim.ui.select` fallback)
- **Phase:** 3 — UI
- **GitHub Issue:** #12

---

## Description
Abstraction cho 3 use-case picker: history, env list, rails routes. Dùng Telescope nếu có, fallback `vim.ui.select`.

- **API:**
  - `pick(opts)` — `opts = { items, format, on_select, on_secondary?, title }`.
    - `items`: list các entry.
    - `format(item) → string` — hiển thị.
    - `on_select(item)` — Enter action.
    - `on_secondary(item)` — `<C-o>` custom action (optional, cho jump-to-source).
    - `title`: label picker.
- **Telescope path:** `pcall(require, "telescope.pickers")`, nếu ok → dùng `telescope.pickers.new(...)` với custom action map Enter + `<C-o>`.
- **Fallback:** `vim.ui.select(items, { prompt = title, format_item = format }, function(choice) on_select(choice) end)`. Fallback **không support** `on_secondary` — log info "upgrade to Telescope for advanced actions".
- **Telescope extension registration:** expose `:Telescope restman history`, `:Telescope restman env`, `:Telescope restman rails_routes` (optional, nếu Telescope có → auto register).
- **Buffer list picker:** helper `open_buffer_list()` liệt kê tất cả response buffer từ `ui.buffer.list()`, on_select → `view.open(bufnr, current_mode)`.

---

## Spec Reference
- Section: §7.2 Picker, §4.4 `<C-o>` action trong [`story.md`](../story.md).
- UX scenario: #6 Telescope + fallback, #7 history picker với custom action trong [`v1-usage.md`](../example/v1-usage.md).

---

## Acceptance Criteria
- [ ] `pick({items, format, on_select})` work cả khi Telescope có và không có.
- [ ] `<C-o>` trong Telescope gọi `on_secondary` đúng entry.
- [ ] `on_secondary` là nil + user bấm `<C-o>` → no-op, không error.
- [ ] `open_buffer_list()` hiển thị đúng list response buffer theo LRU order.
- [ ] Fallback mode hiển thị `format_item` đúng.
- [ ] Plugin không crash nếu Telescope chưa cài (zero hard-dependency).

---

## Implementation Checklist
- [ ] `lua/restman/ui/picker.lua` — `pick`, `open_buffer_list`.
- [ ] `pcall(require, "telescope.pickers")` kiểm tra 1 lần, cache boolean `M._has_telescope`.
- [ ] Telescope branch: custom `attach_mappings` cho Enter + `<C-o>`.
- [ ] Extension register: file `lua/telescope/_extensions/restman.lua` (chỉ load nếu Telescope có).

---

## Notes
- Depends on: 001 (scaffold), 009 (buffer list).
- Các picker cụ thể (history, rails) implement ở issue tương ứng, chỉ gọi `picker.pick(...)`.
