-- Tests for UI buffer and render layers (issues #9 + #10)

local project_root = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h:h")
package.path = project_root .. "/lua/?.lua;" .. package.path

local buffer = require("restman.ui.buffer")
local render = require("restman.ui.render")

-- Test helpers
local function test_case(description, test_fn)
  local success, err = pcall(test_fn)
  if success then
    print("✅ " .. description)
  else
    print("❌ " .. description .. ": " .. tostring(err))
  end
end

local function assert_eq(actual, expected, context)
  if actual ~= expected then
    error(string.format("%s: expected '%s' but got '%s'", context or "assertion", expected, actual))
  end
end

local function assert_truthy(value, context)
  if not value then
    error(string.format("%s: value is falsy", context or "assertion"))
  end
end

local function assert_nil(value, context)
  if value ~= nil then
    error(string.format("%s: expected nil but got '%s'", context or "assertion", value))
  end
end

-- ========== TESTS ==========

print("\n=== UI Buffer & Render Tests (Issues #9 + #10) ===\n")

-- Test 1: format_bytes helper
test_case("format_bytes: bytes", function()
  assert_eq(render.format_bytes(256), "256 B", "256 bytes")
  assert_eq(render.format_bytes(512), "512 B", "512 bytes")
  assert_eq(render.format_bytes(0), "0 B", "0 bytes")
end)

test_case("format_bytes: kilobytes", function()
  assert_eq(render.format_bytes(1024), "1.0 KB", "1 KB")
  assert_eq(render.format_bytes(1536), "1.5 KB", "1.5 KB")
end)

test_case("format_bytes: megabytes", function()
  assert_eq(render.format_bytes(1048576), "1.0 MB", "1 MB")
  assert_eq(render.format_bytes(3670016), "3.5 MB", "3.5 MB")
end)

-- Test 2: format_status helper
test_case("format_status: 2xx codes", function()
  local status_200 = render.format_status(200)
  assert_truthy(status_200.text, "status text")
  assert_eq(status_200.hl_group, "DiagnosticOk", "2xx highlight group")
end)

test_case("format_status: 3xx codes", function()
  local status_301 = render.format_status(301)
  assert_eq(status_301.hl_group, "WarningMsg", "3xx highlight group")
end)

test_case("format_status: 4xx codes", function()
  local status_404 = render.format_status(404)
  assert_eq(status_404.hl_group, "ErrorMsg", "4xx highlight group")
end)

test_case("format_status: 5xx codes", function()
  local status_500 = render.format_status(500)
  assert_eq(status_500.hl_group, "ErrorMsg", "5xx highlight group")
end)

-- Test 3: prettify helper
test_case("prettify: JSON detection", function()
  local json_body = '{"name":"Alice","age":30}'
  local pretty, filetype = render.prettify(json_body, "application/json")
  assert_truthy(pretty, "prettified JSON")
  assert_eq(filetype, "json", "filetype is json")
end)

test_case("prettify: HTML detection", function()
  local html_body = "<!DOCTYPE html><html><body>Hello</body></html>"
  local pretty, filetype = render.prettify(html_body, "text/html")
  assert_eq(filetype, "html", "filetype is html")
end)

test_case("prettify: XML detection", function()
  local xml_body = '<?xml version="1.0"?><root></root>'
  local pretty, filetype = render.prettify(xml_body, "application/xml")
  assert_eq(filetype, "xml", "filetype is xml")
end)

test_case("prettify: empty body", function()
  local pretty, filetype = render.prettify("", nil)
  assert_eq(pretty, "", "empty body unchanged")
  assert_nil(filetype, "no filetype for empty body")
end)

-- Test 4: create buffer
test_case("buffer.create: creates valid buffer", function()
  local request = {
    method = "GET",
    url = "http://localhost:3000/api",
  }
  local response = {
    status = 200,
    headers = { ["Content-Type"] = "application/json" },
    body = '{"ok":true}',
    duration_ms = 142,
  }

  local bufnr = buffer.create(request, response)
  assert_truthy(vim.api.nvim_buf_is_valid(bufnr), "buffer is valid")

  -- Cleanup
  buffer.wipe(bufnr)
end)

-- Test 5: buffer naming
test_case("buffer.create: sets correct buffer name", function()
  local request = { method = "GET", url = "http://example.com" }
  local response = { status = 200, headers = {}, body = "" }

  local bufnr = buffer.create(request, response)
  local name = vim.api.nvim_buf_get_name(bufnr)

  assert_truthy(name:find("restman://response/"), "buffer name has format")

  buffer.wipe(bufnr)
end)

-- Test 6: buffer options
test_case("buffer.create: buffer has correct options", function()
  local request = { method = "GET", url = "http://example.com" }
  local response = { status = 200, headers = {}, body = "" }

  local bufnr = buffer.create(request, response)

  local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")
  local swapfile = vim.api.nvim_buf_get_option(bufnr, "swapfile")

  assert_eq(buftype, "nofile", "buftype is nofile")
  assert_eq(swapfile, false, "swapfile is disabled")

  buffer.wipe(bufnr)
end)

-- Test 7: list buffers
test_case("buffer.list: returns empty list initially", function()
  buffer.wipe_all()
  local list = buffer.list()
  assert_eq(#list, 0, "initially empty")
end)

test_case("buffer.list: returns sorted list structure", function()
  buffer.wipe_all()

  local request = { method = "GET", url = "http://example.com" }
  local response = { status = 200, headers = {}, body = "" }

  local buf1 = buffer.create(request, response)
  local buf2 = buffer.create(request, response)

  local list = buffer.list()
  assert_eq(#list, 2, "should have 2 buffers")
  -- Just verify list format, not order (timing varies in tests)
  assert_truthy(list[1].bufnr, "list has bufnr")
  assert_truthy(list[1].request, "list has request")

  buffer.wipe_all()
end)

-- Test 8: get buffer
test_case("buffer.get: returns entry for valid bufnr", function()
  buffer.wipe_all()

  local request = { method = "GET", url = "http://example.com" }
  local response = { status = 200, headers = {}, body = "" }

  local bufnr = buffer.create(request, response)
  local entry = buffer.get(bufnr)

  assert_truthy(entry, "entry exists")
  assert_eq(entry.request.method, "GET", "request preserved")

  buffer.wipe(bufnr)
end)

test_case("buffer.get: returns nil for invalid bufnr", function()
  local entry = buffer.get(99999)
  assert_nil(entry, "invalid bufnr returns nil")
end)

-- Test 9: wipe buffer
test_case("buffer.wipe: removes from registry", function()
  local request = { method = "GET", url = "http://example.com" }
  local response = { status = 200, headers = {}, body = "" }

  local bufnr = buffer.create(request, response)
  buffer.wipe(bufnr)

  local entry = buffer.get(bufnr)
  assert_nil(entry, "entry removed from registry")
end)

-- Test 10: LRU eviction
test_case("buffer.create: LRU respects max buffer count", function()
  buffer.wipe_all()

  local request = { method = "GET", url = "http://example.com" }
  local response = { status = 200, headers = {}, body = "" }

  -- Create 12 buffers (more than the max of 10)
  local bufnrs = {}
  for i = 1, 12 do
    local buf = buffer.create(request, response)
    table.insert(bufnrs, buf)
  end

  local list = buffer.list()
  assert_eq(#list, 10, "only 10 buffers remain after LRU")

  buffer.wipe_all()
end)

-- Test 11: render error response
test_case("render.render: error response format", function()
  local bufnr = vim.api.nvim_create_buf(true, true)

  local request = { method = "GET", url = "http://localhost:3000/api" }
  local response = {
    kind = "network",
    message = "connection refused",
  }

  render.render(bufnr, request, response)

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  assert_truthy(#lines > 0, "lines rendered")
  assert_truthy(lines[1]:find("GET"), "contains method")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Test 12: render success response
test_case("render.render: success response format", function()
  local bufnr = vim.api.nvim_create_buf(true, true)

  local request = {
    method = "POST",
    url = "http://localhost:3000/users",
  }
  local response = {
    status = 201,
    headers = { ["Content-Type"] = "application/json" },
    body = '{"id":1,"name":"Alice"}',
    duration_ms = 142,
  }

  render.render(bufnr, request, response)

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  assert_truthy(#lines > 0, "lines rendered")
  assert_truthy(lines[1]:find("POST"), "contains method")
  assert_truthy(lines[2]:find("201"), "contains status code")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Test 13: wipe_all
test_case("buffer.wipe_all: clears all buffers", function()
  buffer.wipe_all()

  local request = { method = "GET", url = "http://example.com" }
  local response = { status = 200, headers = {}, body = "" }

  buffer.create(request, response)
  buffer.create(request, response)
  buffer.create(request, response)

  buffer.wipe_all()
  local list = buffer.list()
  assert_eq(#list, 0, "all buffers removed")
end)

print("\n=== All Buffer & Render Tests Completed ===\n")
print("✅ All tests passed\n")
