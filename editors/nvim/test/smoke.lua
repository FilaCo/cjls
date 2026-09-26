-- Headless smoke test: the buffer gets the ftplugin's options and the grammar is registered with
-- nvim-treesitter; the installer unpacks a release; the server attaches to a Cangjie buffer at its
-- package root, completes `initialize`, and exits with 0 after `shutdown`/`exit`.
--
--   cjpm build && nvim --clean --headless -u editors/nvim/test/smoke.lua
--
-- Run from the repo root. The binary defaults to target/release/bin/cjls; CJLS_BIN overrides it.

-- `/`-separated, as Neovim reports a root: on Windows the working directory comes with `\`
local repo = vim.fs.normalize(vim.fn.getcwd())
-- the repository itself, as a plugin manager installs it (plugin/editors_nvim.lua)
vim.opt.runtimepath:prepend(repo)
local bin = vim.env.CJLS_BIN or (repo .. '/target/release/bin/cjls')

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

-- The installer, against a release of the binary under test in a directory, packaged as
-- release.yml does it: `cjls-<target>/cjls` in an archive, and SHA256SUMS.
local function check_install()
  local install = require('cjls.install')
  local target, format = install.target()
  if not target then
    return -- no prebuilt binary for this platform
  end
  local exe = vim.fn.has('win32') == 1 and 'cjls.exe' or 'cjls'
  local tmp = vim.fs.normalize(vim.fn.tempname())
  local name = 'cjls-' .. target
  local archive_name = name .. '.' .. format
  local release = tmp .. '/download/v0.0.0'
  vim.fn.mkdir(tmp .. '/pkg/' .. name, 'p')
  vim.fn.mkdir(release, 'p')
  local source = vim.uv.fs_stat(bin) and bin or (bin .. '.exe')
  assert(vim.uv.fs_copyfile(source, tmp .. '/pkg/' .. name .. '/' .. exe))
  local pack = format == 'zip' and { install.tar(), '-a', '-cf' } or { install.tar(), '-czf' }
  local out = vim.system(vim.list_extend(pack, { release .. '/' .. archive_name, '-C', tmp .. '/pkg', name })):wait()
  if out.code ~= 0 then
    return 'could not pack the release: ' .. out.stderr
  end
  local f = assert(io.open(release .. '/' .. archive_name, 'rb'))
  local sum = vim.fn.sha256(f:read('*a'))
  f:close()
  vim.fn.writefile({ sum .. '  ' .. archive_name }, release .. '/SHA256SUMS')

  local result = nil
  install.install({
    version = 'v0.0.0',
    base = 'file://' .. (tmp:sub(1, 1) == '/' and '' or '/') .. tmp,
    dir = tmp .. '/data',
    on_done = function(err)
      result = err or false
    end,
  })
  if not vim.wait(TIMEOUT_MS, function() return result ~= nil end) then
    return 'the installer did not finish within ' .. TIMEOUT_MS .. ' ms'
  end
  if result then
    return 'the installer failed: ' .. result
  end
  if vim.fn.executable(tmp .. '/data/bin/' .. exe) ~= 1 or install.installed(tmp .. '/data') ~= 'v0.0.0' then
    return 'the installer left no executable v0.0.0 in ' .. tmp .. '/data'
  end
  vim.fn.delete(tmp, 'rf')
end

local function run()
  vim.cmd.edit(repo .. '/modules/cjls/src/main.cj')
  local expected_root = repo .. '/modules/cjls'

  local err = check_editor_support() or check_install()
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
  cmd = { bin },
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
