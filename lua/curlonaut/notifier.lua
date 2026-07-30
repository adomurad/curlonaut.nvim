local M = {}

---Show a completion notification.
---@param success_message? string
function M.stop(success_message)
  success_message = success_message or 'Request done!'
  vim.notify(success_message, vim.log.levels.INFO, { timeout = 2000 })
end

return M
