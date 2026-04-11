# 🎥 restman.nvim v1.0 — UX Walkthrough

> **Mục đích file:** mô tả chính xác những gì user sẽ thấy khi dùng plugin sau khi v1.0 hoàn tất. Đây là "kim chỉ nam UX" — khi implement một feature, đối chiếu với kịch bản tương ứng để verify hành vi.
>
> **Cách đọc:** mỗi kịch bản gồm 3 phần: (1) **Setup** — state của file/env trước khi bấm phím, (2) **Action** — user làm gì, (3) **Expected** — những gì phải xảy ra. Nếu implement không match Expected → bug.

---

## 🧰 Setup chung cho mọi kịch bản

### `.env.json` ở project root

```json
{
  "default": "local",
  "environments": {
    "local": {
      "base_url": "http://localhost:3000",
      "headers": {
        "Authorization": "Bearer dev-token-abc",
        "Content-Type": "application/json"
      },
      "variables": {
        "USER_ID": "42",
        "API_VERSION": "v1"
      }
    },
    "staging": {
      "base_url": "https://staging.api.example.com",
      "headers": {
        "Authorization": "Bearer {{$env.STAGING_TOKEN}}"
      }
    }
  }
}
```

### `init.lua` (user config tối thiểu)

```lua
require("restman").setup({
  -- tất cả default, chỉ override phím nếu muốn
})
```

### Plugin state ban đầu

- Active env: `local` (từ `default`).
- History: rỗng.
- Response buffers: không có.

---

## Kịch bản 1 — Raw cURL trong markdown note

**Setup:** user đang viết `notes/api-debug.md`:

```markdown
# Debug user endpoint

Try this:

curl -X GET http://localhost:3000/users/42 -H "Accept: application/json"

Response should be 200.
```

**Action:** đặt con trỏ trên dòng `curl -X GET ...`, bấm `<leader>rs`.

**Expected:**
1. Parser nhận diện pattern raw cURL → `{ method = "GET", url = "http://localhost:3000/users/42", headers = { Accept = "application/json" } }`.
2. Env `local` merge thêm `Authorization: Bearer dev-token-abc` vào headers (Accept không bị override vì key khác).
3. `vim.system` spawn curl async, status bar hiện `[Restman] GET /users/42 ...`.
4. Sau ~150ms, floating window mở ở giữa màn hình (80% × 70%, rounded border), chứa:
   ```
   GET http://localhost:3000/users/42
   200 OK   •   142ms   •   256 B
   ──────────────────────────────
   [H] Headers (5)   [B] Body   [R] Raw

   {
     "id": 42,
     "name": "Alice",
     "email": "alice@example.com"
   }
   ```
5. Status `200` được highlight xanh, JSON body có treesitter highlight.
6. Bấm `q` → float đóng. Bấm `<leader>rh` → history hiện entry vừa chạy với `file = notes/api-debug.md`, `line = <dòng curl>`.

---

## Kịch bản 2 — Relative URL + env variable substitution

**Setup:** `app/services/user_service.rb`:

```ruby
class UserService
  # GET /api/{{API_VERSION}}/users/{{USER_ID}}
  def fetch_user
    # ...
  end
end
```

**Action:** con trỏ trên dòng comment `# GET /api/{{API_VERSION}}/users/{{USER_ID}}`, bấm `<leader>rs`.

**Expected:**
1. Parser (HTTP-style pattern) trích `method = "GET"`, `url = "/api/{{API_VERSION}}/users/{{USER_ID}}"`.

   > Lưu ý: dòng này là comment, nhưng parser **không** skip nó vì nó match pattern HTTP-style explicit. Quy tắc "skip URL trong comment" (§2.1) chỉ áp dụng cho URL thô không method.

2. Env substitution resolve: `{{API_VERSION}}` → `v1`, `{{USER_ID}}` → `42`.
3. Base URL ghép vào: `http://localhost:3000/api/v1/users/42`.
4. Headers env merge → `Authorization: Bearer dev-token-abc` + `Content-Type: application/json`.
5. Float window hiện response 200 với body user 42.
6. Nếu user đổi env: `:Restman env` → picker hiện `local` / `staging` → chọn `staging` → bấm lại `<leader>rs` → URL giờ là `https://staging.api.example.com/api/v1/users/42`, header `Authorization` lấy từ `{{$env.STAGING_TOKEN}}` (biến OS env).

---

## Kịch bản 3 — Path param prompt với session cache

**Setup:** `routes/articles.rb`:

```ruby
get '/articles/:slug/comments/:comment_id'
```

**Action:** con trỏ trên dòng, bấm `<leader>rs`.

