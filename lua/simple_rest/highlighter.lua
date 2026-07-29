local M = {}

local hl_ns = vim.api.nvim_create_namespace 'simple_rest_highlight'

---@param status integer
---@return string
local function status_hl_group(status)
  if status >= 200 and status < 300 then
    return 'DiagnosticOk'
  elseif status >= 300 and status < 400 then
    return 'DiagnosticWarn'
  else
    return 'DiagnosticError'
  end
end

---Apply semantic highlights to a Simple or Full tab buffer.
---@param bufnr integer
function M.highlight_buffer(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, hl_ns, 0, -1)

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for row = 0, line_count - 1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
    local line_len = #line

    -- # Request / # Response → Title
    if line:match '^# %u' then
      vim.api.nvim_buf_set_extmark(bufnr, hl_ns, row, 0, { end_col = line_len, hl_group = 'Title' })

    -- ## Headers / ## Body → Function (section headers)
    elseif line:match '^## ' then
      vim.api.nvim_buf_set_extmark(bufnr, hl_ns, row, 0, { end_col = line_len, hl_group = 'Function' })

    -- Status: XXX → color the status code
    elseif line:match '^Status: ' then
      local code_start = line:find ': ' + 2
      local hl_group = status_hl_group(tonumber(line:sub(code_start)) or 0)
      vim.api.nvim_buf_set_extmark(bufnr, hl_ns, row, code_start - 1, { end_col = line_len, hl_group = hl_group })

    -- GET / POST / PUT / PATCH / DELETE → Keyword for method, Underlined for URL
    elseif line:match '^%u+ http' then
      local space_pos = line:find ' '
      if space_pos then
        vim.api.nvim_buf_set_extmark(bufnr, hl_ns, row, 0, { end_col = space_pos - 1, hl_group = 'Keyword' })
        vim.api.nvim_buf_set_extmark(bufnr, hl_ns, row, space_pos, { end_col = line_len, hl_group = 'Underlined' })
      end

    -- Header-Name: value → Identifier for name, String for value
    -- Only match non-indented lines (skip JSON body lines)
    elseif line:match '^[^%s][^:]*: ' then
      local colon_pos = line:find ':'
      if colon_pos then
        vim.api.nvim_buf_set_extmark(bufnr, hl_ns, row, 0, { end_col = colon_pos - 1, hl_group = 'Identifier' })
        vim.api.nvim_buf_set_extmark(bufnr, hl_ns, row, colon_pos + 1, { end_col = line_len, hl_group = 'String' })
      end
    end
  end
end

---Apply semantic highlights to a Verbose tab buffer.
---@param bufnr integer
function M.highlight_verbose_buffer(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, hl_ns, 0, -1)

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for row = 0, line_count - 1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
    local line_len = #line

    -- * lines (debug/info) → Comment
    if line:match '^%* ' then
      vim.api.nvim_buf_set_extmark(bufnr, hl_ns, row, 0, { end_col = line_len, hl_group = 'Comment' })

    -- { } hex dump markers → Comment
    elseif line:match '^[{]]' then
      vim.api.nvim_buf_set_extmark(bufnr, hl_ns, row, 0, { end_col = line_len, hl_group = 'Comment' })

    -- > lines (outgoing/request) → arrow Function, rest Keyword
    elseif line:match '^> ' then
      vim.api.nvim_buf_set_extmark(bufnr, hl_ns, row, 0, { end_col = 2, hl_group = 'Function' })
      vim.api.nvim_buf_set_extmark(bufnr, hl_ns, row, 2, { end_col = line_len, hl_group = 'Keyword' })

    -- < lines (incoming/response) → arrow Identifier, rest Identifier
    elseif line:match '^< ' then
      local rest = line:sub(3)
      -- Response status line: < HTTP/1.1 200
      local status_start_in_rest = rest:find ' %d%d%d'
      if rest:match('^HTTP/') and status_start_in_rest then
        local code_start = 2 + status_start_in_rest
        local status = tonumber(rest:sub(status_start_in_rest + 1, status_start_in_rest + 3)) or 0
        local hl_group = status_hl_group(status)
        -- Base: < arrow + HTTP version → Identifier
        vim.api.nvim_buf_set_extmark(bufnr, hl_ns, row, 0, { end_col = code_start, hl_group = 'Identifier' })
        -- Status code override
        vim.api.nvim_buf_set_extmark(bufnr, hl_ns, row, code_start, { end_col = code_start + 3, hl_group = hl_group })
        -- Rest of line back to Identifier
        vim.api.nvim_buf_set_extmark(bufnr, hl_ns, row, code_start + 3, { end_col = line_len, hl_group = 'Identifier' })
      else
        vim.api.nvim_buf_set_extmark(bufnr, hl_ns, row, 0, { end_col = 2, hl_group = 'Identifier' })
        vim.api.nvim_buf_set_extmark(bufnr, hl_ns, row, 2, { end_col = line_len, hl_group = 'Identifier' })
      end
    end
  end
end

return M
