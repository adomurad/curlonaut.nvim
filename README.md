# curlonaut.nvim

![curlonaut](assets/curlonaut-1.png)

A rest client for NVIM.

Uses .rest / .http files and curl to send the requests.

This is a simple project - mainly suited to solve my needs.

It is mostly ***vibed*** - use at your own discretion.

## Installation

### lazy.nvim

```lua
{
  'adomurad/curlonaut.nvim',
  ft = { 'http', 'rest' },
  config = function()
    require('curlonaut').setup {
      formatters = {
        json = { command = 'prettierd', args = { '--stdin-filepath', '/tmp/curlonaut_response.json' } },
        html = { command = 'prettierd', args = { '--stdin-filepath', '/tmp/curlonaut_response.html' } },
        xml  = { command = 'xmllint',   args = { '--format', '-' } },
      },
    }

    vim.api.nvim_create_autocmd('FileType', {
      pattern = { 'http', 'rest' },
      callback = function(args)
        vim.keymap.set('n', '<CR>', function()
          vim.cmd 'Curlonaut RunRequest'
        end, { buffer = args.buf, desc = 'Run REST request under cursor' })

        vim.keymap.set('n', '<C-c>', function()
          vim.cmd 'Curlonaut CancelRequest'
        end, { buffer = args.buf, desc = 'Cancel running curlonaut request' })

        vim.keymap.set('n', ']r', require('curlonaut').goto_next_request,
          { buffer = args.buf, desc = 'Next REST request' })
        vim.keymap.set('n', '[r', require('curlonaut').goto_prev_request,
          { buffer = args.buf, desc = 'Previous REST request' })
      end,
    })
  end,
}
```

## Commands

| Command | Action |
|---|---|
| `:Curlonaut Open` | Open the results panel |
| `:Curlonaut Close` | Close the results panel |
| `:Curlonaut Toggle` | Toggle the results panel |
| `:Curlonaut RunRequest` | Execute the request under cursor |
| `:Curlonaut CancelRequest` | Kill the currently running request (also `<C-c>` in `.http` / results buffers) |
| `:Curlonaut CopyCurl` | Copy the shell-escaped curl command under cursor to clipboard (does not run) |
| `:Curlonaut ClearCookies` | Delete the in-memory cookie jar for the current `.http` / `.rest` buffer |
| `:Curlonaut EditCookies` | Open the raw cookie jar file for the current buffer in an editor buffer |

The results panel has five tabs: **Simple** (response only), **Full** (request + response), **Verbose** (live curl stderr), **Curl** (the exact shell-safe curl command used, ready to copy and paste into a terminal), and **Cookies** (current cookie jar contents).

## .http File Format

```http
# @env-file ./.env.local

@base_url = https://api.example.com

###

GET {{base_url}}/users

###

POST {{base_url}}/users
Content-Type: application/json

{
  "name": "Ada"
}
```

### URL-encoded body

```http
POST {{base_url}}/login
Content-Type: application/x-www-form-urlencoded

username=john
&password=secret
&age=30
```

Formatting newlines before `&` and at the end of the body are stripped automatically.

Use `{{$omit}}` as a value to drop a field entirely before sending:

```http
POST {{base_url}}/login
Content-Type: application/x-www-form-urlencoded

username=john
&password={{$omit}}
&age=30
```

Sent body becomes `username=john&age=30` (the `password` pair is removed).

`{{$omit}}` also works in query strings and multipart fields:

```http
GET {{base_url}}/users?active={{$omit}}&limit=10
```

```http
POST {{base_url}}/upload
Content-Type: multipart/form-data

description=hello
avatar={{$omit}}
report=< ./report.pdf;type=application/pdf
```

### Multipart / File upload

```http
POST {{base_url}}/upload
Content-Type: multipart/form-data

description=hello
avatar=< ./avatar.png
report=< ./report.pdf;type=application/pdf
```

Use `< ./path` for file uploads. Append `;type=mime/type` to override the MIME type.

### Response extractors

After a request completes you can pull values from the response body or headers and save them as session-scoped variables for later requests.

```http
POST {{base_url}}/login
Content-Type: application/json

{
  "username": "admin",
  "password": "secret"
}

@ACCESS_TOKEN = @response.body.token
@REQUEST_ID = @response.headers.x-request-id

GET {{base_url}}/users
Authorization: Bearer {{ACCESS_TOKEN}}
```

