-- Manual test file for HTTP parser
-- Run with: :luafile lua/restman/parser/http_test.lua
-- Or: nvim --headless -c "luafile %"

-- Add project root to package path
local project_root = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h:h")
package.path = project_root .. "/lua/?.lua;" .. project_root .. "/lua/?/init.lua;" .. package.path

local http_parser = require("restman.parser.http")

local function test_case(description, line, expected)
  local result = http_parser.parse(line, 1, "test.http")
  local passed = true

  if expected == nil then
    if result ~= nil then
      passed = false
      print("❌ " .. description .. " | Expected nil, got: " .. vim.inspect(result))
    else
      print("✅ " .. description)
    end
  else
    if result == nil then
      passed = false
      print("❌ " .. description .. " | Got nil")
    elseif result.method ~= expected.method or result.url ~= expected.url then
      passed = false
      print("❌ " .. description .. " | Expected: " .. vim.inspect(expected) .. ", Got: " .. vim.inspect(result))
    else
      print("✅ " .. description)
    end
  end

  return passed
end

print("\n=== HTTP Parser Tests ===\n")

local all_passed = true

-- Acceptance criteria tests
all_passed = test_case("GET with absolute URL", "GET https://api.com/users",
  { method = "GET", url = "https://api.com/users" }) and all_passed

all_passed = test_case("POST with relative URL", "POST /users",
  { method = "POST", url = "/users" }) and all_passed

all_passed = test_case("DELETE lowercase with single quotes", "delete '/api/x'",
  { method = "DELETE", url = "/api/x" }) and all_passed

all_passed = test_case("Comment line with pattern", "# GET /api/v1/users/42",
  { method = "GET", url = "/api/v1/users/42" }) and all_passed

all_passed = test_case("Comment line with spaces", "#  POST  /api/users",
  { method = "POST", url = "/api/users" }) and all_passed

all_passed = test_case("Invalid line returns nil", "not an http request", nil) and all_passed

-- Additional edge cases
all_passed = test_case("PUT with double quotes", 'PUT "https://api.com/update"',
  { method = "PUT", url = "https://api.com/update" }) and all_passed

all_passed = test_case("PATCH without quotes", "PATCH /api/v1/resource",
  { method = "PATCH", url = "/api/v1/resource" }) and all_passed

all_passed = test_case("HEAD method", "HEAD /api/status",
  { method = "HEAD", url = "/api/status" }) and all_passed

all_passed = test_case("OPTIONS method", "OPTIONS /api/options",
  { method = "OPTIONS", url = "/api/options" }) and all_passed

all_passed = test_case("CONNECT method", "CONNECT proxy.example.com:8080",
  { method = "CONNECT", url = "proxy.example.com:8080" }) and all_passed

all_passed = test_case("TRACE method", "TRACE /api/trace",
  { method = "TRACE", url = "/api/trace" }) and all_passed

all_passed = test_case("Empty string returns nil", "", nil) and all_passed

all_passed = test_case("Only method without URL returns nil", "GET", nil) and all_passed

-- Plain URL tests (default to GET)
all_passed = test_case("Plain HTTPS URL defaults to GET", "https://api.com/users",
  { method = "GET", url = "https://api.com/users" }) and all_passed

all_passed = test_case("Plain HTTP URL defaults to GET", "http://localhost:3000/api/users",
  { method = "GET", url = "http://localhost:3000/api/users" }) and all_passed

all_passed = test_case("Plain path defaults to GET", "/api/users",
  { method = "GET", url = "/api/users" }) and all_passed

all_passed = test_case("Plain localhost URL defaults to GET", "http://localhost",
  { method = "GET", url = "http://localhost" }) and all_passed

all_passed = test_case("Plain hostname with port defaults to GET", "localhost:3000",
  { method = "GET", url = "localhost:3000" }) and all_passed

all_passed = test_case("Plain hostname defaults to GET", "localhost",
  { method = "GET", url = "localhost" }) and all_passed

all_passed = test_case("Plain domain with port defaults to GET", "api.example.com:8080",
  { method = "GET", url = "api.example.com:8080" }) and all_passed

-- Verify source structure
local result = http_parser.parse("GET /test", 42, "/path/to/file.http")
if result and result.source and result.source.file == "/path/to/file.http" and result.source.line == 42 then
  print("✅ Source structure (1-indexed line, absolute path)")
else
  print("❌ Source structure")
  all_passed = false
end

-- Verify headers and body defaults
local defaults = http_parser.parse("GET /test", 1, "test.http")
if defaults and type(defaults.headers) == "table" and defaults.body == nil then
  print("✅ Default headers = {}, body = nil")
else
  print("❌ Default headers/body")
  all_passed = false
end

print("\n=== " .. (all_passed and "ALL TESTS PASSED ✅" or "SOME TESTS FAILED ❌") .. " ===\n")
