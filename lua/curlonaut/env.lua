local M = {}

-- Session-scoped variables populated by response extractors.
M.session_vars = {}

---Find the env-file path from buffer contents.
---Looks for `# @env-file ./path/to/.env` (with # comment prefix) anywhere before the first request.
---@param bufnr integer
---@return string|nil
function M.get_env_file_path(bufnr)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for row = 0, line_count - 1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
    -- Stop scanning at first request separator or method line
    if line:match '^#+%s*$' or line:match '^%u+%s+http' then
      break
    end
    local path = line:match '^#%s*@env%-file%s+(.+)$'
    if path then
      return vim.trim(path)
    end
  end
  return nil
end

---Read a .env file and return a table of KEY=value pairs.
---Handles # comments, blank lines, and `KEY="value"` / `KEY='value'` / `KEY=value`.
---@param path string
---@return table<string, string>
function M.load_dotenv(path)
  local env = {}
  local f = io.open(path, 'r')
  if not f then
    vim.schedule(function()
      vim.notify('[curlonaut] Could not read env file: ' .. path, vim.log.levels.WARN)
    end)
    return env
  end

  for line in f:lines() do
    -- Skip blank lines and comments
    if line:match '^%s*$' or line:match '^%s*#' then
      goto continue
    end
    local key, value = line:match '^%s*([A-Za-z_][A-Za-z0-9_]*)%s*=%s*(.-)%s*$'
    if key then
      -- Strip optional surrounding quotes
      value = value:gsub('^"(.-)"$', '%1'):gsub("^'(.-)'$", '%1')
      env[key] = value
    end
    ::continue::
  end

  f:close()
  return env
end

---Get shell environment variables.
---@return table<string, string>
function M.get_shell_env()
  return vim.fn.environ()
end

---Scan buffer for inline @variable = value declarations.
---Lines like @var = @response.body.foo are response extractors, not inline vars.
---@param bufnr integer
---@return table<string, string>
function M.get_inline_vars(bufnr)
  local vars = {}
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for row = 0, line_count - 1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
    local key, value = line:match '^@([A-Za-z_][A-Za-z0-9_]*)%s*=%s*(.-)%s*$'
    if key and not value:match('^@response%.') then
      -- Strip optional surrounding quotes
      value = value:gsub('^"(.-)"$', '%1'):gsub("^'(.-)'$", '%1')
      vars[key] = value
    end
  end
  return vars
end

---Build a merged env table for a buffer.
---Priority: session vars > inline vars > .env file > shell env.
---@param bufnr integer
---@return table<string, string>
function M.build_env_table(bufnr)
  local env = {}

  -- Lowest priority: shell env
  for k, v in pairs(M.get_shell_env()) do
    env[k] = tostring(v)
  end

  -- Medium priority: .env file
  local env_file = M.get_env_file_path(bufnr)
  if env_file then
    -- Resolve relative to the .http file's directory
    local buf_path = vim.api.nvim_buf_get_name(bufnr)
    local buf_dir = vim.fn.fnamemodify(buf_path, ':h')
    local full_path = vim.fn.fnamemodify(buf_dir .. '/' .. env_file, ':p')
    local dotenv = M.load_dotenv(full_path)
    for k, v in pairs(dotenv) do
      env[k] = v
    end
  end

  -- High priority: inline @variable declarations in the .http file
  local inline = M.get_inline_vars(bufnr)
  for k, v in pairs(inline) do
    env[k] = v
  end

  -- Highest priority: session vars from response extractors
  for k, v in pairs(M.session_vars) do
    env[k] = v
  end

  return env
end

---Replace `{{VAR}}` placeholders in text with values from env_table.
---Warns if a variable is not found or empty and substitutes an empty string.
---@param text string
---@param env_table table<string, string>
---@return string
function M.substitute(text, env_table)
  local result = text:gsub('{{([A-Za-z_][A-Za-z0-9_]*)}}', function(var)
    local val = env_table[var]
    if val == nil or val == '' then
      vim.schedule(function()
        vim.notify(
          '[curlonaut] Missing env variable: ' .. var,
          vim.log.levels.WARN
        )
      end)
      return ''
    end
    return val
  end)
  return result
end

return M
