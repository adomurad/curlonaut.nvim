local e2e = require 'tests.helpers.e2e'

local function host()
  return assert((e2e.url '/echo'):match '^http://([^/]+)')
end

describe('e2e: variable resolution', function()
  before_each(function()
    e2e.cleanup()
    e2e.start_server()
  end)

  after_each(function()
    e2e.stop_server()
    e2e.cleanup()
  end)

  it('resolves a multi-level variable chain in the URL', function()
    e2e.write_http(table.concat({
      '@host = ' .. host(),
      '@api = http://{{host}}',
      '@target = {{api}}/echo',
      '',
      '###',
      '',
      'GET {{target}}',
    }, '\n'))

    e2e.goto_line 'GET '
    local lines = e2e.run_and_wait()

    assert.truthy(table.concat(lines, '\n'):find('Status: 200', 1, true))
    assert.equals('/echo', e2e.echo_result().path)
  end)

  it('resolves a variable chain in headers and body', function()
    e2e.write_http(table.concat({
      '@host = ' .. host(),
      '@api = http://{{host}}',
      '@target = {{api}}/echo',
      '',
      '###',
      '',
      'POST {{target}}',
      'Content-Type: text/plain',
      'X-Chain: {{target}}',
      '',
      'v={{host}}',
    }, '\n'))

    e2e.goto_line 'POST '
    e2e.run_and_wait()
    local result = e2e.echo_result()

    assert.equals('http://' .. host() .. '/echo', result.headers['x-chain'])
    assert.equals('v=' .. host(), vim.trim(result.body))
  end)

  it('gives different values to two direct dynamic occurrences', function()
    e2e.write_http(table.concat({
      'GET ' .. e2e.url '/echo',
      'X-A: {{$uuid}}',
      'X-B: {{$uuid}}',
    }, '\n'))

    e2e.goto_line 'GET '
    e2e.run_and_wait()
    local headers = e2e.echo_result().headers

    assert.is_true(e2e.is_uuid(headers['x-a']))
    assert.is_true(e2e.is_uuid(headers['x-b']))
    assert.is_true(headers['x-a'] ~= headers['x-b'])
  end)

  it('reuses the same value when a dynamic var is stored in an inline var', function()
    e2e.write_http(table.concat({
      '@my_uuid = {{$uuid}}',
      '',
      '###',
      '',
      'GET ' .. e2e.url '/echo',
      'X-A: {{my_uuid}}',
      'X-B: {{my_uuid}}',
    }, '\n'))

    e2e.goto_line 'GET '
    e2e.run_and_wait()
    local headers = e2e.echo_result().headers

    assert.is_true(e2e.is_uuid(headers['x-a']))
    assert.equals(headers['x-a'], headers['x-b'])
  end)

  it('resolves an alias chain to the same dynamic value', function()
    e2e.write_http(table.concat({
      '@my_uuid = {{$uuid}}',
      '@alias = {{my_uuid}}',
      '',
      '###',
      '',
      'GET ' .. e2e.url '/echo',
      'X-A: {{my_uuid}}',
      'X-B: {{alias}}',
    }, '\n'))

    e2e.goto_line 'GET '
    e2e.run_and_wait()
    local headers = e2e.echo_result().headers

    assert.is_true(e2e.is_uuid(headers['x-a']))
    assert.equals(headers['x-a'], headers['x-b'])
  end)

  it('reuses a session variable set by an extractor in a later request', function()
    e2e.write_http(table.concat({
      'GET ' .. e2e.url '/with-header',
      '',
      '@RID = @response.headers.x-request-id',
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

  it('lets a session variable override an inline variable of the same name', function()
    e2e.write_http(table.concat({
      '@TOKEN = inline-value',
      '',
      '###',
      '',
      'GET ' .. e2e.url '/json',
      '',
      '@TOKEN = @response.body.token',
      '',
      '###',
      '',
      'GET ' .. e2e.url '/echo',
      'X-Token: {{TOKEN}}',
    }, '\n'))

    e2e.goto_line '/json'
    e2e.run_and_wait()

    e2e.goto_line '/echo'
    e2e.run_and_wait()

    assert.equals('abc123', e2e.echo_result().headers['x-token'])
  end)

  it('prefers inline vars over .env and shell', function()
    e2e.set_shell_env('CURLONAUT_PRIO', 'shell')
    e2e.write_file('.env.test', 'CURLONAUT_PRIO=file\n')
    e2e.write_http(table.concat({
      '# @env-file .env.test',
      '@CURLONAUT_PRIO = inline',
      '',
      '###',
      '',
      'GET ' .. e2e.url '/echo',
      'X-Prio: {{CURLONAUT_PRIO}}',
    }, '\n'))

    e2e.goto_line 'GET '
    e2e.run_and_wait()

    assert.equals('inline', e2e.echo_result().headers['x-prio'])
  end)

  it('prefers .env over shell', function()
    e2e.set_shell_env('CURLONAUT_PRIO', 'shell')
    e2e.write_file('.env.test', 'CURLONAUT_PRIO=file\n')
    e2e.write_http(table.concat({
      '# @env-file .env.test',
      '',
      '###',
      '',
      'GET ' .. e2e.url '/echo',
      'X-Prio: {{CURLONAUT_PRIO}}',
    }, '\n'))

    e2e.goto_line 'GET '
    e2e.run_and_wait()

    assert.equals('file', e2e.echo_result().headers['x-prio'])
  end)

  it('falls back to the shell environment', function()
    e2e.set_shell_env('CURLONAUT_PRIO', 'shell')
    e2e.write_http(table.concat({
      'GET ' .. e2e.url '/echo',
      'X-Prio: {{CURLONAUT_PRIO}}',
    }, '\n'))

    e2e.goto_line 'GET '
    e2e.run_and_wait()

    assert.equals('shell', e2e.echo_result().headers['x-prio'])
  end)

  it('strips surrounding quotes from .env and inline values', function()
    e2e.write_file('.env.test', 'QUOTED="hello world"\n')
    e2e.write_http(table.concat({
      '# @env-file .env.test',
      "@Q = 'single'",
      '',
      '###',
      '',
      'GET ' .. e2e.url '/echo',
      'X-Q: {{QUOTED}}',
      'X-S: {{Q}}',
    }, '\n'))

    e2e.goto_line 'GET '
    e2e.run_and_wait()
    local headers = e2e.echo_result().headers

    assert.equals('hello world', headers['x-q'])
    assert.equals('single', headers['x-s'])
  end)

  it('warns and substitutes empty for a missing variable', function()
    e2e.write_http(table.concat({
      'GET ' .. e2e.url '/echo',
      'X-Missing: {{NOPE}}',
    }, '\n'))

    local messages = e2e.capture_notifications(function()
      e2e.goto_line 'GET '
      e2e.run_and_wait()
    end)

    local found = false
    for _, msg in ipairs(messages) do
      if msg:find('Missing env variable: NOPE', 1, true) then
        found = true
      end
    end
    assert.is_true(found)
    assert.equals('', e2e.echo_result().headers['x-missing'] or '')
  end)

  it('warns about a circular reference and terminates', function()
    e2e.write_http(table.concat({
      '@a = {{b}}',
      '@b = {{a}}',
      '',
      '###',
      '',
      'GET ' .. e2e.url '/echo',
      'X-C: {{a}}',
    }, '\n'))

    local messages = e2e.capture_notifications(function()
      e2e.goto_line 'GET '
      e2e.run_and_wait()
    end)

    local found = false
    for _, msg in ipairs(messages) do
      if msg:find('circular reference', 1, true) then
        found = true
      end
    end
    assert.is_true(found)
    assert.truthy((e2e.echo_result().headers['x-c'] or ''):find('{{', 1, true))
  end)

  it('warns when a variable chain exceeds the maximum depth', function()
    local lines = { '@v1 = end' }
    for i = 2, 12 do
      table.insert(lines, '@v' .. i .. ' = {{v' .. (i - 1) .. '}}')
    end
    table.insert(lines, '')
    table.insert(lines, '###')
    table.insert(lines, '')
    table.insert(lines, 'GET ' .. e2e.url '/echo')
    table.insert(lines, 'X-Deep: {{v12}}')
    e2e.write_http(table.concat(lines, '\n'))

    local messages = e2e.capture_notifications(function()
      e2e.goto_line 'GET '
      e2e.run_and_wait()
    end)

    local found = false
    for _, msg in ipairs(messages) do
      if msg:find('circular reference', 1, true) then
        found = true
      end
    end
    assert.is_true(found)
    assert.truthy((e2e.echo_result().headers['x-deep'] or ''):find('{{', 1, true))
  end)

  it('treats an empty value as missing', function()
    e2e.write_http(table.concat({
      '@EMPTY =',
      '',
      '###',
      '',
      'GET ' .. e2e.url '/echo',
      'X-Empty: {{EMPTY}}',
    }, '\n'))

    local messages = e2e.capture_notifications(function()
      e2e.goto_line 'GET '
      e2e.run_and_wait()
    end)

    local found = false
    for _, msg in ipairs(messages) do
      if msg:find('Missing env variable: EMPTY', 1, true) then
        found = true
      end
    end
    assert.is_true(found)
  end)
end)