- `@response.body.path` — JSON dot-path, supports arrays like `items[0].id`
- `@response.headers.name` — case-insensitive header lookup

### Custom cURL Flags

Pass arbitrary curl flags per-file (applies to all requests) or per-request. Flags are whitespace-split and appended to the generated curl command.

**Per-file** — place before the first request:

```http
# @curl --insecure
# @curl --connect-timeout 5

###

GET https://localhost/api
```

**Per-request** — place inside a request block:

```http
###
# @curl --max-time 10

GET https://slow.example.com/data
```

File-level flags are applied first, then per-request flags. On conflicts (e.g. two `--max-time` values), curl uses the last one, so per-request naturally wins.

### Cookie Jar

Enable a per-file cookie jar by adding `# @cookie-jar` before the first request. All requests in the same file then share cookies automatically via curl's native `--cookie` / `--cookie-jar` mechanism.

```http
# @cookie-jar

POST {{base_url}}/login
Content-Type: application/json

{ "username": "admin", "password": "secret" }

###

GET {{base_url}}/dashboard
```

- Cookies are stored in a temporary file and live only for the current Neovim session (deleted on `VimLeavePre`).
- After any request completes, open the **Cookies** tab to inspect the current jar.
- Press `D` inside the Cookies tab to clear the jar, or run `:Curlonaut ClearCookies`.
- Press `e` inside the Cookies tab to edit the raw cookie jar file directly.

## Environment Variables

Variable resolution priority (highest first):

1. Response extractors (`@var = @response.body...` set after a request)
2. Inline `@variable = value` declarations in the `.http` file
3. Variables from the `.env` file specified via `# @env-file ./path`
4. Shell environment variables

Use `{{VAR_NAME}}` anywhere in the URL, headers, or body.

## Dynamic Variables

Built-in dynamic variables generate fresh values on every occurrence. Use the same syntax with a `$` prefix:

```http
POST {{base_url}}/events
Content-Type: application/json

{
  "id": "{{$uuid}}",
  "createdAt": "{{$isoTimestamp}}",
  "age": {{$randomInt 18 99}},
  "score": {{$randomFloat 0 100}},
  "active": {{$randomBool}},
  "nonce": "{{$randomHex 32}}",
  "today": "{{$date %Y-%m-%d}}"
}
```

| Variable | Description | Example output |
|---|---|---|
| `{{$uuid}}` / `{{$guid}}` | UUID v4 | `a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d` |
| `{{$timestamp}}` | Unix epoch seconds | `1751270400` |
| `{{$timestampMs}}` | Unix epoch milliseconds | `1751270400000` |
| `{{$isoTimestamp}}` | ISO 8601 UTC datetime | `2025-06-30T12:00:00Z` |
| `{{$randomInt}}` | Random integer 0–1000 | `42` |
| `{{$randomInt min max}}` | Random integer in range | `{{$randomInt 1 100}}` |
| `{{$randomFloat}}` | Random float 0.0–1.0 | `0.739` |
| `{{$randomFloat min max}}` | Random float in range | `{{$randomFloat 0 100}}` |
| `{{$randomBool}}` | `true` or `false` | `true` |
| `{{$randomHex}}` | 16 random hex chars | `a3f7b2e1c8d40965` |
| `{{$randomHex n}}` | `n` random hex chars | `{{$randomHex 32}}` |
| `{{$date}}` | Today (`%Y-%m-%d`) | `2025-06-30` |
| `{{$date fmt}}` | Formatted with `os.date` | `{{$date %H:%M}}` |
| `{{$omit}}` | Omit this field from urlencoded/multipart body | — |

> **Tip:** If you need the *same* dynamic value in multiple places, assign it to an inline variable first:
> ```http
> @my_uuid = {{$uuid}}
> ```
> Then use `{{my_uuid}}` wherever needed.
>
> **Note on syntax highlighting:** `{{VAR}}` and `{{$VAR}}` inside JSON bodies without surrounding quotes may briefly break treesitter highlighting in the `.http` buffer. This is an upstream limitation of the `tree-sitter-http` parser (it injects the raw body text into the JSON parser, which sees templates as invalid syntax). The request still runs correctly — only the editor's syntax coloring is affected. Placing templates inside strings avoids the issue.

## Health Check

Run `:checkhealth curlonaut` to verify dependencies.
