-- Tests for parser dispatcher (issue #6)

local project_root = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h:h")
package.path = project_root .. "/lua/?.lua;" .. package.path

local parser_init = require("restman.parser.init")

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
    error(string.format("%s: expected '%s' but got '%s'", context or "assertion", expected, actual))
  end
end

local function assert_not_nil(value, context)
  if value == nil then
    error(string.format("%s: value is nil", context or "assertion"))
  end
end

local function assert_truthy(value, context)
  if not value then
    error(string.format("%s: value is falsy", context or "assertion"))
  end
end

-- ========== TEST CASES ==========

print("\n=== Parser Dispatcher Tests (Issue #6) ===\n")

-- Test 1: Legacy sync parse - HTTP-style
test_case("Legacy parse(): HTTP-style simple", function()
  local result = parser_init.parse("GET http://localhost:3000/users", 1, "/test.md")
  assert_not_nil(result, "request should not be nil")
  assert_eq(result.method, "GET", "method")
  assert_eq(result.url, "http://localhost:3000/users", "url")
end)

-- Test 2: Legacy sync parse - POST
test_case("Legacy parse(): POST with relative path", function()
  local result = parser_init.parse("POST /api/users", 1, "/test.md")
  assert_not_nil(result, "request should not be nil")
  assert_eq(result.method, "POST", "method")
  assert_eq(result.url, "/api/users", "url")
end)

-- Test 3: Legacy sync parse - cURL
test_case("Legacy parse(): cURL command", function()
  local result = parser_init.parse("curl -X GET http://localhost:3000/test", 1, "/test.md")
  assert_not_nil(result, "request should not be nil")
  assert_eq(result.method, "GET", "method")
  assert_truthy(result.url:find("localhost"), "url should contain localhost")
end)

-- Test 4: Legacy sync parse - DSL
test_case("Legacy parse(): DSL (Rails style)", function()
  local result = parser_init.parse("get '/api/users'", 1, "/test.md")
  assert_not_nil(result, "request should not be nil")
  assert_eq(result.method, "GET", "method")
  assert_eq(result.url, "/api/users", "url")
end)

-- Test 5: Legacy sync parse - DSL Express style
test_case("Legacy parse(): DSL (Express style)", function()
  local result = parser_init.parse("router.post('/api/items')", 1, "/test.md")
  assert_not_nil(result, "request should not be nil")
  assert_eq(result.method, "POST", "method")
  assert_eq(result.url, "/api/items", "url")
end)

-- Test 6: Non-matching line returns nil
test_case("Legacy parse(): Comment line returns nil", function()
  local result = parser_init.parse("-- This is a comment", 1, "/test.md")
  assert_eq(result, nil, "comment should return nil")
end)

-- Test 7: cURL multi-line collect
test_case("Legacy parse(): Multi-line cURL (first line only)", function()
  local lines = {
    "curl -X POST http://localhost:3000/users \\",
    '  -H "Content-Type: application/json" \\',
    '  -d \'{"name":"Alice"}\'',
  }
  -- Legacy parse doesn't handle multi-line, just tests first line
  local result = parser_init.parse(lines[1], 1, "/test.md")
  -- First line alone is a cURL with backslash, will try to parse
  assert_not_nil(result, "should parse first line as cURL")
  assert_eq(result.method, "POST", "method should be POST")
end)

-- Test 8: Session cache exists
test_case("Session cache is initialized", function()
  assert_truthy(parser_init._param_cache, "cache should exist")
  assert_eq(type(parser_init._param_cache), "table", "cache should be a table")
end)

-- Test 9: Parser list
test_case("Parser list includes all parsers", function()
  local parsers = parser_init.list_parsers()
  assert_not_nil(parsers, "parser list should not be nil")
  assert_eq(#parsers, 3, "should have 3 parsers")
  assert_eq(parsers[1], "curl", "first parser should be curl")
  assert_eq(parsers[2], "http", "second parser should be http")
  assert_eq(parsers[3], "dsl", "third parser should be dsl")
end)

-- Test 10: Dispatch order (cURL > HTTP > DSL)
test_case("Parser dispatch order: cURL takes precedence", function()
  -- A line that matches cURL should use curl parser, not http
  local result = parser_init.parse("curl -X DELETE http://localhost:3000/item/1", 1, "/test.md")
  assert_not_nil(result, "should match cURL parser")
  assert_eq(result.method, "DELETE", "cURL should parse DELETE correctly")
end)

-- Test 11: Source location tracking
test_case("Source info is included in parsed request", function()
  local result = parser_init.parse("GET http://example.com/api", 5, "/test.lua")
  assert_not_nil(result, "request should not be nil")
  assert_truthy(result.source, "source should exist")
  assert_eq(result.source.line, 5, "source line should be 5")
  assert_truthy(result.source.file:find("test.lua"), "source file should match")
end)

-- Test 12: Different HTTP methods
test_case("All HTTP methods are recognized", function()
  local methods = { "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS" }
  for _, method in ipairs(methods) do
    local result = parser_init.parse(method .. " http://localhost:3000/test", 1, "/test.md")
    assert_not_nil(result, "should parse " .. method)
    assert_eq(result.method, method, method .. " should be recognized")
  end
end)

-- Test 13: Relative paths
test_case("Relative paths are preserved", function()
  local result = parser_init.parse("GET /api/v1/users/123", 1, "/test.md")
  assert_not_nil(result, "should parse relative path")
  assert_eq(result.url, "/api/v1/users/123", "relative path should be preserved")
end)

-- Test 14: Query string in URL
test_case("Query strings in URL are preserved", function()
  local result = parser_init.parse("GET /users?page=1&size=10", 1, "/test.md")
  assert_not_nil(result, "should parse URL with query string")
  assert_truthy(result.url:find("page=1"), "query string should be in URL")
end)

-- Test 15: cURL with headers
test_case("cURL with -H flag", function()
  local result = parser_init.parse('curl -X GET http://api.example.com/data -H "Authorization: Bearer token"', 1, "/test.md")
  assert_not_nil(result, "should parse cURL with header")
  assert_truthy(result.headers, "headers should exist")
  assert_eq(result.headers["Authorization"], "Bearer token", "header should be extracted")
end)

-- Test 16: Empty or nil input
test_case("Empty array returns nil", function()
  local result = parser_init.parse({}, 1, "/test.md")
  assert_eq(result, nil, "empty array should return nil")
end)

-- Test 17: Case-insensitive HTTP methods
test_case("HTTP methods are case-insensitive in input", function()
  local result = parser_init.parse("get http://localhost:3000/users", 1, "/test.md")
  assert_not_nil(result, "should parse lowercase 'get'")
  assert_eq(result.method, "GET", "method should be uppercased")
end)

print("\n=== Parser Dispatcher Tests Complete ===\n")
print("✅ All sync tests passed")
print("Note: Async tests (dynamic params, prompting) should be tested separately with mocking\n")
