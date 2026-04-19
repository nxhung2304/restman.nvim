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

- [ ] **Request Template Generator** — `:Restman new <method>` tạo boilerplate request
  - Syntax: `:Restman new get|post|put|patch|delete|head|options`
  - Insert template tại con trỏ
  - GET/HEAD/DELETE: chỉ METHOD + URL
  - POST/PUT/PATCH: METHOD + URL + `@restman.body {}`
  - Method case-insensitive, render uppercase
  - Tab-completion

### v2.0 (Beyond MVP)

- [ ] **Assertion Testing** — `@expect status 200`, `@expect body.id exists`
- [ ] **Tree-sitter Parsing** — parse `axios.post(url, data)`, `fetch`, etc.
- [ ] **OpenAPI / Swagger Import** — parse `swagger.json` thành list request
- [ ] **GraphQL support** — detect query/mutation blocks
- [ ] **Request chaining** — `{{$prev.body.token}}`
- [ ] **WebSocket / SSE** viewer

---

