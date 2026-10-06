local e2e = require 'tests.helpers.e2e'

local function has_message(messages, needle)
  for _, msg in ipairs(messages) do
    if msg:find(needle, 1, true) then
      return true
    end
  end
  return false
end

describe('e2e: response extractors', function()
  before_each(function()
    e2e.cleanup()
    e2e.start_server()
  end)

  after_each(function()
    e2e.stop_server()
    e2e.cleanup()
  end)

  it('extracts nested values and array indices and reuses them', function()
    e2e.write_http(table.concat({
      'GET ' .. e2e.url '/json',
      '',
      '@ID = @response.body.items[1].id',
      '@OK = @response.body.nested.ok',
      '',
      '###',
      '',
      'GET ' .. e2e.url '/echo',
      'X-Id: {{ID}}',
      'X-Ok: {{OK}}',
    }, '\n'))

    e2e.goto_line '/json'
    e2e.run_and_wait()

    e2e.goto_line '/echo'
    e2e.run_and_wait()
    local headers = e2e.echo_result().headers

    assert.equals('8', headers['x-id'])
    assert.equals('true', headers['x-ok'])
  end)

  it('looks up response headers case-insensitively', function()
    e2e.write_http(table.concat({
      'GET ' .. e2e.url '/with-header',
      '',
      '@RID = @response.headers.X-REQUEST-ID',
      '',
      '###',
      '',
      'GET ' .. e2e.url '/echo',
      'X-Rid: {{RID}}',
    }, '\n'))

    e2e.goto_line '/with-header'
    e2e.run_and_wait()

    e2e.goto_line '/echo'
    e2e.run_and_wait()

    assert.equals('req-abc-123', e2e.echo_result().headers['x-rid'])
  end)

  it('warns when a body extractor targets a non-JSON response', function()
    e2e.write_http(table.concat({
      'GET ' .. e2e.url '/text',
      '',
      '@VAL = @response.body.token',
      '',
      '###',
      '',
      'GET ' .. e2e.url '/echo',
      'X-Val: {{VAL}}',
    }, '\n'))

    local messages = e2e.capture_notifications(function()
      e2e.goto_line '/text'
      e2e.run_and_wait()
    end)
    assert.is_true(has_message(messages, 'not valid JSON'))

    e2e.goto_line '/echo'
    e2e.run_and_wait()
    assert.equals('', e2e.echo_result().headers['x-val'] or '')
  end)

  it('warns when an extracted response header is missing', function()
    e2e.write_http(table.concat({
      'GET ' .. e2e.url '/with-header',
      '',
      '@X = @response.headers.x-nope',
    }, '\n'))

    local messages = e2e.capture_notifications(function()
      e2e.goto_line '/with-header'
      e2e.run_and_wait()
    end)

    assert.is_true(has_message(messages, 'header "x-nope" not found'))
  end)
end)
