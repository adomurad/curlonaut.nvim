local M = {}

-- Sentinel value returned by the `omit` provider so that curlonaut can strip
-- the entire key=value pair from urlencoded / multipart bodies and query strings.
M.OMIT_SENTINEL = '__curlonaut_omit__'

-- Seed math.random once for LuaJIT / Lua 5.1 compatibility.
math.randomseed(os.time())

---Generate a UUID v4 string.
---@return string
local function uuid()
  local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
  return template:gsub('[xy]', function(c)
    local v = math.random(0, 15)
    if c == 'y' then
      v = (v % 4) + 8 -- 8, 9, a, b
    end
    return string.format('%x', v)
  end)
end

---Parse optional space-separated arguments from the captured remainder.
---@param remainder string
---@return string[]
local function parse_args(remainder)
  local args = {}
  for arg in remainder:gmatch('%S+') do
    table.insert(args, arg)
  end
  return args
end

---Built-in dynamic variable providers.
---Each key is the variable name (without the `$` prefix).
---Each value is a function that receives the arguments string and returns the replacement.
---@type table<string, fun(args: string[]): string>
M.providers = {
  uuid = function(_)
    return uuid()
  end,

  guid = function(_)
    return uuid()
  end,

  timestamp = function(_)
    return tostring(os.time())
  end,

  timestampMs = function(_)
    return tostring(os.time() * 1000)
  end,

  isoTimestamp = function(_)
    return os.date('!%Y-%m-%dT%H:%M:%SZ') or ''
  end,

  randomInt = function(args)
    local min, max
    if #args >= 2 then
      min = tonumber(args[1])
      max = tonumber(args[2])
    end
    if not min or not max then
      min, max = 0, 1000
    end
    return tostring(math.random(min, max))
  end,

  randomFloat = function(args)
    local min, max
    if #args >= 2 then
      min = tonumber(args[1])
      max = tonumber(args[2])
    end
    if not min or not max then
      min, max = 0, 1
    end
    return tostring(math.random() * (max - min) + min)
  end,

  randomBool = function(_)
    return math.random(0, 1) == 1 and 'true' or 'false'
  end,

  randomHex = function(args)
    local n = tonumber(args[1]) or 16
    local hex = {}
    for _ = 1, n do
      table.insert(hex, string.format('%x', math.random(0, 15)))
    end
    return table.concat(hex)
  end,

  date = function(args)
    local fmt = table.concat(args, ' ')
    if fmt == '' then
      fmt = '%Y-%m-%d'
    end
    return os.date(fmt) or ''
  end,

  omit = function(_)
    return M.OMIT_SENTINEL
  end,
}

---Replace dynamic `{{$name}}` and `{{$name arg1 arg2}}` placeholders in text.
---Warns if a provider is not found and substitutes an empty string.
---Each occurrence is evaluated independently (different values per call).
---@param text string
---@return string
function M.substitute(text)
  return text:gsub('{{%$([A-Za-z_][A-Za-z0-9_]*)([^}]*)}}', function(name, remainder)
    local provider = M.providers[name]
    if not provider then
      vim.schedule(function()
        vim.notify('[curlonaut] Unknown dynamic variable: $' .. name, vim.log.levels.WARN)
      end)
      return ''
    end
    local args = parse_args(remainder)
    return provider(args)
  end)
end

return M
