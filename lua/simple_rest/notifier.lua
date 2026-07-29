local M = {}

local spinner = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
local timer = vim.loop.new_timer()
local notify_id = nil
local i = 1

---Start the spinner notification.
---@param message? string
function M.start(message)
  message = message or 'Running request'
  i = 1
  notify_id = vim.notify(message .. ' ' .. spinner[i], vim.log.levels.INFO, { timeout = false })
  timer:start(
    100,
    100,
    vim.schedule_wrap(function()
      i = (i % #spinner) + 1
      if notify_id then
        notify_id = vim.notify(message .. ' ' .. spinner[i], vim.log.levels.INFO, { replace = notify_id })
      end
    end)
  )
end

---Stop the spinner notification.
---@param success_message? string
function M.stop(success_message)
  success_message = success_message or 'Request done!'
  if timer:is_active() then
    timer:stop()
  end
  if notify_id then
    vim.notify(success_message, vim.log.levels.INFO, { replace = notify_id, timeout = 500 })
    notify_id = nil
  end
end

return M
