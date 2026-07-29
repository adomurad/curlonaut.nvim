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

---Collect all `request` nodes in the document, sorted by start row.
---@param bufnr integer
---@return TSNode[]
local function collect_requests(bufnr)
  local parser = vim.treesitter.get_parser(bufnr, 'http')
  parser:parse()

  local tree = parser:trees()[1]
  if not tree then
    return {}
  end

  local requests = {}
  local function walk(node)
    if node:type() == 'request' then
      table.insert(requests, node)
      return -- don't recurse into request children
    end
    for child, _ in node:iter_children() do
      walk(child)
    end
  end

  walk(tree:root())
  return requests
end

---Find the index of the request that contains the cursor.
---@param requests TSNode[]
---@param cursor_row integer
---@return integer|nil index
local function find_request_index(requests, cursor_row)
  for i, req in ipairs(requests) do
    local start_row, _, end_row, _ = req:range()
    if cursor_row >= start_row and cursor_row < end_row then
      return i
    end
  end
  return nil
end

---Jump to the next or previous request in the buffer.
---@param bufnr? integer
---@param direction 'next' | 'prev'
---@param count? integer defaults to 1
function M.goto_request(bufnr, direction, count)
  bufnr = bufnr or 0
  count = count or 1
  local requests = collect_requests(bufnr)
  if #requests == 0 then
    vim.notify('No requests found in buffer', vim.log.levels.WARN)
    return
  end

  local cursor_row = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-based
  local current_idx = find_request_index(requests, cursor_row)
  local target_idx

  if current_idx then
    if direction == 'next' then
      target_idx = current_idx + count
    else
      target_idx = current_idx - count
    end
  else
    -- Cursor is outside any request: jump to the nearest one, then apply remaining count.
    if direction == 'next' then
      for i, req in ipairs(requests) do
        local start_row, _, _, _ = req:range()
        if start_row > cursor_row then
          target_idx = i + (count - 1)
          break
        end
      end
    else
      for i = #requests, 1, -1 do
        local _, _, end_row, _ = requests[i]:range()
        if end_row <= cursor_row then
          target_idx = i - (count - 1)
          break
        end
      end
    end
  end

  if not target_idx then
    return
  end

  -- Clamp to valid range (no wrap-around).
  target_idx = math.max(1, math.min(target_idx, #requests))

  if current_idx and target_idx == current_idx then
    -- Already at the boundary, silently do nothing.
    return
  end

  local target = requests[target_idx]
  local start_row, start_col, end_row, end_col = target:range()

  -- Jump to the method node (or the start of the request if no method found)
  local method_node
  for child, _ in target:iter_children() do
    if child:type() == 'method' then
      method_node = child
      break
    end
  end

  if method_node then
    local method_row, method_col = method_node:start()
    vim.api.nvim_win_set_cursor(0, { method_row + 1, method_col })
  else
    vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
  end
end

return M
