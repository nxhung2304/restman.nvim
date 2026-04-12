-- Manual test for restman parser directives
-- Run with: :luafile lua/restman/parser/directives_test.lua

local project_root = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h:h")
package.path = project_root .. "/lua/?.lua;" .. package.path

local directives = require("restman.parser.directives")

-- Test helper functions
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
    error(string.format("%s: expected '%s' but got '%s'", context or "assertion failed", expected, actual))
  end
end

local function assert_not_nil(value, context)
  if value == nil then
    error(string.format("%s: value is nil", context or "assertion failed"))
  end
end

local function assert_deep_eq(actual, expected, context)
  if type(actual) ~= type(expected) then
    error(
      string.format("%s: type mismatch - expected %s but got %s", context or "assertion failed", type(expected), type(actual))
    )
  end

  if type(actual) == "table" then
    for k, v in pairs(expected) do
      assert_deep_eq(actual[k], v, context .. "." .. tostring(k))
    end
  else
    if actual ~= expected then
      error(string.format("%s: expected '%s' but got '%s'", context or "assertion failed", expected, actual))
    end
  end
end

-- Create a mock buffer for testing
local function create_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

-- ========== TEST CASES ==========

print("\n=== Directives Parser Tests ===\n")

-- Test 1: Single-line body directive
test_case("Single-line @restman.body with JSON", function()
  local lines = {
    '-- @restman.body { "name": "Alice" }',
    "POST http://localhost:3000/users",
  }
  local bufnr = create_buffer(lines)
  local result = directives.scan_above(bufnr, 2)

  assert_not_nil(result.body, "body should not be nil")
  assert_eq(type(result.body), "table", "body should be a table (parsed JSON)")
  assert_eq(result.body.name, "Alice", "body.name should be 'Alice'")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Test 2: Multi-line body directive (scenario #5)
test_case("Multi-line @restman.body (scenario #5)", function()
  local lines = {
    '-- @restman.body {',
    '--   "title": "New article",',
    '--   "tags": ["lua", "neovim"]',
    '-- }',
    "-- @restman.header Idempotency-Key: 7f3a",
    "POST /api/{{API_VERSION}}/articles",
  }
  local bufnr = create_buffer(lines)
  local result = directives.scan_above(bufnr, 6)

  assert_not_nil(result.body, "body should not be nil")
  assert_eq(type(result.body), "table", "body should be a table (parsed JSON)")
  assert_eq(result.body.title, "New article", "body.title should be 'New article'")
  assert_eq(type(result.body.tags), "table", "body.tags should be a table")
  assert_eq(#result.body.tags, 2, "body.tags should have 2 items")
  assert_eq(result.body.tags[1], "lua", "body.tags[1] should be 'lua'")
  assert_eq(result.body.tags[2], "neovim", "body.tags[2] should be 'neovim'")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Test 3: Header directive
test_case("@restman.header directive", function()
  local lines = {
    "-- @restman.header X-Trace-Id: abc-123",
    "GET http://localhost:3000/users",
  }
  local bufnr = create_buffer(lines)
  local result = directives.scan_above(bufnr, 2)

  assert_not_nil(result.headers, "headers should not be nil")
  assert_eq(result.headers["X-Trace-Id"], "abc-123", "X-Trace-Id header should be 'abc-123'")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Test 4: Multiple header directives
test_case("Multiple @restman.header directives", function()
  local lines = {
    "-- @restman.header X-Trace-Id: abc-123",
    "-- @restman.header Authorization: Bearer token",
    "GET http://localhost:3000/users",
  }
  local bufnr = create_buffer(lines)
  local result = directives.scan_above(bufnr, 3)

  assert_not_nil(result.headers, "headers should not be nil")
  assert_eq(result.headers["X-Trace-Id"], "abc-123", "X-Trace-Id header")
  assert_eq(result.headers["Authorization"], "Bearer token", "Authorization header")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Test 5: Query directive
test_case("@restman.query directive", function()
  local lines = {
    "-- @restman.query page=2",
    "-- @restman.query size=10",
    "GET http://localhost:3000/users",
  }
  local bufnr = create_buffer(lines)
  local result = directives.scan_above(bufnr, 3)

  assert_not_nil(result.query, "query should not be nil")
  assert_eq(result.query.page, "2", "query.page should be '2'")
  assert_eq(result.query.size, "10", "query.size should be '10'")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Test 6: Form directive
test_case("@restman.form directive", function()
  local lines = {
    "-- @restman.form name=Alice",
    "-- @restman.form email=alice@example.com",
    "POST http://localhost:3000/users",
  }
  local bufnr = create_buffer(lines)
  local result = directives.scan_above(bufnr, 3)

  assert_not_nil(result.form, "form should not be nil")
  assert_eq(result.form.name, "Alice", "form.name should be 'Alice'")
  assert_eq(result.form.email, "alice@example.com", "form.email should be 'alice@example.com'")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Test 7: Different comment prefix styles
test_case("Different comment prefix styles (#, //, --)", function()
  -- Test with # prefix
  local lines1 = {
    "# @restman.body {\"test\": true}",
    "GET http://localhost:3000/test",
  }
  local bufnr1 = create_buffer(lines1)
  local result1 = directives.scan_above(bufnr1, 2)
  assert_not_nil(result1.body, "body with # prefix")
  vim.api.nvim_buf_delete(bufnr1, { force = true })

  -- Test with // prefix
  local lines2 = {
    '// @restman.body {"test": true}',
    "GET http://localhost:3000/test",
  }
  local bufnr2 = create_buffer(lines2)
  local result2 = directives.scan_above(bufnr2, 2)
  assert_not_nil(result2.body, "body with // prefix")
  vim.api.nvim_buf_delete(bufnr2, { force = true })
end)

-- Test 8: Stop at blank line
test_case("Stop scanning at blank line", function()
  local lines = {
    "-- @restman.header X-Old: ignored",
    "",
    "-- @restman.header X-Valid: abc",
    "GET http://localhost:3000/users",
  }
  local bufnr = create_buffer(lines)
  local result = directives.scan_above(bufnr, 4)

  assert_not_nil(result.headers, "headers should not be nil")
  assert_not_nil(result.headers["X-Valid"], "X-Valid header should exist")
  assert_eq(result.headers["X-Valid"], "abc", "X-Valid header value")
  assert_eq(result.headers["X-Old"], nil, "X-Old header should not exist (blank line stopped scan)")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Test 9: Stop at non-comment line
test_case("Stop scanning at non-comment line", function()
  local lines = {
    "-- @restman.header X-Old: ignored",
    "some code here",
    "-- @restman.header X-Valid: abc",
    "GET http://localhost:3000/users",
  }
  local bufnr = create_buffer(lines)
  local result = directives.scan_above(bufnr, 4)

  assert_not_nil(result.headers, "headers should not be nil")
  assert_not_nil(result.headers["X-Valid"], "X-Valid header should exist")
  assert_eq(result.headers["X-Old"], nil, "X-Old header should not exist (code line stopped scan)")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Test 10: Non-namespaced directives are ignored
test_case("Non-namespaced directives are ignored", function()
  local lines = {
    "-- @body {\"should\": \"be ignored\"}",
    "-- @header X-Test: ignored",
    "-- @restman.header X-Valid: abc",
    "GET http://localhost:3000/users",
  }
  local bufnr = create_buffer(lines)
  local result = directives.scan_above(bufnr, 4)

  assert_not_nil(result.headers, "headers should not be nil")
  assert_eq(result.headers["X-Valid"], "abc", "X-Valid header should exist")
  assert_eq(result.body, nil, "body should be nil (@body ignored)")
  assert_eq(result.headers["X-Test"], nil, "X-Test header should not exist (@header ignored)")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Test 11: Invalid JSON body returns raw string
test_case("Invalid JSON body returns raw string", function()
  local lines = {
    '-- @restman.body not valid json but plain text',
    "POST http://localhost:3000/users",
  }
  local bufnr = create_buffer(lines)
  local result = directives.scan_above(bufnr, 2)

  assert_not_nil(result.body, "body should not be nil")
  assert_eq(type(result.body), "string", "body should be a string (raw)")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Test 12: Empty result when no directives
test_case("Empty result when no directives above", function()
  local lines = {
    "GET http://localhost:3000/users",
  }
  local bufnr = create_buffer(lines)
  local result = directives.scan_above(bufnr, 1)

  assert_eq(result.body, nil, "body should be nil")
  assert_eq(result.headers, nil, "headers should be nil")
  assert_eq(result.query, nil, "query should be nil")
  assert_eq(result.form, nil, "form should be nil")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

-- Test 13: Combined directives (scenario #4)
test_case("Combined directives (scenario #4)", function()
  local lines = {
    '-- @restman.body { "name": "OldValue" }',
    '-- @restman.header X-Trace-Id: abc-123',
    "POST http://localhost:3000/users",
  }
  local bufnr = create_buffer(lines)
  local result = directives.scan_above(bufnr, 3)

  assert_not_nil(result.body, "body should not be nil")
  assert_eq(result.body.name, "OldValue", "body.name should be 'OldValue'")
  assert_not_nil(result.headers, "headers should not be nil")
  assert_eq(result.headers["X-Trace-Id"], "abc-123", "X-Trace-Id header")

  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

print("\n=== All tests completed ===\n")
