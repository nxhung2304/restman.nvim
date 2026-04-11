Reivew Thử:

# 🚀 Tệp Đặc tả (Spec) — `courier.nvim` (v1.0 MVP)

## 🎯 Tầm nhìn Sản phẩm
Một trợ lý giao tiếp API ngay trong Neovim, tập trung vào **tốc độ**, **giảm ma sát (frictionless)** và **không yêu cầu cú pháp đặc biệt**.

Nguyên tắc thiết kế:
1. **Explicit > Magic** — Người dùng phải viết đủ `METHOD` và `URL` trên dòng code (hoặc context gần đó). Plugin **không đoán** method khi không có bằng chứng rõ ràng.
2. **One-key experience** — Đặt con trỏ → bấm 1 phím → nhận kết quả.
3. **Async-first** — Không bao giờ block UI.
4. **Zero hard-dependency** — Telescope, plenary đều là optional.

---

## ✅ Checklist Tính năng Cốt lõi (MVP)

### 1. One-Key Experience & Cấu hình
* **Mục tiêu:** Không gián đoạn mạch code.
* **Hành vi:** Đặt con trỏ tại dòng chứa request → bấm phím → nhận kết quả trong floating window.
* **Phím tắt mặc định (override được trong `setup()`):**
  * `<leader>rs` — Send: gửi request tại dòng hiện tại.
  * `<leader>rr` — Repeat: gửi lại request gần nhất.
  * `<leader>re` — Environment: chọn môi trường active.
  * `<leader>rh` — History: mở danh sách request đã chạy.
  * `<leader>rc` — Cancel: hủy request đang chạy.
* **Lệnh tương ứng (cho user không dùng keymap):** dùng cú pháp **subcommand** với một command gốc `:Courier`:
  * `:Courier send`
  * `:Courier repeat`
  * `:Courier env` — chọn environment active
  * `:Courier history`
  * `:Courier cancel`
  * `:Courier rails` — mở Rails routes picker
  * `:Courier rails refresh` — invalidate cache routes
  * `:Courier health` — alias của `:checkhealth courier`
* **Implementation note:** chỉ đăng ký 1 `nvim_create_user_command("Courier", ...)` với `nargs = "*"` và custom completion, dispatch theo subcommand đầu tiên. Tránh tạo nhiều top-level command làm rối `:` completion.

---

### 2. Smart Detection — Explicit METHOD + URL
* **Mục tiêu:** Nhận diện API endpoint từ mọi file code mà không cần parser phức tạp, nhưng **yêu cầu user ghi đủ METHOD và URL**.
* **Quy tắc bắt buộc:** Một dòng chỉ được coi là "gửi được" khi có thể trích xuất **cả METHOD và URL**. Nếu thiếu, plugin **prompt hỏi** thay vì đoán.

#### 2.1 Các pattern hỗ trợ (theo thứ tự ưu tiên)

| # | Pattern | Ví dụ | Method lấy từ |
|---|---------|-------|---------------|
| 1 | **Raw cURL** | `curl -X POST https://api.com/users -H "..."` | Cờ `-X` (default `GET` nếu có `-d` thì `POST`) |
| 2 | **HTTP-style prefix** | `GET https://api.com/users` / `POST /users` | Token đầu dòng |
| 3 | **Framework route DSL** | `get '/users'` (Rails/Sinatra), `router.delete('/x')` (Express) | Tên hàm |
| 4 | **URL thô trong string literal** | `"https://api.com/users"` | ❌ Không có method → **prompt hỏi** |

> **Out of scope v1.0:** Client SDK parsing (`axios.post`, `fetch(url, {method:"PUT"})`, `http.Get(...)`) đòi hỏi phân tích AST / treesitter để lấy được object body truyền vào hàm → **dời sang v1.1**. MVP ưu tiên 4 pattern trên để parser đơn giản, dễ test, và tránh false positive.

**Quy tắc parse URL:**
- Chỉ trích URL nằm **giữa cặp quote** (`"..."`, `'...'`, `` `...` ``) hoặc sau từ khóa HTTP method.
- Bỏ qua URL trong comment (`//`, `#`, `--`).
- Absolute URL (`http(s)://`) → dùng nguyên.
- Relative (`/api/...`) → ghép với `base_url` của env active. Nếu không có env → prompt hỏi base URL.

#### 2.2 Xử lý tham số động (Dynamic Params Fallback)
* Nếu URL chứa biến: `/users/:id`, `/posts/{post_id}`, `/items/<slug>` → dùng `vim.ui.input` prompt từng biến.
* Nếu URL chứa template literal (`${var}`, `#{var}`) mà plugin không resolve được → prompt hỏi.
* Giá trị đã nhập được **cache trong session** — lần sau gặp cùng biến thì pre-fill.

