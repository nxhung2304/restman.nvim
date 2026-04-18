local project_root = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h:h")
package.path = project_root .. "/lua/?.lua;" .. package.path

local rails = require("restman.integrations.rails")

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

print("\n=== Rails Integration Tests (Issue #15) ===\n")

test_case("Parse route line with prefix", function()
  local route = rails._parse_route_line("users GET /users(.:format) users#index")
  assert_truthy(route, "route should parse")
  assert_eq(route.verb, "GET", "verb")
  assert_eq(route.path, "/users", "path")
  assert_eq(route.action, "users#index", "action")
end)

test_case("Parse route line without prefix", function()
  local route = rails._parse_route_line("PATCH/PUT  /users/:id(.:format)  users#update")
  assert_truthy(route, "route should parse")
  assert_eq(route.verb, "PATCH", "verb")
  assert_eq(route.path, "/users/:id", "path")
end)

test_case("Ignore header row", function()
  local route = rails._parse_route_line("Prefix Verb URI Pattern Controller#Action")
  assert_eq(route, nil, "header should be ignored")
end)

test_case("Parse full routes output", function()
  local routes = rails._parse_routes_output(table.concat({
    "Prefix Verb URI Pattern Controller#Action",
    "users GET /users(.:format) users#index",
    " PATCH/PUT /users/:id(.:format) users#update",
    "DELETE /users/:id(.:format) users#destroy",
  }, "\n"))

  assert_eq(#routes, 3, "route count")
  assert_eq(routes[2].verb, "PATCH", "second verb")
  assert_eq(routes[3].action, "users#destroy", "third action")
end)

test_case("Detect stale cache by mtime", function()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  local routes_file = tmp .. "/routes.rb"
  local cache_file = tmp .. "/rails_routes.txt"

  vim.fn.writefile({ "Rails.application.routes.draw do", "end" }, routes_file)
  vim.wait(20)
  vim.fn.writefile({ "users GET /users users#index" }, cache_file)
  assert_eq(rails._cache_is_stale(routes_file, cache_file), false, "new cache should not be stale")

  vim.wait(20)
  vim.fn.writefile({ "Rails.application.routes.draw do", "resources :users", "end" }, routes_file)
  assert_eq(rails._cache_is_stale(routes_file, cache_file), true, "updated routes should be stale")
end)

print("\n=== Rails Integration Tests Complete ===\n")
