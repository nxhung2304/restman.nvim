-- restman.nvim
-- Entry point for Neovim plugin

if vim.fn.has("nvim-0.10") == 0 then
  return
end

-- Lazy load the plugin
vim.api.nvim_create_user_command("Restman", function(opts)
  -- TODO: Implement subcommand dispatcher
  -- For now, just show a message
  vim.notify("[Restman] Plugin loaded. Subcommands not yet implemented.", vim.log.levels.INFO)
end, {
  nargs = "*",
  desc = "Restman.nvim - REST client for Neovim",
})
