local M = {}

---Extract a value from a Lua table using a dot-path string.
---Supports array indices like `items[0]` (0-based, converted to 1-based for Lua).
---@param obj table
---@param path string
---@return any
local function extract_json_path(obj, path)
  local current = obj
  -- Match parts: either `key` or `key[index]`
  for part in path:gmatch('[^.]+') do
    local key, idx = part:match('^(.-)%[(%d+)%]$')
    if key then
      current = current[key]
      if type(current) ~= 'table' then
        return nil
      end
      current = current[tonumber(idx) + 1] -- 0-based to 1-based
    else
      current = current[part]
    end
    if current == nil then
      return nil
    end
  end
  return current
end

---Evaluate response extractors and store values in session_vars.
---@param parsed SimpleRestParsedRequest
---@param result SimpleRestResponse
---@param session_vars table<string, string>
function M.evaluate(parsed, result, session_vars)
  if not parsed.response_extractors or #parsed.response_extractors == 0 then
    return
  end

  for _, extractor in ipairs(parsed.response_extractors) do
    local target = extractor.target -- e.g. "@response.body.token" or "@response.headers.x-request-id"
    local var_name = extractor.name
    local val = nil

    if target:match('^@response%.body%.') then
      local json_path = target:sub(16) -- remove "@response.body."
      local ok, body_table = pcall(vim.json.decode, result.body)
      if ok and body_table then
        val = extract_json_path(body_table, json_path)
      else
        vim.notify(
          '[curlonaut] Extractor "' .. var_name .. '" failed: response is not valid JSON',
          vim.log.levels.WARN
        )
      end
    elseif target:match('^@response%.headers%.') then
      local header_name = target:sub(19) -- remove "@response.headers."
      val = result.response_headers[header_name]
      if not val then
        -- case-insensitive fallback
        for k, v in pairs(result.response_headers) do
          if k:lower() == header_name:lower() then
            val = v
            break
          end
        end
      end
      if not val then
        vim.notify(
          '[curlonaut] Extractor "' .. var_name .. '" failed: header "' .. header_name .. '" not found',
          vim.log.levels.WARN
        )
      end
    else
      vim.notify('[curlonaut] Unknown extractor target: ' .. target, vim.log.levels.WARN)
    end

    if val ~= nil then
      session_vars[var_name] = tostring(val)
      vim.notify('[curlonaut] Set ' .. var_name .. ' = ' .. tostring(val), vim.log.levels.INFO)
    else
      session_vars[var_name] = ''
    end
  end
end

return M
