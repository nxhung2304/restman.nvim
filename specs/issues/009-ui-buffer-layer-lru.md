## **Status:**
- Review: Pending
- PR: Todo

## Metadata
- **Title:** UI — Response buffer layer + LRU
- **Phase:** 3 — UI
- **GitHub Issue:** (to be filled after sync)

---

## Description
Buffer layer của response viewer (§4.1). Tách biệt hoàn toàn với window layer — mỗi response là 1 scratch buffer, view chỉ là viewport.

- **Tạo buffer:** `vim.api.nvim_create_buf(false, true)`, set options `buftype=nofile`, `bufhidden=hide`, `swapfile=false`, tên `courier://response/<n>` (n tăng dần global).
- **Registry:** module table `M._buffers = { [bufnr] = { index, request, response, created_at } }`.
- **LRU wipe:** giữ tối đa 10 buffer, khi vượt → wipe oldest bằng `nvim_buf_delete(bufnr, { force = true })`, cleanup registry.
- **API:**
  - `create(request, response) → bufnr` — tạo mới + render (gọi render layer) + push vào registry.
  - `list() → { {bufnr, index, request, response} }` — trả list sorted desc theo `created_at`.
  - `get(bufnr) → entry` — lookup.
  - `wipe(bufnr)` — xóa 1 buffer.
  - `wipe_all()` — clear toàn bộ.
- Buffer giữ sau khi float/split đóng — đó là mục đích của tách layer.

---

## Spec Reference
- Section: §4.1 Nguyên tắc kiến trúc, §4.5 giới hạn 10 buffer LRU trong [`story.md`](../story.md).
- UX scenario: #7 history picker load lại buffer cũ (nếu còn) trong [`v1-usage.md`](../example/v1-usage.md).

---

## Acceptance Criteria
- [ ] `create(req, res)` return bufnr valid, `:ls` thấy `courier://response/1`, `courier://response/2`, ...
- [ ] Buffer `nofile` + `bufhidden=hide` + không save được (`:w` phải error).
- [ ] Push buffer thứ 11 → buffer thứ 1 (cũ nhất) bị `wipe`, chỉ còn 10 trong registry.
- [ ] `list()` sort đúng theo recency.
- [ ] `get(invalid_bufnr)` → `nil`.
- [ ] Đóng window hiển thị buffer không gây wipe buffer.

---

## Implementation Checklist
- [ ] `lua/courier/ui/buffer.lua` — các API trên.
- [ ] Counter `M._next_index = 1`, tăng khi create.
- [ ] LRU queue (table ordered).
- [ ] Gọi `ui/render.render(bufnr, request, response)` sau khi tạo (depends on 010).
- [ ] Manual test: tạo 12 buffer, verify LRU.

---

## Notes
- Depends on: 001 (scaffold), 010 (render layer — có thể stub render rồi merge sau).
- Không xử lý window/float ở đây.
