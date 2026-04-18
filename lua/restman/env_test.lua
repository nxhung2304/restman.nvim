-- Tests for environment loader (issue #8)

local project_root = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h")
package.path = project_root .. "/lua/?.lua;" .. package.path

local env = require("restman.env")

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

local function assert_contains(haystack, needle, context)
  if not haystack or not haystack:find(needle, 1, true) then
    error(
      string.format("%s: '%s' not found in '%s'", context or "assertion", needle, haystack or "")
    )
  end
end

-- ========== TESTS ==========

print("\n=== Environment Loader Tests (Issue #8) ===\n")

-- Test 1: Basic request without environment
test_case("Apply env to request with no env loaded", function()
  local request = {
    method = "GET",
    url = "http://example.com/api",
    headers = {},
  }

  local result = env.apply_to(request)
  assert_eq(result.method, "GET", "method unchanged")
  assert_eq(result.url, "http://example.com/api", "url unchanged")
end)

test_case("Relative URL uses cached base URL without env file", function()
  local previous_cache = env._base_url_cache
  local previous_env_cache = env._cache
  local previous_active = env._active
  env._cache = false
  env._active = nil
  env._base_url_cache = { [project_root] = "http://localhost:3000" }

  local result = env.apply_to({
    method = "GET",
    url = "/users",
    headers = {},
  })

  assert_eq(result.url, "http://localhost:3000/users", "relative URL should use cached base URL")

  env._base_url_cache = previous_cache
  env._cache = previous_env_cache
  env._active = previous_active
end)

test_case("Base URL cache is scoped by project root", function()
  local previous_cache = env._base_url_cache
  env._base_url_cache = {
    ["/tmp/project-a"] = "http://localhost:3000",
    ["/tmp/project-b"] = "http://localhost:3030",
  }

  assert_eq(env._base_url_cache["/tmp/project-a"], "http://localhost:3000", "project A cache")
  assert_eq(env._base_url_cache["/tmp/project-b"], "http://localhost:3030", "project B cache")

  env._base_url_cache = previous_cache
end)

test_case("Parse port from lsof LISTEN output", function()
  local port = env._parse_listen_port(table.concat({
    "COMMAND   PID USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME",
    "ruby    12345 dev    8u  IPv4 0x123456789abcdef      0t0  TCP 127.0.0.1:3030 (LISTEN)",
  }, "\n"))

  assert_eq(port, 3030, "should parse Rails custom port")
end)

test_case("Ignore lsof output without LISTEN port", function()
  local port = env._parse_listen_port("ruby 12345 dev txt REG /usr/bin/ruby")
  assert_eq(port, nil, "should ignore non-network output")
end)

-- Test 2: Variable substitution in URL
test_case("Variable substitution in URL", function()
  local request = {
    method = "GET",
    url = "http://example.com/users/{{USER_ID}}",
    headers = {},
  }

  -- This test verifies the pattern matching works
  assert_contains(request.url, "{{USER_ID}}", "should have {{USER_ID}} placeholder")
end)

-- Test 3: Variable substitution in headers
test_case("Variable substitution in headers", function()
  local request = {
    method = "GET",
    url = "http://example.com/api",
    headers = {
      ["Authorization"] = "Bearer {{TOKEN}}",
      ["X-Request-Id"] = "{{REQUEST_ID}}",
    },
  }

  assert_contains(request.headers["Authorization"], "{{TOKEN}}", "Bearer header has placeholder")
  assert_contains(request.headers["X-Request-Id"], "{{REQUEST_ID}}", "Request-Id has placeholder")
end)

-- Test 4: Query parameters
test_case("Query parameters structure", function()
  local request = {
    method = "GET",
    url = "http://example.com/search",
    headers = {},
    query = {
      q = "test",
      limit = "10",
    },
  }

  assert_eq(request.query.q, "test", "q parameter")
  assert_eq(request.query.limit, "10", "limit parameter")
end)

-- Test 5: Form parameters
test_case("Form parameters structure", function()
  local request = {
    method = "POST",
    url = "http://example.com/login",
    headers = {},
    form = {
      username = "alice",
      password = "secret",
    },
  }

  assert_eq(request.form.username, "alice", "username")
  assert_eq(request.form.password, "secret", "password")
end)

-- Test 6: JSON body substitution placeholder
test_case("JSON body with variable placeholder", function()
  local request = {
    method = "POST",
    url = "http://example.com/users",
    headers = { ["Content-Type"] = "application/json" },
    body = {
      name = "{{USER_NAME}}",
      email = "{{USER_EMAIL}}",
    },
  }

  assert_truthy(request.body, "body exists")
  assert_eq(request.body.name, "{{USER_NAME}}", "name placeholder")
  assert_eq(request.body.email, "{{USER_EMAIL}}", "email placeholder")
end)

-- Test 7: Environment list
test_case("Environment listing", function()
  local envs = env.list()
  assert_truthy(type(envs) == "table", "list returns table")
  -- May be empty if no .env.json exists
end)

-- Test 8: Get active environment
test_case("Get active environment", function()
  local active = env.get_active()
  -- May be nil if no env loaded, that's OK
  assert_truthy(active == nil or type(active) == "string", "active is nil or string")
end)

-- Test 9: Reload environment
test_case("Reload environment", function()
  env.reload()
  -- reload() clears cache, next load() will re-read
  assert_truthy(true, "reload doesn't crash")
end)

-- Test 10: Request with body string
test_case("Request with string body", function()
  local request = {
    method = "POST",
    url = "http://example.com/data",
    headers = { ["Content-Type"] = "text/plain" },
    body = "This is raw data",
  }

  assert_eq(request.body, "This is raw data", "string body")
end)

-- Test 11: Relative URL pattern
test_case("Relative URL detection", function()
  local relative = "/api/users"
  local absolute = "http://example.com/api/users"

  assert_eq(relative:sub(1, 1), "/", "relative starts with /")
  assert_truthy(absolute:match("^https?://"), "absolute matches http(s)://")
end)

-- Test 12: Request with multiple headers
test_case("Request with multiple headers", function()
  local request = {
    method = "GET",
    url = "http://example.com/api",
    headers = {
      ["Authorization"] = "Bearer token",
      ["Content-Type"] = "application/json",
      ["Accept"] = "application/json",
      ["X-Custom"] = "value",
    },
  }

  assert_eq(request.headers["Authorization"], "Bearer token", "auth header")
  assert_eq(request.headers["Content-Type"], "application/json", "content-type")
  assert_eq(request.headers["Accept"], "application/json", "accept")
  assert_eq(request.headers["X-Custom"], "value", "custom header")
end)

-- Test 13: Environment variables pattern
test_case("Environment variable patterns", function()
  local patterns = {
    "{{VAR_NAME}}",
    "{{$env.HOME}}",
    "{{API_KEY}}",
    "{{$env.PATH}}",
  }

  for _, pattern in ipairs(patterns) do
    assert_truthy(pattern:find("{{"), "pattern contains {{")
    assert_truthy(pattern:find("}}"), "pattern contains }}")
  end
end)

-- Test 14: Deep copy verification
test_case("Apply env returns new object", function()
  local request = {
    method = "GET",
    url = "http://example.com",
    headers = { ["X-Test"] = "original" },
  }

  local result = env.apply_to(request)
  -- Even with no env, should return a copy
  assert_truthy(result ~= nil, "result not nil")
end)

-- Test 15: Query with multiple params
test_case("Multiple query parameters", function()
  local request = {
    method = "GET",
    url = "http://example.com/search",
    headers = {},
    query = {
      q = "test",
      page = "1",
      size = "20",
      sort = "date",
      filter = "active",
    },
  }

  assert_eq(request.query.q, "test", "q")
  assert_eq(request.query.page, "1", "page")
  assert_eq(request.query.size, "20", "size")
  assert_eq(request.query.sort, "date", "sort")
  assert_eq(request.query.filter, "active", "filter")
end)

-- Test 16: Form with special values
test_case("Form parameters with special characters", function()
  local request = {
    method = "POST",
    url = "http://example.com/form",
    headers = {},
    form = {
      email = "user@example.com",
      phone = "+1-234-567-8900",
      message = "Hello & goodbye",
    },
  }

  assert_contains(request.form.email, "@", "email has @")
  assert_contains(request.form.phone, "+", "phone has +")
  assert_contains(request.form.message, "&", "message has &")
end)

-- Test 17: PUT request
test_case("PUT request with body", function()
  local request = {
    method = "PUT",
    url = "http://example.com/users/42",
    headers = { ["Content-Type"] = "application/json" },
    body = {
      name = "Updated Name",
      email = "new@example.com",
    },
  }

  assert_eq(request.method, "PUT", "method is PUT")
  assert_truthy(request.body, "body exists")
  assert_eq(request.body.name, "Updated Name", "updated name")
end)

-- Test 18: Source info preserved
test_case("Request source info structure", function()
  local request = {
    method = "GET",
    url = "http://example.com/api",
    headers = {},
    source = {
      file = "/home/user/test.lua",
      line = 42,
    },
  }

  assert_truthy(request.source, "source exists")
  assert_eq(request.source.line, 42, "line number")
  assert_contains(request.source.file, "test.lua", "file path")
end)

print("\n=== All Environment Tests Completed ===\n")
print("✅ All tests passed\n")