**Expected:**
1. Parser (Framework DSL) → `method = "GET"`, `url = "/articles/:slug/comments/:comment_id"`.
2. Trước khi gửi, plugin detect 2 biến động `:slug` và `:comment_id` → mở `vim.ui.input` tuần tự:
   - Prompt 1: `"slug = "` → user nhập `hello-world`.
   - Prompt 2: `"comment_id = "` → user nhập `7`.
3. URL cuối: `http://localhost:3000/articles/hello-world/comments/7`. Gửi, hiện response.
4. **Session cache kick in:** user edit file, con trỏ vẫn trên dòng route đó, bấm `<leader>rs` lần 2:
   - Prompt 1: `"slug = "` với pre-fill `hello-world`.
   - Prompt 2: `"comment_id = "` với pre-fill `7`.
   - User có thể enter để giữ, hoặc sửa.
5. Tắt Neovim, mở lại → cache reset (session-scoped, không persist).

---

## Kịch bản 4 — POST body từ visual selection (win over directive)

**Setup:** `scratch.js`:

```javascript
// @restman.body { "name": "OldValue" }
// @restman.header X-Trace-Id: abc-123
POST http://localhost:3000/users

const payload = {
  "name": "Alice",
  "email": "alice@example.com",
  "role": "admin"
};
```

**Action:**
1. Bấm `V` (visual-line mode) trên 4 dòng `{` → `}` (object literal ở dưới).
2. Vẫn giữ visual selection, bấm `<leader>rs`.

**Expected:**
1. Plugin parse dòng `POST http://localhost:3000/users` → `method = "POST"`, `url = "..."`.
2. **Body precedence:** visual selection có → win. `@restman.body { "name": "OldValue" }` bị ignore.
3. Directive `@restman.header X-Trace-Id: abc-123` vẫn apply (headers là merge, không phải winner-take-all).
4. Request cuối:
   ```
   POST http://localhost:3000/users
   Authorization: Bearer dev-token-abc    (từ env)
   Content-Type: application/json         (từ env)
   X-Trace-Id: abc-123                    (từ directive)
   
   {
     "name": "Alice",
     "email": "alice@example.com",
     "role": "admin"
   }
   ```
5. Response 201 Created, tô xanh.
6. Nếu user làm lại **không có visual selection** → directive `@restman.body` win, body là `{ "name": "OldValue" }`.

---

## Kịch bản 5 — POST body qua @restman.body directive (multiline)

**Setup:** `api-tests.http`:

```
-- @restman.body {
--   "title": "New article",
--   "tags": ["lua", "neovim"]
-- }
-- @restman.header Idempotency-Key: 7f3a
POST /api/{{API_VERSION}}/articles
```

**Action:** con trỏ trên dòng `POST /api/...`, bấm `<leader>rs` (không visual select).

**Expected:**
1. Parser directive scan comment block liền kề phía trên (stop khi gặp blank line hoặc non-comment). Gộp các dòng `@restman.body` multiline thành 1 JSON string, parse thành table.
2. Env substitution: `{{API_VERSION}}` → `v1`, URL cuối `http://localhost:3000/api/v1/articles`.
3. Gửi POST với body đã parse + header `Idempotency-Key: 7f3a` + env headers.
4. Response 201 hiện trong float.
5. History entry có `file = api-tests.http`, `line = <dòng POST>`.

---

## Kịch bản 6 — Rails routes picker với Telescope

**Setup:** đang ở Rails project, Telescope đã cài. Chưa từng chạy `:Restman rails` trong session.

**Action:** `:Restman rails`.

**Expected:**
1. Lần đầu: plugin chạy `bin/rails routes` async (user thấy notify `[Restman] Loading rails routes...`). Mất ~3s.
2. Output parse thành list, cache vào `.cache/restman/rails_routes.txt`.
3. Telescope picker mở với format:
   ```
   GET    /users                    users#index
   POST   /users                    users#create
   GET    /users/:id                users#show
   PATCH  /users/:id                users#update
   DELETE /users/:id                users#destroy
   GET    /articles/:slug/comments  comments#index
   ...
   ```
4. User gõ `show` → Telescope fuzzy filter xuống `users#show`. Enter.
5. URL có `:id` → prompt `id = ` → user nhập `42` → gửi GET.
6. Response hiện trong float.
7. Lần thứ 2 chạy `:Courier rails` trong cùng session → đọc thẳng từ cache file (< 50ms), không spawn `rails routes` nữa.
8. Nếu `config/routes.rb` đã mtime mới hơn cache → notify warning `"routes.rb has changed since last cache, run :Courier rails refresh"` nhưng picker vẫn mở với cache cũ.
9. `:Restman rails refresh` → xóa cache, re-run `bin/rails routes`, picker mở với data mới.
10. Nếu Telescope **không** cài: fallback về `vim.ui.select` — list dài hơn, không có fuzzy, nhưng chức năng đầy đủ.

---

## Kịch bản 7 — History replay + jump to source

