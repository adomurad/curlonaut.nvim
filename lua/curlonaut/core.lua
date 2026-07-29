local M = {}

local flash_ns = vim.api.nvim_create_namespace 'curlonaut_flash'

---@param bufnr? integer
---@return TSNode|nil
function M.get_request_at_cursor(bufnr)
  bufnr = bufnr or 0
  vim.treesitter.get_parser(bufnr, 'http'):parse()

  local node = vim.treesitter.get_node { bufnr = bufnr }
  while node do
    if node:type() == 'request' then
      return node
    end
    node = node:parent()
  end
end

---Flash highlight the full lines of a request block like `on_yank`.
---Treesitter ranges are [start, end) exclusive.  For `regtype = 'V'`
---(visual-line mode) we must point the finish at the last *included* line.
---When `end_col == 0` the last included line is `end_row - 1`.
---@param bufnr integer
---@param start_row integer
---@param start_col integer
---@param end_row integer  exclusive end row from treesitter
---@param end_col integer  exclusive end col from treesitter
function M.flash_request(bufnr, start_row, start_col, end_row, end_col)
  vim.api.nvim_buf_clear_namespace(bufnr, flash_ns, 0, -1)

  local finish_row = end_row
  if end_col == 0 and end_row > start_row then
    finish_row = end_row - 1
  end

  vim.highlight.range(bufnr, flash_ns, 'IncSearch', { start_row, start_col }, { finish_row, 0 }, {
    regtype = 'V',
    inclusive = true,
  })

  vim.defer_fn(function()
    vim.api.nvim_buf_clear_namespace(bufnr, flash_ns, 0, -1)
  end, 200)
end

return M
