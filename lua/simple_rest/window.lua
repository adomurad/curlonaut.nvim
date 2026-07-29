local M = {}

local SIMPLE_BUF_NAME = 'simple_rest://simple'
local FULL_BUF_NAME = 'simple_rest://full'
local VERBOSE_BUF_NAME = 'simple_rest://verbose'
local TABS = { 'simple', 'full', 'verbose' }

---@type string
local active_tab = 'simple'

---@param tab_name string
---@return string
local function buf_name_for_tab(tab_name)
  if tab_name == 'full' then
    return FULL_BUF_NAME
  elseif tab_name == 'verbose' then
    return VERBOSE_BUF_NAME
  end
  return SIMPLE_BUF_NAME
end

---@param tab_name string
---@return integer bufnr
local function get_or_create_buf(tab_name)
  local name = buf_name_for_tab(tab_name)
  local buf = vim.fn.bufnr(name)
  if buf == -1 then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, name)
    vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buf })
    vim.api.nvim_set_option_value('bufhidden', 'hide', { buf = buf })
    vim.api.nvim_set_option_value('swapfile', false, { buf = buf })
    vim.api.nvim_set_option_value('filetype', 'simple_rest', { buf = buf })

    -- Buffer-local keymaps for tab switching
    vim.api.nvim_buf_set_keymap(buf, 'n', '<S-l>', '', {
      noremap = true,
      silent = true,
      callback = function()
        M.switch_tab('next')
      end,
    })
    vim.api.nvim_buf_set_keymap(buf, 'n', '<S-h>', '', {
      noremap = true,
      silent = true,
      callback = function()
        M.switch_tab('prev')
      end,
    })
  end
  return buf
end

---@return integer winid or -1 if not visible
local function get_results_win()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    if name:match('simple_rest://%w+$') then
      return win
    end
  end
  return -1
end

---@return boolean
function M.is_open()
  return get_results_win() ~= -1
end

---Build the winbar string showing tabs.
---@param current_tab string
---@return string
local function build_winbar(current_tab)
  local parts = {}
  for _, tab in ipairs(TABS) do
    if tab == current_tab then
      table.insert(parts, '%#TabLineSel# ' .. tab:gsub('^%l', string.upper) .. ' ')
    else
      table.insert(parts, '%#TabLine# ' .. tab:gsub('^%l', string.upper) .. ' ')
    end
  end
  return table.concat(parts, '')
end

---Update the winbar on a window.
---@param winid integer
---@param tab_name string
local function set_winbar(winid, tab_name)
  vim.api.nvim_win_set_option(winid, 'winbar', build_winbar(tab_name))
end

---Open the results window on the right without stealing focus.
---@param tab_name? string defaults to active_tab or 'response'
---@return integer winid
function M.open(tab_name)
  tab_name = tab_name or active_tab
  active_tab = tab_name

  local win = get_results_win()
  if win ~= -1 then
    -- Window already open, just switch to requested tab
    local buf = get_or_create_buf(tab_name)
    vim.api.nvim_win_set_buf(win, buf)
    set_winbar(win, tab_name)
    return win
  end

  local prev_win = vim.api.nvim_get_current_win()

  vim.cmd 'rightbelow vsplit'
  local new_win = vim.api.nvim_get_current_win()

  local buf = get_or_create_buf(tab_name)
  vim.api.nvim_win_set_buf(new_win, buf)

  local total_width = vim.o.columns
  local win_width = math.floor(total_width * 0.5)
  vim.api.nvim_win_set_width(new_win, win_width)

  set_winbar(new_win, tab_name)

  vim.api.nvim_set_current_win(prev_win)

  return new_win
end

---Close the results window if open.
function M.close()
  local win = get_results_win()
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
  local win = get_results_win()
  if win ~= -1 then
    vim.api.nvim_set_current_win(win)
  end
end

---Switch to the next or previous tab.
---@param direction 'next' | 'prev'
function M.switch_tab(direction)
  local current = active_tab
  local idx = 1
  for i, tab in ipairs(TABS) do
    if tab == current then
      idx = i
      break
    end
  end

  if direction == 'next' then
    idx = (idx % #TABS) + 1
  else
    idx = ((idx - 2 + #TABS) % #TABS) + 1
  end

  local new_tab = TABS[idx]
  active_tab = new_tab

  local win = get_results_win()
  if win ~= -1 then
    local buf = get_or_create_buf(new_tab)
    vim.api.nvim_win_set_buf(win, buf)
    set_winbar(win, new_tab)
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

---Replace the entire contents of a tab buffer.
---@param tab_name string
---@param lines string[]
function M.set_tab_lines(tab_name, lines)
  local buf = get_or_create_buf(tab_name)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, normalize_lines(lines))
end

---Append lines to the end of a tab buffer.
---@param tab_name string
---@param lines string[]
function M.append_tab_lines(tab_name, lines)
  local buf = get_or_create_buf(tab_name)
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, normalize_lines(lines))
end

---Clear a tab buffer.
---@param tab_name string
function M.clear_tab(tab_name)
  local buf = get_or_create_buf(tab_name)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
end

return M