**Setup:** trong session đã chạy 5 request từ nhiều file khác nhau. Giờ đang ở một file hoàn toàn khác.

**Action 1 — Repeat nhanh:** bấm `<leader>rr`.

**Expected 1:**
- Plugin gửi lại request gần nhất (request thứ 5) với **đúng** method/url/headers/body như lần trước. Response hiện trong float.
- Không cần con trỏ ở đâu cả — repeat là stateless theo nghĩa "không đọc lại buffer hiện tại".

**Action 2 — Mở history picker:** `:Restman history` (hoặc `<leader>rh`).

**Expected 2:**
1. Response viewer mở ở **split** (bên phải, size 80 cols) — không phải float. (§4.5 rule.)
2. Picker (Telescope ưu tiên) hiện 5 entries theo thứ tự mới → cũ:
   ```
   [10:32] POST   /articles              201   120ms   local   scratch.js:5
   [10:30] GET    /articles/hello/.../7  200   88ms    local   routes/articles.rb:1
   [10:28] GET    /users/42              200   142ms   local   notes/api-debug.md:5
   [10:20] POST   /users                 201   178ms   staging app/services/user_service.rb:3
   [10:15] GET    /api/v1/users/42       200   95ms    local   app/services/user_service.rb:2
   ```
3. Trong picker, mỗi entry có 2 action:
   - **Enter (default)** → load response body cached từ buffer list vào split view. Nếu buffer đã bị LRU wipe (> 10 buffer) → replay request để lấy lại.
   - **`<C-o>` (custom action)** → jump to source: `vim.cmd("edit " .. entry.file)` + `cursor(line, 0)`. Nếu file đã bị xóa → notify `[Courier] File missing: ...`, picker hiển thị entry với marker `[missing]` và action Enter vẫn chạy replay được (không cần file gốc).
4. Bấm `<C-c>` trong picker → đóng picker nhưng split viewer giữ lại.
5. Entry cũ nhất (thứ 100+) tự động bị LRU wipe khỏi `history.json`.

---

## Kịch bản 8 — Cancel long-running request

**Setup:** endpoint `/slow` ở local server mất 60s mới response. Timeout mặc định là 30s.

**Action 1 — Gửi và chờ:** con trỏ trên `GET http://localhost:3000/slow`, bấm `<leader>rs`.

**Expected 1:**
- Plugin spawn curl async, không block UI. User vẫn gõ code bình thường.
- Status line hiện spinner `[Courier] GET /slow ...` (không chặn gì).

**Action 2 — Cancel sau 5s:** bấm `<leader>rc` (hoặc `:Courier cancel`).

**Expected 2:**
1. Plugin kill curl process (bằng `vim.system` handle `kill()`).
2. Notify `[Restman] Request cancelled`.
3. Không mở float window (cancel không phải error).
4. History **không** log entry bị cancel (vì không có response).

**Action 3 — Gửi lại, chưa response thì bấm `<leader>rs` lần 2:**

**Expected 3:**
1. Plugin detect có pending request → prompt `vim.ui.input`: `"Cancel previous request? [y/N]"`.
2. User gõ `y` → kill pending, spawn mới. Gõ `N` hoặc enter rỗng → bỏ qua lần bấm mới, pending vẫn chạy.

**Action 4 — Để request chạy đến timeout (không cancel):**

**Expected 4:**
1. Sau 30s, `vim.system` report timeout.
2. Float mở với error formatted:
   ```
   GET http://localhost:3000/slow
   ❌ Network error: request timed out after 30000ms
   
   Hint: check network / increase timeout in setup({ timeout = 60000 }).
   ```
3. Border red (hoặc status "ERROR" tô đỏ). History entry có `status = null`, `duration_ms = 30000`, `error = "timeout"`.

---

## 🎯 Verification checklist cho Claude Code khi implement

Khi hoàn tất mỗi module, đối chiếu với kịch bản tương ứng:

| Module | Kịch bản verify |
|--------|-----------------|
| `parser/curl.lua` | #1 |
| `parser/http.lua` | #2, #5 |
| `parser/dsl.lua` | #3, #6 |
| `parser/directives.lua` | #4, #5 |
| `env.lua` | #2 (substitution), #8 (file-not-found fallback — test riêng) |
| `http_client.lua` | toàn bộ, đặc biệt #8 (cancel + timeout) |
| `ui/buffer.lua` | #1, #7 (LRU wipe) |
| `ui/view.lua` | #1 (float), #7 (split), promote keys |
| `ui/render.lua` | #1 (status color, JSON highlight) |
| `ui/picker.lua` | #6 (Telescope + fallback), #7 (custom action) |
| `history.lua` | #7 (replay + jump to source + missing file) |
| `integrations/rails.lua` | #6 (cache + stale warning + refresh) |

Nếu bất kỳ kịch bản nào behavior khác mô tả → **đó là bug**, không phải spec update.
