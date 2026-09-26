-- The repository as a Neovim plugin, for plugin managers that install a whole repository
-- (lazy.nvim, vim.pack): the plugin itself is editors/nvim, which this puts on the runtimepath.
-- Neovim reads `lsp/` and `ftplugin/` from there on demand; `plugin/` is sourced here, as nothing
-- sources it for a directory added after startup.
local dir = vim.fs.joinpath(vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(debug.getinfo(1, 'S').source:sub(2)))), 'editors', 'nvim')
vim.opt.runtimepath:append(dir)
for _, file in ipairs(vim.fn.glob(vim.fs.joinpath(dir, 'plugin', '*.lua'), false, true)) do
  vim.cmd.source(file)
end
