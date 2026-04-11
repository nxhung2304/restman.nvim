## **Status:**
- Review: Approved
- PR: Approved

## Metadata
- **Title:** Rails integration — routes parser + cache
- **Phase:** 6 — Integrations
- **GitHub Issue:** #15

---

## Description
Integration đọc `bin/rails routes` và expose picker để user chọn 1 route → gửi request.

- **Cache file:** `.cache/restman/rails_routes.txt` (trong project root, thêm vào `.gitignore` tự động nếu `.gitignore` tồn tại và chưa có entry).
- **Load flow:**
  1. Nếu cache file tồn tại → đọc + parse, return list.
  2. Nếu không → chạy `bin/rails routes` async qua `vim.system`, notify `[Restman] Loading rails routes...`, đợi ~3s, cache lại.
- **Parse output:** tách cột `Prefix Verb URI Pattern Controller#Action`, extract `verb`, `path`, `controller#action`. Ignore dòng header.
- **Stale detection:** mỗi lần load cache, so sánh `mtime` của `config/routes.rb` với cache file. Nếu routes.rb mới hơn → notify WARN `"routes.rb has changed, run :Restman rails refresh"`, vẫn dùng cache cũ.
- **Refresh:** `:Restman rails refresh` → `os.remove(cache_file)` + re-run.
- **Picker:** `picker.pick({ items, format = "VERB PATH controller#action", on_select = send_route })`.
- **`send_route(route)`:**
  1. Tạo request `{ method = route.verb, url = route.path }`.
  2. Parser dispatcher logic cho dynamic params (`:id`) — reuse helper từ issue 006.
  3. Env apply (base_url + headers).
  4. http_client.send → buffer → view.
- **Detect Rails project:** check `config/routes.rb` tồn tại. Nếu không → notify ERROR `"Not a Rails project (config/routes.rb not found)"`, abort.

---

## Spec Reference
- Section: §7 Rails Integration trong [`story.md`](../story.md).
- UX scenario: #6 rails picker Telescope + fallback + stale warning trong [`v1-usage.md`](../example/v1-usage.md).

---

## Acceptance Criteria
- [ ] Lần đầu `:Restman rails` chạy `bin/rails routes`, notify loading, cache file tạo đúng path.
- [ ] Lần 2 trong cùng session đọc từ cache < 100ms (đo bằng `vim.loop.hrtime`).
- [ ] `:Restman rails refresh` xóa cache và re-run.
- [ ] routes.rb mtime > cache mtime → notify warn nhưng picker vẫn mở với cache cũ.
- [ ] Chọn route có `:id` → prompt, gửi đúng URL resolved.
- [ ] Không phải Rails project → ERROR, không crash.
- [ ] `.cache/restman/` trong `.gitignore` nếu file này đã tồn tại (append nếu chưa có, no-op nếu chưa có `.gitignore` chính).

---

## Implementation Checklist
- [ ] `lua/restman/integrations/rails.lua`.
- [ ] Parser table-style output (fixed-width cols hoặc split by 2+ spaces).
- [ ] Cache read/write via `vim.fn.readfile`/`writefile`.
- [ ] Stale check via `vim.loop.fs_stat`.
- [ ] Wire `:Restman rails [refresh]` subcommand vào commands dispatcher (issue 013 complete).
- [ ] Tab completion bổ sung `refresh`.

---

## Notes
- Depends on: 006 (parser — dynamic param helper), 007 (http_client), 008 (env), 012 (picker), 013 (commands).
- Không support engine mounted hoặc routes parent→child nested — v2.0.
