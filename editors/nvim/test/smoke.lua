-- Headless smoke test: the buffer gets the ftplugin's options and the grammar is registered with
-- nvim-treesitter; the server attaches to a Cangjie buffer at its package root, completes
-- `initialize`, and exits with 0 after `shutdown`/`exit`.
--
--   cjpm build && nvim --clean --headless -u editors/nvim/test/smoke.lua
--
-- Run from the repo root. The binary defaults to target/release/bin/cjls; CJLS_BIN overrides it.

-- `/`-separated, as Neovim reports a root: on Windows the working directory comes with `\`
local repo = vim.fs.normalize(vim.fn.getcwd())
vim.opt.runtimepath:prepend(repo .. '/editors/nvim')

local TIMEOUT_MS = 5000
local exit_code = nil

local function fail(msg)
  io.stderr:write('FAIL: ' .. msg .. '\n')
  vim.cmd('cquit 1')
end

-- What `plugin/` and `ftplugin/` set up without the server: a Cangjie buffer's options, and the
-- grammar nvim-treesitter installs (checked against a stand-in parser table, so the test needs
-- neither nvim-treesitter nor the network).
local function check_editor_support()
  if vim.bo.commentstring ~= '// %s' or vim.bo.shiftwidth ~= 4 or not vim.bo.expandtab then
    return 'ftplugin did not apply: commentstring=' .. vim.bo.commentstring .. ', shiftwidth=' .. vim.bo.shiftwidth
  end
  if vim.filetype.match({ filename = 'a.cj.macrocall' }) ~= 'cangjie' then
    return '*.cj.macrocall is not detected as cangjie'
  end
  package.loaded['nvim-treesitter.parsers'] = {}
  vim.api.nvim_exec_autocmds('User', { pattern = 'TSUpdate' })
  local cangjie = package.loaded['nvim-treesitter.parsers'].cangjie
  package.loaded['nvim-treesitter.parsers'] = nil
  if not (cangjie and cangjie.install_info.url and cangjie.install_info.revision) then
    return 'the cangjie grammar is not registered with nvim-treesitter on TSUpdate'
  end
end

local function run()
  vim.cmd.edit(repo .. '/modules/cjls/src/main.cj')
  local expected_root = repo .. '/modules/cjls'

  local err = check_editor_support()
  if err then
    return fail(err)
  end

  local client = nil
  local attached = vim.wait(TIMEOUT_MS, function()
    client = vim.lsp.get_clients({ name = 'cjls', bufnr = 0 })[1]
    return client ~= nil and client.initialized
  end)
  if not attached then
    return fail('cjls did not attach and initialize within ' .. TIMEOUT_MS .. ' ms; see :LspLog')
  end
  if client.root_dir ~= expected_root then
    return fail('root_dir is ' .. tostring(client.root_dir) .. ', expected ' .. expected_root)
  end
  if not (client.server_info and client.server_info.name == 'cjls') then
    return fail('unexpected serverInfo: ' .. vim.inspect(client.server_info))
  end

  client:stop()
  if not vim.wait(TIMEOUT_MS, function() return exit_code ~= nil end) then
    return fail('cjls did not exit within ' .. TIMEOUT_MS .. ' ms of shutdown')
  end
  if exit_code ~= 0 then
    return fail('cjls exited with ' .. exit_code .. ' after shutdown, expected 0')
  end

  io.stdout:write('OK: attached at ' .. client.root_dir .. ', exited with 0\n')
  vim.cmd('qall!')
end

vim.lsp.config('cjls', {
  cmd = { vim.env.CJLS_BIN or (repo .. '/target/release/bin/cjls') },
  on_exit = function(code)
    exit_code = code
  end,
})
vim.lsp.enable('cjls')

-- filetype detection is switched on only after the init file, so the test waits for startup
vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    vim.schedule(run)
  end,
})
