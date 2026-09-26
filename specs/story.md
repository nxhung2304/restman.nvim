# Spec
## v1.0

### Parser ✅
- [x] Parse raw cURL (`-X`, `-H`, `-d`)
- [x] Parse HTTP-style (`GET https://...`)
- [x] Parse Rails/Express DSL
- [x] Parse `@restman.*` directives
- [x] Bỏ qua URL trong comment
- [x] Prompt khi thiếu method
- [x] SDK parsing dời sang v1.1

### Environment ✅
- [x] Load `.env.json` bằng `vim.json.decode`
- [x] Merge headers từ env
- [x] Substitute `{{VAR}}` và `{{$env.VAR}}`
- [x] Chuyển env qua `:Restman env`

### Request ✅
- [x] Gửi POST với body từ visual selection
- [x] Gửi POST với body từ `@restman.body`
- [x] Inject `Authorization: Bearer {{TOKEN}}`
- [x] Prompt cho dynamic params
- [x] Cancel request đang pending

### UI ✅
- [x] Scratch buffer `restman://response/<n>`
- [x] Float default view
- [x] Promote float → split/vsplit/tab
- [x] Status code có màu
- [x] JSON prettify + highlight
- [x] Keymaps: q, H, B, R, y, yy, <CR>, s, v, t, <C-o>
- [x] LRU 10 buffers
- [x] History mở bằng split

### History ✅
- [x] `<leader>rr` repeat last
- [x] Persist qua `vim.json.*`
- [x] 100 entries LRU
- [x] Metadata: timestamp, method, url, status, duration_ms, env, file, line
- [x] Jump to source
- [x] Picker (Telescope/vim.ui.select)

### Rails ✅
- [x] `:Restman rails` load/cache routes
- [x] `:Restman rails refresh`
- [x] `:Restman rails grape`
- [x] Tab-completion all subcommands

### Chất lượng ✅
- [x] Telescope optional
- [x] 3 loại error messages
- [x] `:checkhealth restman`
- [x] `vim.json.*` only (no `vim.fn.json_*`)

---

### v1.1 (Enhancement)

- [x] **Request Template Generator** — `:Restman new [method]` tạo boilerplate request
  - `:Restman new` → hiển thị dialog picker chọn method (vim.ui.select / Telescope)
  - `:Restman new <method>` → direct insert, bypass dialog
  - Methods hỗ trợ: GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS (case-insensitive)
  - Tab-completion cho `<method>`
  - Insert template tại con trỏ:
    - GET/HEAD/DELETE: `GET https://example.com`
    - POST/PUT/PATCH: `POST https://example.com\n@restman.body {}`

---

### v1.2 (Correctness & Security — từ ChatGPT review, đã verify lại source)

- [ ] **P0 — History không được lưu resolved secret**
  - `history.append()` hiện lưu `resolved_request` (đã substitute `{{TOKEN}}` → giá trị thật) vào `history.json`
  - Đổi sang lưu request gốc (còn nguyên `{{VAR}}`), chỉ resolve env lại lúc replay
- [ ] **P1 — Environment cache phải isolated theo project root**
  - `env.lua` dùng `M._cache`/`M._active` là module-level global, không key theo project root
  - Mở 2 project khác nhau trong cùng session Neovim có thể dùng nhầm env của project khác
- [ ] **P1 — Cancellation race condition trong http_client**
  - `M._pending`/`M._cancelled` là global flag, không gắn với request instance
  - Cancel request A rồi gửi request B ngay sau đó có thể làm B bị ảnh hưởng bởi cancel state của A
- [ ] **P1 — Deep merge cho config**
  - `config.merge()` hiện chỉ merge 1 level (`vim.tbl_extend`), user set nested field (vd. `response_view.float.width`) sẽ làm mất các field còn lại (`height`, `row`, `col`, `border`)
- [ ] **P1 — Header lookup case-insensitive**
  - Header lookup (vd. `response.headers["Content-Type"]` trong `render.lua`) đang case-sensitive
  - Normalize lowercase khi parse (`http_client.parse_response`) và khi truy cập
- [ ] **P1 — Hỗ trợ duplicate header (vd. Set-Cookie)**
  - `parse_response()` hiện `headers[key] = value`, ghi đè khi có nhiều header cùng tên
  - Đổi sang giữ list giá trị cho các key có thể lặp lại; cần làm sau task case-insensitive vì đổi data shape mà mọi nơi đọc `response.headers` phải theo
- [ ] **P2 — Query encoding**
  - Query key không được `vim.uri_encode`, chỉ value được encode
  - Thứ tự query param không deterministic (`pairs()`), ảnh hưởng reproducibility/debugging
- [ ] **P2 — Dynamic param cache key collision**
  - Cache key hiện là `file_path:param_name`, không phân biệt được `/users/:id` và `/orders/:id` trong cùng file
  - Đổi key sang gồm cả request identity (vd. line hoặc method+url)
- [ ] **P2 — Tách visual-selection logic ra khỏi `commands._send()`**
  - ~100 dòng xử lý visual block (scan request line, tách header/body) hiện nằm trong `_send()`
  - Gom vào module riêng (vd. `restman.selection`), làm trước vì task orchestration bên dưới phụ thuộc vào output của bước này
- [ ] **P2 — Tách request orchestration ra khỏi `commands.lua`**
  - `_send()`/`_repeat()` hiện tự orchestrate parser → env → http_client → buffer → view → history
  - Gom use-case orchestration ra module riêng (vd. `restman.request`), `commands.lua` chỉ còn là adapter gọi vào module đó
- [ ] **P3 — Đổi tên "LRU" thành đúng bản chất (FIFO/oldest-created eviction)**
  - `buffer.lua` evict theo `created_at`, không phải theo last-access → không phải LRU thật
  - Sửa comment/docs cho đúng, hoặc implement `last_accessed` nếu cần LRU thật
- [ ] **P3 — Bổ sung `config_test.lua`**
  - Test nested config merge (vd. set `response_view.float.width` không được làm mất `height`/`row`/`col`/`border`)
- [ ] **P3 — Bổ sung `history_test.lua`**
  - Test dedup theo file:line, replay, corrupted JSON, và (sau khi P0 fix) không còn secret trong entry đã lưu
