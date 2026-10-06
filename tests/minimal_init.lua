-- Minimal init for running the curlonaut.nvim test suite.
-- Used both by the top-level PlenaryBustedDirectory process and by the
-- per-spec child Neovim processes it spawns.

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')

-- Make the plugin and the test helpers importable.
vim.opt.runtimepath:prepend(root)
package.path = table.concat({ root .. '/?.lua', root .. '/lua/?.lua', package.path }, ';')

-- plenary provides the busted harness and plenary.job (a runtime dependency).
local plenary = os.getenv 'PLENARY_PATH' or vim.fn.expand '~/.local/share/nvim/lazy/plenary.nvim'
if vim.fn.isdirectory(plenary) == 1 then
  vim.opt.runtimepath:prepend(plenary)
end

-- Load plenary's plugin file so `:PlenaryBustedDirectory` exists even when
-- Neovim was started with --noplugin.
vim.cmd 'silent! runtime plugin/plenary.vim'

vim.o.swapfile = false
vim.o.shadafile = 'NONE'
vim.o.columns = 160
vim.o.lines = 50
vim.o.termguicolors = false
vim.o.more = false

vim.g.curlonaut_test_root = root