#### 2.3 Body & Headers — Nguồn dữ liệu
MVP hỗ trợ **3 nguồn**. **Thứ tự ưu tiên (cao → thấp):** visual selection > directive > prompt. Nguồn đầu tiên tìm thấy sẽ **win tuyệt đối**, các nguồn còn lại bị bỏ qua (no merge).

1. **Visual selection** (ưu tiên cao nhất) — nếu user có active visual selection khi bấm `<leader>rs`, block đó luôn thắng, kể cả khi có `@courier.body` directive gần đó.
2. **Heredoc comment ngay trên dòng request** — parser đọc comment block liền kề:
   ```lua
   -- @courier.body { "name": "Alice" }
   -- @courier.header Authorization: Bearer {{TOKEN}}
   POST https://api.com/users
   ```
   Các directive hỗ trợ: `@courier.body`, `@courier.header`, `@courier.query`, `@courier.form`.
   **Lý do chọn namespace `@courier.*`:** tránh xung đột với JSDoc (`@body`), YARD (`@param`), phpDoc, hoặc các plugin comment-directive khác. Parser chỉ nhận diện prefix `@courier.` — các directive không namespace sẽ bị bỏ qua.
3. **Prompt** (ưu tiên thấp nhất) — nếu method là POST/PUT/PATCH mà không tìm được body từ (1) hoặc (2) → hỏi qua `vim.ui.input` (hoặc mở scratch buffer để paste nhiều dòng).

> **Headers merge khác với body:** headers từ env (§3.1) luôn merge vào request, chỉ bị override khi key trùng trong `@courier.header`. Tức là headers là **merge**, còn body là **winner-take-all**.

---

### 3. Environment & Smart Defaults

#### 3.1 File `.env.json`
Đặt tại root project. Cấu trúc:
```json
{
  "default": "local",
  "environments": {
    "local": {
      "base_url": "http://localhost:3000",
      "headers": {
        "Authorization": "Bearer dev-token",
        "Content-Type": "application/json"
      },
      "variables": {
        "USER_ID": "42"
      }
    },
    "staging": {
      "base_url": "https://staging.api.com",
      "headers": { "Authorization": "Bearer {{STAGING_TOKEN}}" }
    }
  }
}
```

* **Base URL** ghép tự động với relative path.
* **Headers** mặc định merge vào mọi request (request-specific headers override).
* **Variables** được substitute vào URL/body/header dưới dạng `{{VAR_NAME}}`.
* Hỗ trợ **biến môi trường hệ thống** qua `{{$env.VAR}}` (VD: `{{$env.GITHUB_TOKEN}}`).

**Hành vi khi file không tồn tại / lỗi:**
| Tình huống | Behavior |
|------------|----------|
| `.env.json` không tồn tại | Chạy với **env rỗng** (no base_url, no default headers, no variables). Không fail. Log info 1 lần qua `vim.notify` ở level `INFO`. |
| `.env.json` tồn tại nhưng parse lỗi (`vim.json.decode` throw) | **Fail loud**: `vim.notify` level `ERROR` kèm dòng/lỗi parse, plugin vẫn hoạt động với env rỗng. Không crash. |
| `default` trỏ tới environment không tồn tại | Fail loud, fallback env rỗng. |
| Request dùng relative URL nhưng env rỗng / không có `base_url` | Prompt user nhập base URL 1 lần qua `vim.ui.input` (cache trong session). |
| File đổi trên disk giữa session | Reload lazy: lần gọi `:Courier env` kế tiếp sẽ re-read. Không auto-watch. |

**Project root detection:** tìm `.env.json` bằng cách đi lên từ `vim.fn.expand("%:p:h")` cho tới khi gặp `.git/` hoặc `/`. Nếu không có file thì dùng quy tắc "env rỗng" ở trên.

#### 3.2 Smart Defaults
* Content-Type mặc định: `application/json` khi có body JSON.
* Timeout mặc định: 30 giây (override được).
* User-Agent: `courier.nvim/1.0`.
* **Không có method default** — nếu không phát hiện được, plugin prompt hỏi (không tự chọn GET).

---

### 4. Response Viewer (Float-first, Promotable)

