local M = {}

local RESULTS_BUF_NAME = 'simple_rest://results'

---@return integer bufnr
local function get_or_create_buf()
  local buf = vim.fn.bufnr(RESULTS_BUF_NAME)
  if buf == -1 then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, RESULTS_BUF_NAME)
    vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buf })
    vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = buf })
    vim.api.nvim_set_option_value('swapfile', false, { buf = buf })
    vim.api.nvim_set_option_value('filetype', 'simple_rest', { buf = buf })
  end
  return buf
end

---@return integer winid or -1 if not visible
local function get_win()
  local buf = vim.fn.bufnr(RESULTS_BUF_NAME)
  if buf == -1 then
    return -1
  end
  return vim.fn.bufwinid(buf)
end

---@return boolean
function M.is_open()
  return get_win() ~= -1
end

---Open the results window on the right without stealing focus.
---@return integer winid
function M.open()
  if M.is_open() then
    return get_win()
  end

  local prev_win = vim.api.nvim_get_current_win()

  vim.cmd 'rightbelow vsplit'
  local new_win = vim.api.nvim_get_current_win()

  local buf = get_or_create_buf()
  vim.api.nvim_win_set_buf(new_win, buf)

  local total_width = vim.o.columns
  local win_width = math.floor(total_width * 0.5)
  vim.api.nvim_win_set_width(new_win, win_width)

  vim.api.nvim_set_current_win(prev_win)

  return new_win
end

---Close the results window if open.
function M.close()
  local win = get_win()
  if win ~= -1 then
    vim.api.nvim_win_close(win, false)
  end
end

---Toggle the results window open/closed.
function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

---Focus the results window if it is open.
function M.focus()
  local win = get_win()
  if win ~= -1 then
    vim.api.nvim_set_current_win(win)
  end
end

---Normalize lines: split any strings containing embedded newlines.
---@param lines string[]
---@return string[]
local function normalize_lines(lines)
  local result = {}
  for _, line in ipairs(lines) do
    if line:find '\n' then
      for split_line in line:gmatch '([^\n]*)' do
        table.insert(result, split_line)
      end
    else
      table.insert(result, line)
    end
  end
  return result
end

---Replace the entire contents of the results buffer.
---@param lines string[]
function M.set_lines(lines)
  local buf = get_or_create_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, normalize_lines(lines))
end

---Append lines to the end of the results buffer.
---@param lines string[]
function M.append_lines(lines)
  local buf = get_or_create_buf()
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, normalize_lines(lines))
end

---Clear the results buffer.
function M.clear()
  local buf = get_or_create_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
end

return M
