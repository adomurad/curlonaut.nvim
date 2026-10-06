-- End-to-end test helpers for curlonaut.nvim.
--
-- These drive the real plugin: they start a mock HTTP server, write a temp
-- `.http` file, open it in a real buffer, run the request through the plugin
-- (which shells out to curl) and read the results panel buffers back.

local M = {}

local server_job
local server_port
local tmpdir
local counter = 0
local http_buf

local function root()
  return vim.g.curlonaut_test_root
end

---Start the mock HTTP server and return its port.
---@return integer
function M.start_server()
  server_port = nil
  local script = root() .. '/tests/helpers/server.py'
  server_job = vim.fn.jobstart({ 'python3', '-u', script }, {
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        local p = line:match '^PORT=(%d+)$'
        if p then
          server_port = tonumber(p)
        end
      end
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if line ~= '' then
          io.stderr:write('[server] ' .. line .. '\n')
        end
      end
    end,
    stdout_buffered = false,
  })

  local ok = vim.wait(8000, function()
    return server_port ~= nil
  end, 20)
  assert(ok and server_port, 'mock server failed to start')
  return server_port
end

function M.stop_server()
  if server_job then
    pcall(vim.fn.jobstop, server_job)
    server_job = nil
  end
  server_port = nil
end

---Build a URL pointing at the mock server.
---@param path string
---@return string
function M.url(path)
  return string.format('http://127.0.0.1:%d%s', server_port, path)
end

local function ensure_tmpdir()
  if not tmpdir then
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, 'p')
  end
  return tmpdir
end

---Write a file next to the .http fixtures. Returns the absolute path.
---@param name string
---@param content string
---@return string
function M.write_file(name, content)
  local path = ensure_tmpdir() .. '/' .. name
  local f = assert(io.open(path, 'w'))
  f:write(content)
  f:close()
  return path
end

---Write and open a `.http` file, returning its path.
---The buffer must be a real named file so `# @env-file` and multipart path
---resolution behave as they do in normal use.
---@param content string
---@return string path
function M.write_http(content)
  counter = counter + 1
  local path = M.write_file('request_' .. counter .. '.http', content)
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  vim.bo.filetype = 'http'
  http_buf = vim.api.nvim_get_current_buf()
  local ok, err = pcall(vim.treesitter.start, http_buf, 'http')
  assert(ok, 'http treesitter parser unavailable: ' .. tostring(err))
  return path
end

---Move the cursor to the first line containing `pattern` in the .http buffer.
---@param pattern string
function M.goto_line(pattern)
  if http_buf and vim.api.nvim_buf_is_valid(http_buf) then
    local win = vim.fn.bufwinid(http_buf)
    if win ~= -1 then
      vim.api.nvim_set_current_win(win)
    end
  end
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:find(pattern, 1, true) then
      vim.api.nvim_win_set_cursor(0, { i, 0 })
      return i
    end
  end
  error('no line matching ' .. pattern)
end

---@return string[]
function M.tab_lines(tab)
  local buf = vim.fn.bufnr('curlonaut://' .. tab)
  if buf == -1 then
    return {}
  end
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function status_ready()
  local buf = vim.fn.bufnr 'curlonaut://simple'
  if buf == -1 then
    return false
  end
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:match '^Status: %d+' then
      return true
    end
  end
  return false
end

---Run the request under the cursor and wait for the response to render.
---@param timeout? integer
---@return string[] simple_tab_lines
function M.run_and_wait(timeout)
  timeout = timeout or 10000
  require('curlonaut').run_request()
  local ok = vim.wait(timeout, status_ready, 10)
  assert(ok, 'request did not complete within ' .. timeout .. 'ms')
  return M.tab_lines 'simple'
end

local function body_of(lines)
  local out, started = {}, false
  for _, line in ipairs(lines) do
    if started then
      table.insert(out, line)
    elseif line == '## Body' then
      started = true
    end
  end
  return table.concat(out, '\n')
end

---Return the raw response body shown in the Simple tab.
---@return string
function M.simple_body()
  return body_of(M.tab_lines 'simple')
end

---Decode the Simple tab body as JSON (used with the server's /echo route).
---@return table
function M.echo_result()
  local raw = vim.trim(M.simple_body())
  local ok, decoded = pcall(vim.json.decode, raw)
  assert(ok and decoded, 'simple body is not valid JSON: ' .. raw)
  return decoded
end

---Run `fn` while capturing all `vim.notify` messages.
---Warnings emitted from `vim.schedule` are flushed before returning.
---@param fn fun()
---@return string[]
function M.capture_notifications(fn)
  local messages = {}
  local original = vim.notify
  vim.notify = function(msg, ...)
    table.insert(messages, tostring(msg))
  end
  local ok, err = pcall(fn)
  vim.wait(80, function()
    return false
  end, 5)
  vim.notify = original
  if not ok then
    error(err)
  end
  return messages
end

---Run the request and assert that no response was rendered (early validation
---failure). Leaves the results panel untouched.
---@param timeout? integer
function M.run_and_expect_no_response(timeout)
  timeout = timeout or 800
  require('curlonaut').run_request()
  local appeared = vim.wait(timeout, status_ready, 10)
  assert(not appeared, 'unexpected response rendered')
end

---@param s any
---@return boolean
function M.is_uuid(s)
  return type(s) == 'string'
    and s:match '^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$' ~= nil
end

---@return integer|nil
function M.server_hits()
  local raw = vim.fn.system { 'curl', '-s', M.url '/__hits' }
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok then
    return nil
  end
  return decoded.count
end

function M.reset_hits()
  vim.fn.system { 'curl', '-s', M.url '/__reset' }
end

local env_backup = {}

local function remember_env(name)
  if env_backup[name] == nil then
    env_backup[name] = { present = vim.env[name] ~= nil, value = vim.env[name] }
  end
end

---@param name string
---@param value string
function M.set_shell_env(name, value)
  remember_env(name)
  vim.env[name] = value
end

---@param name string
function M.unset_shell_env(name)
  remember_env(name)
  vim.env[name] = nil
end

---Reset all plugin state between tests.
function M.cleanup()
  pcall(function()
    require('curlonaut').close_results()
  end)
  for _, tab in ipairs { 'simple', 'full', 'verbose', 'curl', 'cookies' } do
    local buf = vim.fn.bufnr('curlonaut://' .. tab)
    if buf ~= -1 then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  if http_buf and vim.api.nvim_buf_is_valid(http_buf) then
    pcall(vim.api.nvim_buf_delete, http_buf, { force = true })
  end
  http_buf = nil
  for name, info in pairs(env_backup) do
    if info.present then
      vim.env[name] = info.value
    else
      vim.env[name] = nil
    end
  end
  env_backup = {}
  require('curlonaut.env').session_vars = {}
  require('curlonaut.cookies').cleanup_all()
end

return M
