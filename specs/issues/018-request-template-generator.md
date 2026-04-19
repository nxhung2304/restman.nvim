## **Status:**
- Review: Approved
- PR: Todo / Draft / Merged

## Metadata
- **Title:** Request Template Generator
- **Phase:** v1.1 Enhancement
- **GitHub Issue:** (to be filled after sync)

---

## Description
Tạo command `:Restman new [method]` để sinh boilerplate request tại cursor.
- `:Restman new` → hiển thị dialog picker (vim.ui.select / Telescope)
- `:Restman new <method>` → direct insert, bypass dialog
- Methods hỗ trợ: GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS (case-insensitive)
- Tab-completion cho `<method>`
- Insert template tại con trỏ:
  - GET/HEAD/DELETE: `GET https://example.com`
  - POST/PUT/PATCH: `POST https://example.com\n@restman.body {}`

---

## Design
No UI wireframe needed - command-line interface.

---

## Acceptance Criteria
- [ ] `:Restman new` opens picker with all HTTP methods
- [ ] `:Restman new post` inserts template directly (case-insensitive)
- [ ] `:Restman new POST` works (uppercase)
- [ ] `:Restman new PoSt` works (mixed case)
- [ ] Tab-completion shows: GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS
- [ ] GET/HEAD/DELETE template: only METHOD + URL line
- [ ] POST/PUT/PATCH template: METHOD + URL + `@restman.body {}`
- [ ] Template inserted at current cursor position
- [ ] Cursor positioned after URL for easy editing
- [ ] Fallback to vim.ui.select when Telescope unavailable

---

## Implementation Checklist
- [ ] Add command registration in `lua/restman/commands.lua`
- [ ] Create `lua/restman/template.lua` module
- [ ] Implement `vim.ui.select` method picker
- [ ] Implement Telescope picker (optional, with fallback)
- [ ] Add tab-completion for `<method>` argument
- [ ] Create template generator function per method type
- [ ] Handle case-insensitive method parsing
- [ ] Add tests for template generation
- [ ] Update `:checkhealth restman` to verify command

---

## Notes
- Template URL should use placeholder like `https://example.com`
- Body template should be empty object `{}` for JSON
- Consider adding comment hints like `# TODO: replace with actual URL`
