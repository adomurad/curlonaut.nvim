local e2e = require 'tests.helpers.e2e'

describe('e2e: request cancellation', function()
  before_each(function()
    e2e.cleanup()
    e2e.start_server()
  end)

  after_each(function()
    e2e.stop_server()
    e2e.cleanup()
  end)

  it('cancels a running request', function()
    e2e.write_http('GET ' .. e2e.url '/slow?ms=5000')

    require('curlonaut').run_request()
    vim.wait(300, function()
      return false
    end, 10)
    require('curlonaut').cancel_request()

    local joined = table.concat(e2e.tab_lines 'simple', '\n')
    assert.truthy(joined:find('cancelled', 1, true))
  end)
end)