#### 4.1 Nguyên tắc kiến trúc — tách **Buffer layer** và **Window layer**
* **Buffer layer:** Mỗi response được ghi vào một **scratch buffer** riêng, đặt tên dạng `courier://response/<n>` (n tăng dần). Buffer là `nofile`, `bufhidden=hide`, không save được — đóng view không xóa data.
* **Window layer:** Nhiều cách render cùng một buffer — float / split / vsplit / tab. Chuyển view **không mất state** (scroll position, toggle headers, v.v.).
* **Lợi ích:** user có thể "promote" từ float sang split để inspect sâu, hoặc mở lại response cũ từ buffer list (`:ls`, `<C-o>`) mà không cần resend.

#### 4.2 Default view: Floating window
Khớp với triết lý one-key, non-intrusive. 90% use case là *quick peek* — gửi, xem status, đóng, code tiếp.

* `vim.api.nvim_open_win` tạo float ở **giữa màn hình** (default).
* Kích thước mặc định: 80% width × 70% height.
* Border: `rounded`.
* Config được override qua `setup()`:
  ```lua
  response = {
    default_view = "float",   -- "float" | "split" | "vsplit" | "tab"
    float = { position = "center", width = 0.8, height = 0.7, border = "rounded" },
    split = { position = "right", size = 80 },  -- cho "split"/"vsplit"
  }
  ```

#### 4.3 Nội dung hiển thị (render giống nhau cho mọi view)
```
┌─ Response ─────────────────────────────────────┐
│ POST https://api.com/users                     │
│ 201 Created   •   142ms   •   1.2 KB           │
│ ────────────────────────────────────────────── │
│ [H] Headers (3)   [B] Body   [R] Raw           │
│                                                │
│ {                                              │
│   "id": 42,                                    │
│   "name": "Alice"                              │
│ }                                              │
└────────────────────────────────────────────────┘
```
* **Status Code** tô màu: 2xx xanh, 3xx vàng, 4xx/5xx đỏ.
* **Body** auto prettify + syntax highlight theo Content-Type (JSON/HTML/XML/plain) — tận dụng treesitter vì là real buffer.

#### 4.4 Keymap trong response buffer (float hoặc split đều có)
| Phím | Hành động |
|------|-----------|
| `q`, `<Esc>` | Đóng view hiện tại (buffer vẫn còn trong list) |
| `H` | Toggle headers section |
| `B` | Scroll tới body |
| `R` | Toggle raw vs prettified |
| `y` | Copy body vào clipboard |
| `yy` | Copy full response (status + headers + body) |
| `<CR>` | Save response ra file (prompt path) |
| `s` | **Promote** → horizontal split |
| `v` | **Promote** → vertical split |
| `t` | **Promote** → new tab |
| `<C-o>` | Mở picker các response buffer cũ (float → switch buffer) |

#### 4.5 Quy tắc view-specific
* `:Courier send` → mở bằng `default_view` trong config.
* `:Courier history` → **mở bằng split** (user đang inspect sâu, không phải quick peek). Override được qua `history.view = "float"`.
* Khi promote từ float → split/vsplit/tab: float đóng, buffer giữ nguyên, window mới focus vào buffer đó.
* Mặc định giữ tối đa **10 response buffer** gần nhất, auto wipe LRU khi vượt (tránh leak bộ nhớ).

---

### 5. Async Core & Cancel
* **Engine:** `vim.system` (Neovim ≥ 0.10) chạy ngầm `curl`. Fallback `plenary.job` nếu version thấp hơn.
* **Timeout:** mặc định 30s, config được per-request.
* **Cancel:** `:Courier cancel` hoặc `<leader>rc` giết process đang chạy. Bấm `<leader>rs` lần 2 khi chưa có response → prompt "Cancel previous request? [y/N]".
* **Error handling:** phân biệt 3 loại lỗi với thông báo riêng:
  1. Network error (timeout, DNS fail) → đỏ + gợi ý check mạng.
  2. HTTP error (4xx/5xx) → hiển thị body lỗi trong floating window.
  3. Parse error (URL sai, method không hợp lệ) → echo message, không mở window.

---

