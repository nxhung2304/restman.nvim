-- Manual test file for cURL parser
-- Run with: :luafile lua/restman/parser/curl_test.lua
-- Or: nvim --headless -c "luafile %"

-- Add project root to package path
local project_root = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h:h")
package.path = project_root .. "/lua/?.lua;" .. project_root .. "/lua/?/init.lua;" .. package.path

local curl = require("restman.parser.curl")

local function test_case(name, test_fn)
  local success, err = pcall(test_fn)
  if success then
    print("✓ " .. name)
  else
    print("✗ " .. name .. ": " .. tostring(err))
  end
end

local function assert_eq(actual, expected, context)
  if actual ~= expected then
    error(
      string.format(
        "Assertion failed: %s\n  Expected: %s\n  Got: %s",
        context or "",
        vim.inspect(expected),
        vim.inspect(actual)
      )
    )
  end
end

local function assert_neq(actual, unexpected, context)
  if actual == unexpected then
    error(
      string.format("Assertion failed: %s\n  Should not equal: %s", context or "", vim.inspect(unexpected))
    )
  end
end

local function assert_nil(value, context)
  if value ~= nil then
    error(string.format("Assertion failed: %s\n  Expected nil, got: %s", context or "", vim.inspect(value)))
  end
end

-- Test 1: Simple GET request with -X flag
test_case("curl -X GET with header", function()
  local lines = { 'curl -X GET http://a.com/u/42 -H "Accept: application/json"' }
  local result = curl.parse(lines, 1, "/test/file.txt")

  assert_neq(result, nil, "Result should not be nil")
  assert_eq(result.method, "GET", "Method should be GET")
  assert_eq(result.url, "http://a.com/u/42", "URL should match")
  assert_eq(result.headers["Accept"], "application/json", "Header should match")
  assert_nil(result.body, "Body should be nil")
end)

-- Test 2: POST without -X flag (inferred from -d)
test_case("POST inferred from -d flag", function()
  local lines = { 'curl http://a.com/u -d \'{"k":1}\'' }
  local result = curl.parse(lines, 1, "/test/file.txt")

  assert_neq(result, nil, "Result should not be nil")
  assert_eq(result.method, "POST", "Method should be POST (inferred)")
  assert_eq(result.url, "http://a.com/u", "URL should match")
  assert_eq(result.body, '{"k":1}', "Body should match")
end)

-- Test 3: PUT with multiple headers and file body
test_case("PUT with multiple headers and @file body", function()
  local lines = {
    'curl -X PUT http://a.com/u -H "A: 1" -H "B: 2" -d @/tmp/body.json',
  }
  local result = curl.parse(lines, 1, "/test/file.txt")

  assert_neq(result, nil, "Result should not be nil")
  assert_eq(result.method, "PUT", "Method should be PUT")
  assert_eq(result.url, "http://a.com/u", "URL should match")
  assert_eq(result.headers["A"], "1", "Header A should match")
  assert_eq(result.headers["B"], "2", "Header B should match")
  -- Body will be nil if file doesn't exist, which is expected
end)

-- Test 4: Multi-line cURL with backslash continuation
test_case("Multi-line cURL with backslash continuation", function()
  local lines = {
    'curl -X POST http://a.com/api \\',
    '  -H "Content-Type: application/json" \\',
    '  -d \'{"hello":"world"}\'',
  }
  local result = curl.parse(lines, 1, "/test/file.txt")

  assert_neq(result, nil, "Result should not be nil")
  assert_eq(result.method, "POST", "Method should be POST")
  assert_eq(result.url, "http://a.com/api", "URL should match")
  assert_eq(result.headers["Content-Type"], "application/json", "Header should match")
  assert_eq(result.body, '{"hello":"world"}', "Body should match")
end)

-- Test 5: Non-cURL line returns nil
test_case("Non-cURL line returns nil", function()
  local lines = { "GET http://example.com/api" }
  local result = curl.parse(lines, 1, "/test/file.txt")

  assert_nil(result, "Result should be nil for non-cURL line")
end)

-- Test 6: Various data flag variants
test_case("Different data flag variants", function()
  -- --data-raw
  local lines1 = { 'curl http://a.com/api --data-raw "test data"' }
  local result1 = curl.parse(lines1, 1, "/test/file.txt")
  assert_neq(result1, nil, "--data-raw should work")
  assert_eq(result1.method, "POST", "Method should be POST")

  -- --data-binary
  local lines2 = { 'curl http://a.com/api --data-binary "binary data"' }
  local result2 = curl.parse(lines2, 1, "/test/file.txt")
  assert_neq(result2, nil, "--data-binary should work")
  assert_eq(result2.body, "binary data", "Body should match")
end)

-- Test 7: GET without any flags (default)
test_case("Default GET without flags", function()
  local lines = { "curl http://example.com/users" }
  local result = curl.parse(lines, 1, "/test/file.txt")

  assert_neq(result, nil, "Result should not be nil")
  assert_eq(result.method, "GET", "Method should default to GET")
  assert_eq(result.url, "http://example.com/users", "URL should match")
end)

-- Test 8: Single quote headers
test_case("Single quote headers", function()
  local lines = { "curl http://a.com/api -H 'Authorization: Bearer token123'" }
  local result = curl.parse(lines, 1, "/test/file.txt")

  assert_neq(result, nil, "Result should not be nil")
  assert_eq(result.headers["Authorization"], "Bearer token123", "Header should match")
end)

-- Test 9: URL without protocol (edge case - still parse)
test_case("URL parsing with various formats", function()
  local lines = { "curl https://api.github.com/users/octocat" }
  local result = curl.parse(lines, 1, "/test/file.txt")

  assert_neq(result, nil, "Result should not be nil")
  assert_eq(result.url, "https://api.github.com/users/octocat", "URL should match")
end)

-- Test 10: Empty block returns nil
test_case("Empty block returns nil", function()
  local result = curl.parse({}, 1, "/test/file.txt")
  assert_nil(result, "Empty block should return nil")
end)

print("\n--- All cURL parser tests completed ---")
