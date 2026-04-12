-- UI View layer — window management for response buffers (float/split/vsplit/tab + promote + keymaps)

local M = {}
local log = require("restman.log")

-- Module state: current view { bufnr, winid, mode }
M._current = nil

---Setup buffer-local keymaps for response view
---@param bufnr number Buffer number
local function _setup_keymaps(bufnr)
  -- Guard: only set keymaps once per buffer
  if vim.b[bufnr].restman_keymaps_set then
    return
  end
  vim.b[bufnr].restman_keymaps_set = true

  local render = require("restman.ui.render")
  local buffer = require("restman.ui.buffer")

  local opts = { buffer = bufnr, nowait = true, silent = true }

  -- Close view: q or Esc
  vim.keymap.set("n", "q", function()
    M.close()
  end, opts)
  vim.keymap.set("n", "<Esc>", function()
    M.close()
  end, opts)

  -- Toggle headers: H
  vim.keymap.set("n", "H", function()
    local entry = buffer.get(bufnr)
    if not entry then
      return
    end
    local current_mode = vim.b[bufnr].restman_view_mode or "body"
    local new_mode = (current_mode == "headers") and "body" or "headers"
    render.render(bufnr, entry.request, entry.response, { mode = new_mode })
  end, opts)

  -- Show body: B
  vim.keymap.set("n", "B", function()
    local entry = buffer.get(bufnr)
    if not entry then
      return
    end
    render.render(bufnr, entry.request, entry.response, { mode = "body" })
  end, opts)

  -- Toggle raw: R
  vim.keymap.set("n", "R", function()
    local entry = buffer.get(bufnr)
    if not entry then
      return
    end
    local current_mode = vim.b[bufnr].restman_view_mode or "body"
    local new_mode = (current_mode == "raw") and "body" or "raw"
    render.render(bufnr, entry.request, entry.response, { mode = new_mode })
  end, opts)

  -- Yank body: y
  vim.keymap.set("n", "y", function()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 5, -1, false)
    vim.fn.setreg("+", table.concat(lines, "\n"))
    log.info("Body yanked to clipboard")
  end, opts)

  -- Yank full: yy
  vim.keymap.set("n", "yy", function()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    vim.fn.setreg("+", table.concat(lines, "\n"))
    log.info("Full response yanked to clipboard")
  end, opts)

  -- Save to file: Enter
  vim.keymap.set("n", "<CR>", function()
    vim.ui.input({ prompt = "Save to file: " }, function(path)
      if path and path ~= "" then
        local lines = vim.api.nvim_buf_get_lines(bufnr, 5, -1, false)
        local expanded_path = vim.fn.expand(path)
        vim.fn.writefile(lines, expanded_path)
        log.info("Saved to " .. expanded_path)
      end
    end)
  end, opts)

  -- Promote to split: s
  vim.keymap.set("n", "s", function()
    M.promote("split")
  end, opts)

  -- Promote to vsplit: v
  vim.keymap.set("n", "v", function()
    M.promote("vsplit")
  end, opts)

  -- Promote to tab: t
  vim.keymap.set("n", "t", function()
    M.promote("tab")
  end, opts)

  -- Open buffer list picker: C-o
  vim.keymap.set("n", "<C-o>", function()
    require("restman.ui.picker").open_buffer_list()
  end, opts)
end

---Open a response buffer in a specific view mode
---@param bufnr number Buffer number to display
---@param mode string View mode: "float" | "split" | "vsplit" | "tab"
function M.open(bufnr, mode)
  -- Validate buffer
  if not vim.api.nvim_buf_is_valid(bufnr) then
    log.error("view.open: invalid buffer " .. bufnr)
    return
  end

  -- Close existing view first
  if M._current then
    M.close()
  end

  local cfg = require("restman.config").get()

  -- Open window based on mode
  if mode == "float" then
    -- Compute float dimensions from config
    local flt_cfg = cfg.response_view.float
    local w = math.floor(vim.o.columns * flt_cfg.width)
    local h = math.floor(vim.o.lines * flt_cfg.height)
    local row = math.floor((vim.o.lines - h) / 2)
    local col = math.floor((vim.o.columns - w) / 2)

    vim.api.nvim_open_win(bufnr, true, {
      relative = flt_cfg.relative or "editor",
      width = w,
      height = h,
      row = row,
      col = col,
      border = flt_cfg.border or "rounded",
    })
  elseif mode == "split" or mode == "vsplit" then
    local split_cfg = cfg.response_view.split
    local size = split_cfg.size or 80
    vim.cmd("botright " .. size .. "vsplit")
    vim.api.nvim_win_set_buf(0, bufnr)
  elseif mode == "tab" then
    vim.cmd("tabnew")
    vim.api.nvim_win_set_buf(0, bufnr)
  else
    log.error("view.open: unknown mode " .. mode)
    return
  end

  -- Save state
  M._current = {
    bufnr = bufnr,
    winid = vim.api.nvim_get_current_win(),
    mode = mode,
  }

  -- Setup keymaps (only once per buffer)
  _setup_keymaps(bufnr)
end

---Close the current view (does not wipe buffer)
function M.close()
  if not M._current then
    return
  end

  -- Close window safely
  if vim.api.nvim_win_is_valid(M._current.winid) then
    pcall(vim.api.nvim_win_close, M._current.winid, false)
  end

  M._current = nil
end

---Promote current view to a different mode (e.g., float → split)
---@param new_mode string New view mode
function M.promote(new_mode)
  if not M._current then
    log.warn("view.promote: no active view")
    return
  end

  -- Capture current cursor position
  local cursor = vim.api.nvim_win_get_cursor(M._current.winid)
  local bufnr = M._current.bufnr

  -- Close old view
  M.close()

  -- Open new view
  M.open(bufnr, new_mode)

  -- Restore cursor position
  if vim.api.nvim_win_is_valid(M._current.winid) then
    pcall(vim.api.nvim_win_set_cursor, M._current.winid, cursor)
  end
end

return M