### 6. History & State Persistence
* **Last request** (cho `<leader>rr`): lưu trong RAM, **không persist** qua session (đơn giản cho MVP).
* **History list:**
  * Lưu tại `vim.fn.stdpath("data") .. "/courier/history.json"`.
  * Giới hạn 100 entries gần nhất (LRU).
  * Mỗi entry bao gồm metadata đầy đủ để có thể **jump back to source**:
    ```json
    {
      "timestamp": "2026-04-11T10:32:18+07:00",
      "method": "GET",
      "url": "https://api.com/users/42",
      "status": 200,
      "duration_ms": 120,
      "env": "local",
      "file": "app/services/user_service.rb",
      "line": 42
    }
    ```
  * **`file` lưu dạng absolute path** (kết quả của `vim.fn.expand("%:p")`). Picker khi jump back sẽ `vim.fn.fnamemodify(file, ":~:.")` để hiển thị relative-to-cwd cho đẹp, nhưng trong JSON luôn là absolute. Lý do: project có thể được mở từ nhiều cwd khác nhau — absolute path là nguồn duy nhất luôn resolve được.
  * Khi user chọn một history entry và file không còn tồn tại (đã xóa/di chuyển), picker hiển thị entry với marker `[missing]` và disable action "jump to source" — nhưng "replay" vẫn chạy được (chỉ cần method + url + body).
  * `file` + `line` cho phép picker (Telescope/`vim.ui.select`) mở lại đúng vị trí request gốc khi user chọn entry cũ.
* **Response cache:** không persist body ra disk (tránh rò rỉ data) — chỉ giữ metadata.
* **Serialization:** dùng `vim.json.encode/decode` (Neovim ≥ 0.10) — **không** dùng `vim.fn.json_encode/decode` (chậm + edge case khác nhau với `null`/empty table).

---

### 7. Rails Integration (Optional)

#### 7.1 `:Courier rails`
* Đọc đầu ra `bin/rails routes` **một lần** khi gọi lệnh đầu tiên.
* **Cache** tại `.cache/courier/rails_routes.txt` (trong project root, thêm vào `.gitignore`).
* Lệnh `:Courier rails refresh` để invalidate cache (khi user vừa thêm route mới).
* **Auto-invalidate:** **không** tự động watch `config/routes.rb` trong v1.0. User phải gọi `refresh` thủ công. Lý do: tránh overhead fs watcher, và `bin/rails routes` là command nặng (~2–5s), không nên chạy tự động.
* **Stale detection (nhẹ):** mỗi lần `:Courier rails` đọc cache, so sánh `mtime` của `config/routes.rb` với `mtime` của cache file. Nếu routes.rb mới hơn → log warning `"routes.rb has changed since last cache, run :Courier rails refresh"` nhưng **vẫn dùng cache cũ** (không block user).
* Parse output → list `{ verb, path, controller#action }` → đưa vào picker.
* Chọn → nếu có `:param` thì prompt → gửi.

#### 7.2 Picker
* **Ưu tiên Telescope** nếu đã cài (`pcall(require, "telescope")`).
* **Fallback `vim.ui.select`** nếu không có — vẫn dùng được nhưng UX đơn giản hơn.
* Telescope extension: `:Telescope courier history`, `:Telescope courier env`, `:Telescope courier rails_routes`.

---

## 🏗️ Kiến trúc Module (đề xuất)

```
lua/courier/
├── init.lua           -- setup(), expose API
├── config.lua         -- default config + user config merge
├── parser/
│   ├── init.lua       -- entry: parse_current_line()
│   ├── curl.lua       -- raw cURL parser
│   ├── http.lua       -- "GET https://..." parser
│   ├── dsl.lua        -- Rails/Sinatra/Express route DSL
│   └── directives.lua -- @courier.body, @courier.header comment directives
├── env.lua            -- load .env.json, substitute variables
├── http_client.lua    -- vim.system + curl wrapper, cancel
├── ui/
│   ├── buffer.lua     -- scratch buffer layer: create, store, LRU wipe
│   ├── render.lua     -- status/headers/body rendering vào buffer
│   ├── view.lua       -- window layer: float | split | vsplit | tab, promote
│   └── picker.lua     -- Telescope | vim.ui.select abstraction
├── history.lua        -- persist & query (dùng vim.json)
└── integrations/
    └── rails.lua      -- rails routes parser + cache
```

> **JSON:** tất cả serialization (`.env.json`, `history.json`) dùng `vim.json.encode/decode`. Không dùng `vim.fn.json_encode/decode`.

---

## 🚀 Tầm nhìn v2.0 (ngoài MVP)
1. **Assertion Testing** — `@expect status 200`, `@expect body.id exists`.
2. **Tree-sitter Parsing** — lấy body object từ biến truyền vào `axios.post(url, data)`.
3. **OpenAPI / Swagger Import** — parse `swagger.json` thành list request.
4. **GraphQL support** — detect query/mutation blocks.
5. **Request chaining** — dùng response field làm input cho request tiếp theo (`{{$prev.body.token}}`).
6. **WebSocket / SSE** viewer.

---

## 📊 Definition of Done cho v1.0

