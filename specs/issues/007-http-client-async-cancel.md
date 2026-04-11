## **Status:**
- Review: Approved
- PR: Approved

## Metadata
- **Title:** HTTP client — async `vim.system` + cancel
- **Phase:** 2 — Execution
- **GitHub Issue:** #7

---

## Description
Module thực thi request thật qua `curl` CLI, async, hỗ trợ cancel và timeout.

- **Engine:** `vim.system` (Neovim ≥ 0.10). Fallback `plenary.job` nếu user config yêu cầu (MVP chỉ cần `vim.system`).
- **Input:** request object từ parser dispatcher (đã resolve env).
- **Output:** callback `on_complete(response | error)` với `response = { status, headers, body, duration_ms, raw }`.
- **Curl args build:**
  - `-X METHOD`, `-H "K: V"` cho mỗi header, `--data @-` (stdin) cho body, `-sS -D -` để lấy headers + body trong 1 lần, `-w "\nRESTMAN_META %{http_code} %{time_total}\n"` footer.
  - `--max-time <timeout>` (mặc định 30s, config được).
  - `-G --data-urlencode` nếu có query, hoặc append vào URL.
- **Parse response:** tách header block và body block từ curl stdout, parse status code từ footer `COURIER_META`.
- **Cancel:** giữ handle của `vim.system`, expose `cancel()` → `handle:kill(15)`. Có state module `M._pending` track request đang chạy.
- **Error classification** (§5):
  1. Network error — `vim.system` exit code ≠ 0, signal timeout → `{ kind="network", message }`.
  2. HTTP error — status ≥ 400 → vẫn là response bình thường (không phải error), UI layer sẽ tô đỏ.
  3. Parse error — URL sai / method invalid → caller (dispatcher) validate trước khi gọi.

---

## Spec Reference
- Section: §5 Async Core & Cancel trong [`story.md`](../story.md).
- UX scenario: #8 cancel long-running + timeout trong [`v1-usage.md`](../example/v1-usage.md).

---

## Acceptance Criteria
- [ ] `send(request, on_complete)` không block UI (gõ code trong khi chờ vẫn mượt).
- [ ] Response parse đúng status/headers/body/duration cho GET 200 JSON.
- [ ] Cancel giữa chừng: `cancel()` → curl process exit, không gọi `on_complete` với error (hoặc gọi với `kind = "cancelled"`, caller tự handle).
- [ ] Bấm gửi lần 2 khi pending: API `send(...)` detect pending → return special status, caller sẽ prompt.
- [ ] Timeout 30s → `on_complete({ kind="network", message="timeout" })`.
- [ ] Method `POST`/`PUT`/`PATCH` + body JSON → body gửi qua stdin (`--data @-`), không qua arg (tránh command-length limit).

---

## Implementation Checklist
- [ ] `lua/restman/http_client.lua` — export `send(req, cb)`, `cancel()`, `is_pending()`.
- [ ] Build curl arg list (table).
- [ ] Parse response: split header/body, extract status.
- [ ] State `M._pending = { handle, started_at }`.
- [ ] Timeout qua `--max-time` của curl (không dùng vim timer).
- [ ] Manual test: local server trả 200, 404, slow (60s), nonexistent host.

---

## Notes
- KHÔNG đụng UI ở module này. `on_complete` chỉ pass data lên; `ui/` layer render.
- `User-Agent: restman.nvim/1.0` auto add vào mọi request (trừ khi user override).
