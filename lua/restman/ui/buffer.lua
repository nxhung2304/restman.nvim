-- UI Buffer layer — manage response buffers with LRU eviction

local M = {}

local render = require("restman.ui.render")

-- Module state
M._buffers = {}  -- { [bufnr] = { index, request, response, created_at } }
M._next_index = 1  -- Auto-increment counter
M._max_buffers = 10  -- LRU maximum

---Create a new response buffer
---Registers in buffer registry, applies LRU eviction if needed, and renders response
---@param request table Parsed request object
---@param response table Response object from http_client
---@return number bufnr Buffer number
function M.create(request, response)
  -- Create buffer: unlisted, scratch (no swap, no modifications on save)
  local bufnr = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(bufnr, "bufhidden", "hide")
  vim.api.nvim_buf_set_option(bufnr, "swapfile", false)

  -- Name buffer
  local buf_name = "restman://response/" .. M._next_index
  vim.api.nvim_buf_set_name(bufnr, buf_name)
  M._next_index = M._next_index + 1

  -- Register in buffer registry
  M._buffers[bufnr] = {
    index = M._next_index - 1,
    request = request,
    response = response,
    created_at = vim.fn.localtime(),
  }

  -- LRU eviction: wipe oldest buffer if we exceed max
  if vim.tbl_count(M._buffers) > M._max_buffers then
    local oldest_bufnr = nil
    local oldest_time = math.huge

    for bid, entry in pairs(M._buffers) do
      if entry.created_at < oldest_time then
        oldest_time = entry.created_at
        oldest_bufnr = bid
      end
    end

    if oldest_bufnr then
      M.wipe(oldest_bufnr)
    end
  end

  -- Render response into buffer
  render.render(bufnr, request, response)

  return bufnr
end

---Get all buffers as a list, sorted by recency (newest first)
---@return table[] List of { bufnr, index, request, response, created_at }
function M.list()
  local result = {}

  for bufnr, entry in pairs(M._buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      table.insert(result, {
        bufnr = bufnr,
        index = entry.index,
        request = entry.request,
        response = entry.response,
        created_at = entry.created_at,
      })
    end
  end

  -- Sort by created_at (newest first)
  table.sort(result, function(a, b)
    return a.created_at > b.created_at
  end)

  return result
end

---Get a specific buffer entry by bufnr
---@param bufnr number Buffer number
---@return table|nil Entry or nil if not found
function M.get(bufnr)
  return M._buffers[bufnr]
end

---Wipe (delete) a specific buffer
---Removes from registry and deletes the buffer
---@param bufnr number Buffer number
function M.wipe(bufnr)
  if M._buffers[bufnr] then
    M._buffers[bufnr] = nil
  end

  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

---Wipe all buffers
function M.wipe_all()
  local bufnrs = vim.tbl_keys(M._buffers)
  for _, bufnr in ipairs(bufnrs) do
    M.wipe(bufnr)
  end
end

return M
