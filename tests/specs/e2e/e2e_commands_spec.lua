local e2e = require 'tests.helpers.e2e'

local function has_message(messages, needle)
  for _, msg in ipairs(messages) do
    if msg:find(needle, 1, true) then
      return true
    end
  end
  return false
end

describe('e2e: commands and navigation', function()
  before_each(function()
    e2e.cleanup()
    e2e.start_server()
  end)

  after_each(function()
    e2e.stop_server()
    e2e.cleanup()
  end)

  it('copies a resolved curl command without sending it', function()
    e2e.reset_hits()
    local before = e2e.server_hits()

    local host = assert((e2e.url '/echo'):match '^http://([^/]+)')
    e2e.write_http(table.concat({
      '@host = ' .. host,
      '@target = http://{{host}}/echo',
      '',
      '###',
      '',
      'POST {{target}}',
      'Content-Type: application/json',
      '',
      '{"a":1}',
    }, '\n'))

    e2e.goto_line 'POST '
    require('curlonaut').copy_curl()

    local reg = vim.fn.getreg '"'
    assert.truthy(reg:find('curl', 1, true))
    assert.truthy(reg:find('http://' .. host .. '/echo', 1, true))
    assert.equals(before, e2e.server_hits())
  end)

  it('jumps to the next and previous request', function()
    e2e.write_http(table.concat({
      'GET ' .. e2e.url '/echo',
      '',
      '###',
      '',
      'GET ' .. e2e.url '/json',
      '',
      '###',
      '',
      'GET ' .. e2e.url '/with-header',
    }, '\n'))

    local row1 = e2e.goto_line '/echo'
    local row2 = e2e.goto_line '/json'
    local row3 = e2e.goto_line '/with-header'

    vim.api.nvim_win_set_cursor(0, { row1, 0 })
    require('curlonaut').goto_next_request()
    assert.equals(row2, vim.api.nvim_win_get_cursor(0)[1])

    require('curlonaut').goto_next_request()
    assert.equals(row3, vim.api.nvim_win_get_cursor(0)[1])

    require('curlonaut').goto_prev_request()
    assert.equals(row2, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it('warns when cancelling with no active request', function()
    local messages = e2e.capture_notifications(function()
      require('curlonaut').cancel_request()
    end)

    assert.is_true(has_message(messages, 'No active request to cancel'))
  end)

  it('clears the cookie jar for the current buffer', function()
    e2e.write_http(table.concat({
      '# @cookie-jar',
      '',
      '###',
      '',
      'GET ' .. e2e.url '/set-cookie',
    }, '\n'))

    e2e.goto_line '/set-cookie'
    e2e.run_and_wait()
    assert.truthy(table.concat(e2e.tab_lines 'cookies', '\n'):find('session', 1, true))

    require('curlonaut').clear_cookies()

    assert.truthy(table.concat(e2e.tab_lines 'cookies', '\n'):find('cleared', 1, true))
  end)
end)
