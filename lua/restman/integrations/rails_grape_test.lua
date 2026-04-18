local project_root = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h:h")
package.path = project_root .. "/lua/?.lua;" .. package.path

local rails_grape = require("restman.integrations.rails_grape")

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

print("\n=== Rails Grape Integration Tests ===\n")

test_case("Parse Grape route line (pipe-separated format)", function()
  local route = rails_grape._parse_grape_route_line("     POST  |  /oauth/token(.:format)                                     |    |  Requires for an access token")
  assert_truthy(route, "route should parse")
  assert_eq(route.verb, "POST", "verb")
  assert_eq(route.path, "/oauth/token", "path")
end)

test_case("Parse Grape route line (space-separated format)", function()
  local route = rails_grape._parse_grape_route_line("GET /api/users(.:format) Api::Users#index")
  assert_truthy(route, "route should parse")
  assert_eq(route.verb, "GET", "verb")
  assert_eq(route.path, "/api/users", "path")
end)

test_case("Ignore Grape header row", function()
  local route = rails_grape._parse_grape_route_line("Prefix Verb Path Action")
  assert_eq(route, nil, "header should be ignored")
end)

test_case("Parse full Grape routes output (pipe-separated)", function()
  local routes = rails_grape._parse_grape_routes_output(table.concat({
    "     POST  |  /oauth/token(.:format)                                     |    |  Requires for an access token",
    "      GET  |  /oauth/token/info(.:format)                                |    |  Information for an access token",
    "      GET  |  /api/user(.:format)                                        |    |",
  }, "\n"))
  assert_eq(#routes, 3, "route count")
  assert_eq(routes[1].verb, "POST", "first verb")
  assert_eq(routes[2].verb, "GET", "second verb")
  assert_eq(routes[3].path, "/api/user", "third path")
end)

test_case("Format Grape route with description", function()
  local route = {
    verb = "POST",
    path = "/oauth/token",
    action = "Requires for an access token"
  }
  local formatted = rails_grape._format_grape_route_for_picker(route, " → %s")
  -- Should apply arrow format for Grape descriptions
  assert_truthy(formatted:find("POST"), "verb should be in output")
  assert_truthy(formatted:find("/oauth/token"), "path should be in output")
  assert_truthy(formatted:find("→"), "arrow should be in formatted output")
  assert_truthy(formatted:find("Requires for an access token"), "description should be in output")
end)

test_case("Format Grape route without description", function()
  local route = {
    verb = "GET",
    path = "/api/user",
    action = ""  -- No description
  }
  local formatted = rails_grape._format_grape_route_for_picker(route, " → %s")
  -- Should NOT apply arrow format for empty descriptions
  assert_truthy(formatted:find("GET"), "verb should be in output")
  assert_truthy(formatted:find("/api/user"), "path should be in output")
  assert_eq(formatted:find("→"), nil, "arrow should NOT be in output for empty description")
end)

test_case("Format Grape route with pipe description format", function()
  local route = {
    verb = "GET",
    path = "/oauth/token/info",
    action = "Information for an access token"
  }
  local formatted = rails_grape._format_grape_route_for_picker(route, " | %s")
  -- Should use pipe format
  assert_truthy(formatted:find("GET"), "verb should be in output")
  assert_truthy(formatted:find("/oauth/token/info"), "path should be in output")
  assert_truthy(formatted:find("|"), "pipe should be in formatted output")
  assert_truthy(formatted:find("Information for an access token"), "description should be in output")
end)

print("\n=== Rails Grape Integration Tests Complete ===\n")
