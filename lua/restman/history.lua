-- History — persist, replay, and jump to source for past requests
local M = {}

local log = require("restman.log")

-- In-memory cache (includes ephemeral _bufnr, stripped on save)
M._cache = nil

local function get_history_file()
  local cfg = require("restman.config").get()
  return cfg.history.file or (vim.fn.stdpath("data") .. "/restman/history.json")
end

local function iso_timestamp()
  return os.date("%Y-%m-%dT%H:%M:%S")
end

---Load entries from disk
---@return table[] List of history entries (newest first)
function M.load()
  local path = get_history_file()
  if vim.fn.filereadable(path) == 0 then
    return {}
  end
  local lines = vim.fn.readfile(path)
  if not lines or #lines == 0 then
    return {}
  end
  local ok, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok or type(data) ~= "table" then
    return {}
  end
  return data
end

---Save entries to disk (strips ephemeral fields)
---@param entries table[] List of history entries
function M.save(entries)
  local path = get_history_file()
  local dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")

  local to_save = {}
  for _, e in ipairs(entries) do
    local clean = vim.deepcopy(e)
    clean._bufnr = nil
    table.insert(to_save, clean)
  end

  local ok, content = pcall(vim.json.encode, to_save)
  if not ok then
    log.warn("history: failed to encode entries")
    return
  end
  vim.fn.writefile({ content }, path)
end

---Append a new entry after a successful request
---@param request table Parsed request object
---@param response table Response from http_client
---@param bufnr? number Buffer number created for this response (ephemeral)
function M.append(request, response, bufnr)
  local cfg = require("restman.config").get()
  if not cfg.history.enabled then
    return
  end

  local entries = M.load()

  local env = require("restman.env")

  local entry = {
    timestamp = iso_timestamp(),
    method = request.method or "GET",
    url = request.url or "",
    status = response.status,
    duration_ms = response.duration_ms,
    env = env.get_active(),
    file = (request.source and request.source.file) or vim.fn.expand("%:p"),
    line = (request.source and request.source.line) or 0,
    request = request,
    _bufnr = bufnr,
  }

  table.insert(entries, 1, entry)

  local max = cfg.history.max_entries or 100
  while #entries > max do
    entries[#entries] = nil
  end

  M._cache = entries
  M.save(entries)
end

---Return the most recent history entry (RAM cache first, then disk)
---@return table|nil
function M.last()
  local entries = M._cache or M.load()
  return entries[1]
end

---Open picker for history entries
---@param view_mode? string View mode for replayed responses
function M.open_picker(view_mode)
  local entries = M.load()
  M._cache = entries

  if #entries == 0 then
    log.info("history: no entries yet")
    return
  end

  local picker = require("restman.ui.picker")

  picker.pick({
    items = entries,
    title = "Request History",
    format = function(entry)
      local rel_file = entry.file and vim.fn.fnamemodify(entry.file, ":~:.") or "?"
      local file_missing = entry.file and vim.fn.filereadable(entry.file) == 0
      local file_str = file_missing and ("[missing] " .. rel_file) or rel_file
      return string.format(
        "[%s] %s %s → %s  %s:%d",
        entry.timestamp and entry.timestamp:sub(1, 16) or "?",
        entry.method or "?",
        entry.url or "?",
        tostring(entry.status or "?"),
        file_str,
        entry.line or 0
      )
    end,
    on_select = function(entry)
      M._replay(entry, view_mode)
    end,
    on_secondary = function(entry)
      M._jump_to_source(entry)
    end,
  })
end

---Replay a history entry: reopen existing buffer or re-send request
---@param entry table History entry
---@param view_mode? string View mode
function M._replay(entry, view_mode)
  local buffer = require("restman.ui.buffer")
  local view = require("restman.ui.view")
  local cfg = require("restman.config").get()
  local mode = view_mode or cfg.response_view.default_view

  -- Reuse existing buffer if still valid
  if entry._bufnr and vim.api.nvim_buf_is_valid(entry._bufnr) and buffer.get(entry._bufnr) then
    view.open(entry._bufnr, mode)
    return
  end

  if not entry.request then
    log.warn("history: no request data to replay")
    return
  end

  local http_client = require("restman.http_client")
  http_client.send(entry.request, function(response)
    vim.schedule(function()
      local resp_bufnr = buffer.create(entry.request, response)
      view.open(resp_bufnr, mode)
      M.append(entry.request, response, resp_bufnr)
    end)
  end)
end

---Jump to the source file and line of a history entry
---@param entry table History entry
function M._jump_to_source(entry)
  if not entry.file or entry.file == "" then
    log.warn("history: no source file recorded for this entry")
    return
  end

  if vim.fn.filereadable(entry.file) == 0 then
    log.warn("history: source file missing: " .. entry.file)
    return
  end

  vim.cmd("edit " .. vim.fn.fnameescape(entry.file))
  vim.api.nvim_win_set_cursor(0, { math.max(entry.line or 1, 1), 0 })
end

return M
