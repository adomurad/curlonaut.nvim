---@return boolean
local check_external_reqs = function()
  for _, exe in ipairs { 'curl' } do
    local is_executable = vim.fn.executable(exe) == 1
    if is_executable then
      vim.health.ok(string.format("Found executable: '%s'", exe))
    else
      vim.health.error(string.format("Could not find executable: '%s'", exe))
    end
  end

  return true
end

local check_treesitter_parser = function()
  local ok, _ = pcall(vim.treesitter.language.inspect, 'http')
  if ok then
    vim.health.ok "Treesitter 'http' parser is available"
  else
    vim.health.warn "Treesitter 'http' parser is not available. Run :TSInstall http"
  end
end

return {
  check = function()
    vim.health.start 'curlonaut.nvim'

    vim.health.info [[A curl-based REST client for Neovim]]

    check_external_reqs()
    check_treesitter_parser()
  end,
}
