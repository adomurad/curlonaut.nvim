local M = {}

-- Per-buffer cookie jar temp file paths.
-- Key = bufnr, value = temp file path string.
M.jar_paths = {}

---Detect the `# @cookie-jar` directive in a buffer.
-- Looks anywhere before the first request separator or method line.
-- @param bufnr integer
-- @return boolean
function M.has_cookie_jar_directive(bufnr)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for row = 0, line_count - 1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
    -- Stop scanning at first request separator or method line
    if line:match '^#+%s*$' or line:match '^%u+%s+http' then
      break
    end
    if line:match '^#%s*@cookie%-jar%s*$' then
      return true
    end
  end
  return false
end

---Get or create the cookie jar temp file path for a buffer.
-- @param bufnr integer
-- @return string|nil
function M.get_jar_path(bufnr)
  if M.jar_paths[bufnr] then
    return M.jar_paths[bufnr]
  end
  if not M.has_cookie_jar_directive(bufnr) then
    return nil
  end
  local path = vim.fn.tempname() .. '_curlonaut_cookies.txt'
  M.jar_paths[bufnr] = path
  return path
end

---Read the contents of a buffer's cookie jar file.
-- Returns nil if no jar or file doesn't exist yet.
-- @param bufnr integer
-- @return string|nil
function M.read_jar(bufnr)
  local path = M.jar_paths[bufnr]
  if not path then
    return nil
  end
  local f = io.open(path, 'r')
  if not f then
    return nil
  end
  local content = f:read '*a'
  f:close()
  return content
end

---Parse Netscape-format cookie lines into a table of cookie records.
-- Handles the #HttpOnly_ prefix used by curl for HttpOnly cookies.
-- Each record: { domain, subdomains, path, https, expires, name, value, httponly }
-- @param content string
-- @return table[]
function M.parse_cookies(content)
  local cookies = {}
  for line in (content .. '\n'):gmatch '([^\r\n]*)\r?\n' do
    if line ~= '' then
      local httponly = line:match '^#HttpOnly_' ~= nil
      -- Strip #HttpOnly_ prefix (curl marks HttpOnly cookies this way)
      local raw = line:gsub('^#HttpOnly_', '')
      -- Skip real comments and empty lines
      if not raw:match '^#' and raw ~= '' then
        local parts = vim.split(raw, '\t')
        if #parts >= 7 then
          table.insert(cookies, {
            domain = parts[1],
            subdomains = parts[2],
            path = parts[3],
            https = parts[4],
            expires = parts[5],
            name = parts[6],
            value = parts[7],
            httponly = httponly,
          })
        end
      end
    end
  end
  return cookies
end

---Format cookie records into human-readable lines for display.
-- @param cookies table[]
-- @return string[]
function M.format_cookies(cookies)
  if #cookies == 0 then
    return { '# Cookie Jar', '(D = clear, e = edit)', '', '(empty)' }
  end

  local lines = { '# Cookie Jar', '(D = clear, e = edit)', '' }
  for _, c in ipairs(cookies) do
    table.insert(lines, '---')
    table.insert(lines, 'Domain:   ' .. c.domain)
    table.insert(lines, 'Name:     ' .. c.name)
    table.insert(lines, 'Value:    ' .. c.value)
    table.insert(lines, 'Path:     ' .. c.path)
    table.insert(lines, 'Secure:   ' .. c.https)
    table.insert(lines, 'HttpOnly: ' .. (c.httponly and 'TRUE' or 'FALSE'))
    table.insert(lines, 'Expires:  ' .. (c.expires == '0' and 'Session' or os.date('%Y-%m-%d %H:%M:%S', tonumber(c.expires) or 0)))
  end
  return lines
end

---Build diagnostic lines for the cookies tab when something is off.
-- @param bufnr integer
-- @return string[]
function M.diagnostic_lines(bufnr)
  local path = M.jar_paths[bufnr]
  if not path then
    return { '# Cookie Jar', '', 'No cookie jar active for this buffer.' }
  end

  local lines = { '# Cookie Jar', '', 'Jar path: ' .. path }

  local readable = vim.fn.filereadable(path) == 1
  table.insert(lines, 'File exists: ' .. (readable and 'yes' or 'no'))

  if readable then
    local size = vim.fn.getfsize(path)
    table.insert(lines, 'File size: ' .. size .. ' bytes')

    local f = io.open(path, 'r')
    if f then
      local content = f:read '*a'
      f:close()
      table.insert(lines, '')
      table.insert(lines, '## Raw content')
      table.insert(lines, '```')
      for line in (content .. '\n'):gmatch '([^\r\n]*)\r?\n' do
        table.insert(lines, line)
      end
      table.insert(lines, '```')
    else
      table.insert(lines, 'Could not read file.')
    end
  end

  return lines
end

---Clear (delete) the cookie jar file for a buffer.
-- @param bufnr integer
-- @return boolean deleted
function M.clear_jar(bufnr)
  local path = M.jar_paths[bufnr]
  if not path then
    return false
  end
  local ok = pcall(function()
    vim.fn.delete(path)
  end)
  M.jar_paths[bufnr] = nil
  return ok
end

---Get the jar file path for editing, or nil.
-- @param bufnr integer
-- @return string|nil
function M.get_edit_path(bufnr)
  return M.jar_paths[bufnr]
end

---Clean up all temp cookie jar files (call on VimLeavePre).
function M.cleanup_all()
  for _, path in pairs(M.jar_paths) do
    pcall(function()
      vim.fn.delete(path)
    end)
  end
  M.jar_paths = {}
end

return M