### Parser
- [ ] Parse raw cURL (`-X`, `-H`, `-d`) thành request object chính xác.
- [ ] Parse `GET https://...`, `POST /users` — trích đúng method + URL.
- [ ] Parse Rails DSL: `get '/users'`, `post '/login'` (và Express `router.delete('/x')`).
- [ ] Parse directive `@courier.body`, `@courier.header`, `@courier.query`, `@courier.form` trong comment liền kề.
- [ ] Bỏ qua URL trong comment thường (không phải directive).
- [ ] Khi thiếu method → prompt hỏi (không tự default GET).
- [ ] SDK parsing (`axios.post`, `fetch`, `http.Get`) **dời sang v1.1** — không nằm trong v1.0 DoD.

### Environment
- [ ] Load `.env.json` bằng `vim.json.decode`, ghép `base_url` với relative path.
- [ ] Merge headers mặc định của env vào request.
- [ ] Substitute `{{VAR}}` từ `variables` và `{{$env.X}}` từ OS env.
- [ ] Chuyển env qua `:Courier env`, state được share toàn Neovim.

### Request
- [ ] Gửi POST với body từ visual selection.
- [ ] Gửi POST với body từ `@courier.body` directive trong comment liền kề.
- [ ] Inject `Authorization: Bearer {{TOKEN}}` từ `.env.json`.
- [ ] Prompt giá trị cho `/users/:id`, cache trong session.
- [ ] Cancel request đang pending qua `:Courier cancel`.

### UI
- [ ] Response ghi vào **scratch buffer** `courier://response/<n>`, không phải render trực tiếp vào window.
- [ ] Float là default view, render response < 50ms (overhead plugin, không tính network).
- [ ] Promote float → split (`s`), vsplit (`v`), tab (`t`) giữ nguyên scroll/state.
- [ ] Status code có màu theo class (2xx xanh / 3xx vàng / 4xx-5xx đỏ).
- [ ] JSON body được prettify + treesitter highlight.
- [ ] Đóng view bằng `q` / `<Esc>` — buffer vẫn còn trong list.
- [ ] Copy body bằng `y`, copy full bằng `yy`.
- [ ] Giới hạn 10 response buffer gần nhất, LRU wipe khi vượt.
- [ ] `:Courier history` mở entry bằng split (không phải float).

### History
- [ ] `<leader>rr` gửi lại request gần nhất.
- [ ] History persist qua session bằng `vim.json.encode/decode`, giới hạn 100 entries.
- [ ] Mỗi entry lưu đủ `{ timestamp, method, url, status, duration_ms, env, file, line }`.
- [ ] Picker hiển thị history có action "jump to source" dùng `file` + `line`.
- [ ] Mở history qua picker (Telescope hoặc `vim.ui.select`).

### Rails
- [ ] `:Courier rails` load và cache `rails routes`.
- [ ] `:Courier rails refresh` invalidate cache.
- [ ] Tất cả subcommand có tab-completion (gợi ý `send`, `repeat`, `env`, `history`, `cancel`, `rails`, `health`).

### Chất lượng
- [ ] Telescope là optional (plugin chạy được khi không cài).
- [ ] Error messages rõ ràng cho 3 loại lỗi (network / HTTP / parse).
- [ ] `:checkhealth courier` báo trạng thái: Neovim version ≥ 0.10, curl version, env loaded, telescope available.
- [ ] Toàn bộ JSON I/O dùng `vim.json.*` — không có chỗ nào gọi `vim.fn.json_*`.

---

## 🎥 Ví dụ Trải nghiệm sau khi hoàn thành v1.0

Các kịch bản chi tiết (setup, `.env.json` mẫu, 8 use case end-to-end) được tách sang file riêng:

👉 [`specs/example/v1-usage.md`](./example/v1-usage.md)

File đó đóng vai trò "kim chỉ nam UX" — mô tả chính xác những gì user sẽ thấy khi dùng plugin. Khi implement một feature, đối chiếu với kịch bản tương ứng để verify hành vi.

---

## 🎬 Next Step — Thứ tự implement đề xuất

1. **Parser core** (`parser/http.lua` + `parser/curl.lua`) — nền tảng cho mọi thứ.
2. **HTTP client** (`http_client.lua`) — async + cancel.
3. **Floating UI** (`ui/float.lua` + `ui/render.lua`) — có thể làm song song với (2).
4. **Env loader** (`env.lua`) — đơn giản, làm sau khi parser xong.
5. **History** + **Repeat** — sau khi (1)(2)(3) đã chạy end-to-end.
6. **Rails integration** — cuối cùng, sau khi core ổn.
