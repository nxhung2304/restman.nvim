-- Add project root to package.path
local project_root = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h:h")
package.path = project_root .. "/lua/?.lua;" .. project_root .. "/lua/?/init.lua;" .. package.path

local parser = require("restman.parser.dsl")

local total_tests = 0
local passed_tests = 0

---Test helper function
local function test_case(description, test_fn)
  total_tests = total_tests + 1
  local success, err = pcall(test_fn)
  if success then
    passed_tests = passed_tests + 1
    print("✅ " .. description)
  else
    print("❌ " .. description .. ": " .. tostring(err))
  end
end

---Assertion helpers
local function assert_eq(actual, expected, context)
  if actual ~= expected then
    error(string.format("%s\n  Expected: %s\n  Got: %s", context, vim.inspect(expected), vim.inspect(actual)))
  end
end

local function assert_neq(actual, unexpected, context)
  if actual == unexpected then
    error(string.format("%s\n  Should not equal: %s\n  Got: %s", context, vim.inspect(unexpected), vim.inspect(actual)))
  end
end

local function assert_nil(value, context)
  if value ~= nil then
    error(string.format("%s\n  Expected: nil\n  Got: %s", context, vim.inspect(value)))
  end
end

-- ============================================================================
-- Acceptance Criteria Tests
-- ============================================================================

-- Test 1: get '/articles/:slug/comments/:comment_id' → GET
test_case("Rails DSL: get with path params", function()
  local result = parser.parse("get '/articles/:slug/comments/:comment_id'", 1, "test.rb")
  assert_neq(result, nil, "should match")
  assert_eq(result.method, "GET", "method")
  assert_eq(result.url, "/articles/:slug/comments/:comment_id", "url")
end)

-- Test 2: post '/login' → POST
test_case("Rails DSL: post with single quotes", function()
  local result = parser.parse("post '/login'", 1, "test.rb")
  assert_neq(result, nil, "should match")
  assert_eq(result.method, "POST", "method")
  assert_eq(result.url, "/login", "url")
end)

-- Test 3: router.delete('/items/:id') → DELETE
test_case("Express DSL: router.delete with path param", function()
  local result = parser.parse("router.delete('/items/:id')", 1, "test.js")
  assert_neq(result, nil, "should match")
  assert_eq(result.method, "DELETE", "method")
  assert_eq(result.url, "/items/:id", "url")
end)

-- Test 4: app.patch("/users/:id") → PATCH
test_case("Express DSL: app.patch with double quotes", function()
  local result = parser.parse("app.patch(\"/users/:id\")", 1, "test.js")
  assert_neq(result, nil, "should match")
  assert_eq(result.method, "PATCH", "method")
  assert_eq(result.url, "/users/:id", "url")
end)

-- Test 5: getUser('/u') → nil (not a verb)
test_case("Word boundary: getUser should not match", function()
  local result = parser.parse("getUser('/u')", 1, "test.js")
  assert_nil(result, "should not match getUser")
end)

-- Test 6: get_user('/x') → nil (not a verb)
test_case("Word boundary: get_user should not match", function()
  local result = parser.parse("get_user('/x')", 1, "test.rb")
  assert_nil(result, "should not match get_user")
end)

-- ============================================================================
-- Additional DSL Pattern Tests
-- ============================================================================

test_case("Rails DSL: put with double quotes", function()
  local result = parser.parse("put \"/items/:id\"", 1, "test.rb")
  assert_neq(result, nil, "should match")
  assert_eq(result.method, "PUT", "method")
  assert_eq(result.url, "/items/:id", "url")
end)

test_case("Rails DSL: delete with backticks", function()
  local result = parser.parse("delete `/api/v1/users/:id`", 1, "test.rb")
  assert_neq(result, nil, "should match")
  assert_eq(result.method, "DELETE", "method")
  assert_eq(result.url, "/api/v1/users/:id", "url")
end)

test_case("Express DSL: api.get with nested path", function()
  local result = parser.parse("api.get('/articles/:slug/comments/:comment_id')", 1, "test.js")
  assert_neq(result, nil, "should match")
  assert_eq(result.method, "GET", "method")
  assert_eq(result.url, "/articles/:slug/comments/:comment_id", "url")
end)

