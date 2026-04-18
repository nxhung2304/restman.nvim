## **Status:**
- Review: Approved
- PR: Draft

## Metadata
- **Title:** History — persist, replay, jump to source
- **Phase:** 5 — Persistence
- **GitHub Issue:** #14

---

## Description
Module lưu lịch sử request và expose picker.

- **File:** `vim.fn.stdpath("data") .. "/restman/history.json"` — tạo dir nếu chưa có.
- **Encode/decode:** `vim.json.encode/decode`. **KHÔNG** dùng `vim.fn.json_*`.
- **Entry schema:**
  ```json
  {
    "timestamp": "2026-04-11T10:32:18+07:00",
    "method": "GET",
    "url": "...",
    "status": 200,
    "duration_ms": 120,
    "env": "local",
    "file": "/absolute/path/to/file.rb",
    "line": 42,
    "request": { /* full request object cho replay */ }
  }
  ```
- **File path:** absolute (`vim.fn.expand("%:p")`). Hiển thị trong picker thì `fnamemodify(file, ":~:.")`.
- **API:**
  - `append(request, response)` — push entry, truncate LRU 100.
  - `load()` — read + decode.
  - `save()` — encode + write.
  - `last()` — entry mới nhất (fallback cho `repeat` nếu RAM state mất).
  - `open_picker(view_mode)` — gọi `picker.pick(...)` với actions Enter (load response) / `<C-o>` (jump to source).
- **Replay:** nếu buffer của response cũ còn (match index trong `ui.buffer`) → mở lại buffer đó. Nếu LRU đã wipe → re-send request, ghi entry mới.
- **Jump to source:** `vim.cmd("edit " .. entry.file)` + `nvim_win_set_cursor(0, {entry.line, 0})`. File missing → notify, marker `[missing]` trong list, disable action nhưng Enter (replay) vẫn work.
- **`<leader>rr` / `:Restman repeat`:** dùng `M._last` (RAM) nếu có, fallback `history.last()`.

---

## Spec Reference
- Section: §6 History & State Persistence trong [`story.md`](../story.md).
- UX scenario: #7 history picker full flow trong [`v1-usage.md`](../example/v1-usage.md).

---

## Acceptance Criteria
- [ ] `append` ghi entry mới vào file, verify bằng `cat` (ngoài plugin).
- [ ] Entry thứ 101 → entry 1 bị drop.
- [ ] `file` lưu absolute, picker hiển thị relative.
- [ ] `:Restman history` mở split (không phải float).
- [ ] Enter trên entry còn buffer → load lại buffer cũ, không re-send.
- [ ] Enter trên entry buffer đã wipe → re-send, tạo buffer mới.
- [ ] `<C-o>` trên entry file còn → jump đúng line.
- [ ] `<C-o>` trên entry file missing → notify, picker vẫn mở được, Enter vẫn replay được.
- [ ] `:Restman repeat` work sau `nvim_restart` (dùng history fallback).
- [ ] Dùng `vim.json.*` — grep codebase không có `vim.fn.json_`.

---

## Implementation Checklist
- [ ] `lua/restman/history.lua`.
- [ ] File I/O: `vim.fn.mkdir(dir, "p")`, `vim.fn.readfile`, `vim.fn.writefile`.
- [ ] `append` với LRU truncate.
- [ ] `open_picker` — gọi `ui.picker.pick` với 2 actions.
- [ ] Wire vào `commands.lua` — `:Restman history` → `history.open_picker()`.
- [ ] Wire `send` flow: sau `on_complete` thành công → `history.append(req, res)`.

---

## Notes
- Depends on: 007 (http_client), 009 (buffer), 012 (picker), 013 (commands).
- Body response KHÔNG persist (§6 rule), chỉ metadata.
