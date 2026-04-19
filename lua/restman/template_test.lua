-- Tests for template generator

local M = {}

local template = require("restman.template")

function M.test_generate_get()
  local lines = template.generate("GET")
  assert(type(lines) == "table", "lines should be a table")
  assert(#lines == 1, "GET should have 1 line")
  -- URL may vary based on ENV, just check it contains GET
  assert(lines[1]:match("^GET https?://"), "GET line should start with GET + URL")
  return true
end

function M.test_generate_post()
  local lines = template.generate("POST")
  assert(type(lines) == "table", "lines should be a table")
  assert(#lines == 2, "POST should have 2 lines")
  assert(lines[1]:match("^POST https?://"), "POST line should start with POST + URL")
  assert(lines[2] == "@restman.body {}", "body line should match")
  return true
end

function M.test_generate_case_insensitive()
  local lower = template.generate("get")
  local upper = template.generate("GET")
  local mixed = template.generate("GeT")

  assert(#lower == #upper, "case should not affect line count")
  assert(#upper == #mixed, "case should not affect line count")
  return true
end

function M.test_generate_invalid_method()
  local lines = template.generate("INVALID")
  assert(lines == nil, "invalid method should return nil")
  return true
end

function M.test_list_methods()
  local methods = template.list_methods()
  assert(type(methods) == "table", "methods should be a table")
  assert(#methods == 7, "should have 7 HTTP methods")
  return true
end

function M.test_body_methods()
  for _, method in ipairs({ "POST", "PUT", "PATCH" }) do
    local lines = template.generate(method)
    assert(#lines == 2, method .. " should have 2 lines (with body)")
  end
  return true
end

function M.test_no_body_methods()
  for _, method in ipairs({ "GET", "DELETE", "HEAD", "OPTIONS" }) do
    local lines = template.generate(method)
    assert(#lines == 1, method .. " should have 1 line (no body)")
  end
  return true
end

return M