test_case("Express DSL: router.post with double quotes", function()
  local result = parser.parse("router.post(\"/login\")", 1, "test.js")
  assert_neq(result, nil, "should match")
  assert_eq(result.method, "POST", "method")
  assert_eq(result.url, "/login", "url")
end)

test_case("Express DSL: app.put with backticks", function()
  local result = parser.parse("app.put(`/items/:id`)", 1, "test.js")
  assert_neq(result, nil, "should match")
  assert_eq(result.method, "PUT", "method")
  assert_eq(result.url, "/items/:id", "url")
end)

test_case("Express DSL: expressRouter.patch", function()
  local result = parser.parse("expressRouter.patch('/users/:id')", 1, "test.js")
  assert_neq(result, nil, "should match")
  assert_eq(result.method, "PATCH", "method")
  assert_eq(result.url, "/users/:id", "url")
end)

-- ============================================================================
-- Edge Cases and False Positives
-- ============================================================================

test_case("Rails DSL: with leading whitespace", function()
  local result = parser.parse("  get '/users'", 1, "test.rb")
  assert_neq(result, nil, "should match with leading space")
  assert_eq(result.method, "GET", "method")
end)

test_case("Rails DSL: with tab indentation", function()
  local result = parser.parse("\tget '/users'", 1, "test.rb")
  assert_neq(result, nil, "should match with tab")
  assert_eq(result.method, "GET", "method")
end)

test_case("Rails DSL: get without parentheses", function()
  local result = parser.parse("get '/users'", 1, "test.rb")
  assert_neq(result, nil, "should match without parens")
  assert_eq(result.method, "GET", "method")
end)

test_case("Rails DSL: get with parentheses", function()
  local result = parser.parse("get('/users')", 1, "test.rb")
  assert_neq(result, nil, "should match with parens")
  assert_eq(result.method, "GET", "method")
end)

test_case("Express DSL: with leading whitespace", function()
  local result = parser.parse("  router.get('/users')", 1, "test.js")
  assert_neq(result, nil, "should match with leading space")
  assert_eq(result.method, "GET", "method")
end)

test_case("Word boundary: GetRequest should not match", function()
  local result = parser.parse("GetRequest('/x')", 1, "test.js")
  assert_nil(result, "should not match GetRequest")
end)

test_case("Word boundary: getting should not match", function()
  local result = parser.parse("getting '/data'", 1, "test.rb")
  assert_nil(result, "should not match getting")
end)

test_case("Empty line should not match", function()
  local result = parser.parse("", 1, "test.rb")
  assert_nil(result, "should not match empty line")
end)

test_case("Nil input should not match", function()
  local result = parser.parse(nil, 1, "test.rb")
  assert_nil(result, "should not match nil")
end)

-- ============================================================================
-- Source Information Tests
-- ============================================================================

test_case("Source info: file and line should be preserved", function()
  local result = parser.parse("get '/users'", 42, "routes.rb")
  assert_neq(result, nil, "should match")
  assert_eq(result.source.file, "routes.rb", "source file")
  assert_eq(result.source.line, 42, "source line")
end)

test_case("Source info: Express should preserve source", function()
  local result = parser.parse("app.get('/x')", 99, "api.js")
  assert_neq(result, nil, "should match")
  assert_eq(result.source.file, "api.js", "source file")
  assert_eq(result.source.line, 99, "source line")
end)

-- ============================================================================
-- Response Structure Tests
-- ============================================================================

test_case("Response structure: should have empty headers", function()
  local result = parser.parse("get '/users'", 1, "test.rb")
  assert_neq(result, nil, "should match")
  assert_eq(type(result.headers), "table", "headers should be table")
  assert_eq(vim.tbl_count(result.headers), 0, "headers should be empty")
end)

test_case("Response structure: body should be nil", function()
  local result = parser.parse("get '/users'", 1, "test.rb")
  assert_neq(result, nil, "should match")
  assert_eq(result.body, nil, "body should be nil")
end)

-- ============================================================================
-- Print Summary
-- ============================================================================

print("\n" .. string.rep("=", 60))
print("DSL Parser Test Results")
print(string.rep("=", 60))
print(string.format("Passed: %d/%d tests", passed_tests, total_tests))
if passed_tests == total_tests then
  print("✅ All tests passed!")
else
  print(string.format("❌ %d test(s) failed", total_tests - passed_tests))
end
print(string.rep("=", 60))
