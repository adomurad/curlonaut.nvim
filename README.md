# curlonaut.nvim

![curlonaut](assets/curlonaut-1.png)

A REST client for Neovim. Write `.http` / `.rest` files and send the requests
with `curl` without leaving the editor.

This is a simple project — mainly suited to solve my needs. It is mostly
***vibed*** — use at your own discretion.

---

## Requirements

- Neovim with Lua and the built-in `vim.treesitter` API.
- [`curl`](https://curl.se/) on your `PATH`.
- The tree-sitter `http` parser: run `:TSInstall http`.
- [`plenary.nvim`](https://github.com/nvim-lua/plenary.nvim) (used for the async job).

---

## Installation

### lazy.nvim

```lua
{
  'adomurad/curlonaut.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
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

---

## Quick Start

Create a file called `api.http`:

```sh
@base_url = https://httpbin.org

###

GET {{base_url}}/get
```

Put your cursor anywhere in the request and run `:Curlonaut RunRequest`. The
results panel opens on the right. See the [lazy.nvim example](#lazynvim) for
suggested keymaps.

---

## Commands

All functionality is exposed through one command with a required argument
(Tab-completion works):

| Command | Action |
|---|---|
| `:Curlonaut Open` | Open the results panel. |
| `:Curlonaut Close` | Close the results panel. |
| `:Curlonaut Toggle` | Toggle the results panel. |
| `:Curlonaut RunRequest` | Execute the request under the cursor. |
| `:Curlonaut CancelRequest` | Kill the currently running request. |
| `:Curlonaut CopyCurl` | Copy the shell-safe `curl` command under the cursor to the clipboard (does not run it). |
| `:Curlonaut ClearCookies` | Delete the cookie jar for the current buffer. |
| `:Curlonaut EditCookies` | Open the raw cookie jar file for the current buffer in an editor buffer. |

---

## Results Panel

Running a request opens a vertical split on the right showing the output. The
panel does not steal focus from your `.http` buffer.

### Tabs

Switch tabs with `<S-l>` / `<S-h>` (see [Keymaps](#keymaps)).

| Tab | Contents |
|---|---|
| **Simple** | Response only — status, time, headers, and body. |
| **Full** | Request details plus the full response. |
| **Verbose** | Live `curl` stderr output, streamed as the request runs. |
| **Curl** | The exact shell-safe `curl` command used, ready to copy and paste. |
| **Cookies** | The current cookie jar (only populated when `# @cookie-jar` is active). |

### Keymaps

These are set automatically inside results buffers:

| Key | Action |
|---|---|
| `<S-l>` | Next tab. |
| `<S-h>` | Previous tab. |
| `<C-c>` | Cancel the running request. |
| `D` | Clear the cookie jar (Cookies tab only). |
| `e` | Edit the raw cookie jar file (Cookies tab only). |

> `RunRequest` is not bound by default — bind it yourself (see the
> [lazy.nvim example](#lazynvim)).

---

## File Format

A `.http` / `.rest` file contains one or more requests separated by `###`
lines. The request under the cursor is the one that runs.

### Requests and Separators

```sh
### First request

GET https://httpbin.org/get

###

### Second request

GET https://httpbin.org/ip
```

### Headers

Headers are plain `Name: value` lines placed directly under the request line:

```sh
GET https://httpbin.org/headers
Accept: application/json
X-Custom: hello
```

### Bodies

The body follows the headers, separated by a blank line. How it is interpreted
depends on the `Content-Type` header.

#### JSON

```sh
POST {{base_url}}/users
Content-Type: application/json

{
  "name": "Ada"
}
```

JSON bodies (`Content-Type` containing `json`) support whole-line `//` comments.
Comment lines are stripped before the request is sent:

```sh
POST {{base_url}}/users
Content-Type: application/json

{
  // this line is removed
  "name": "Ada",
  "homepage": "http://example.com/a//b"
}
```

Only lines whose first non-whitespace characters are `//` are treated as
comments, so `//` inside strings and URLs is preserved. Trailing (inline)
comments are not supported, and this applies to JSON bodies only.

#### URL-encoded

```sh
POST {{base_url}}/login
Content-Type: application/x-www-form-urlencoded

username=john
&password=secret
&age=30
```

Formatting newlines before `&` and at the end of the body are stripped
automatically.

Use `{{$omit}}` as a value to drop a field entirely before sending:

```sh
POST {{base_url}}/login
Content-Type: application/x-www-form-urlencoded

username=john
&password={{$omit}}
&age=30
```

Sent body becomes `username=john&age=30` (the `password` pair is removed).
`{{$omit}}` also works in query strings and multipart fields — see
[Dynamic Variables](#dynamic-variables).

#### Multipart and File Upload

```sh
POST {{base_url}}/upload
Content-Type: multipart/form-data

description=hello
avatar=< ./avatar.png
report=< ./report.pdf;type=application/pdf
```

Use `< ./path` for file uploads. Append `;type=mime/type` to override the MIME
type. Relative paths are resolved against the `.http` file's directory.

### Multiline URLs

Long URLs and query strings can be split across multiple lines. Whitespace
after a line break is removed, so parameters line up neatly:

```sh
GET {{base_url}}/search
  ?q=neovim
  &limit=10
  &offset=0
```

The above is sent as `GET {{base_url}}/search?q=neovim&limit=10&offset=0`.

---

## Directives

Directives are `#` comment lines that change how a file behaves.

### @env-file

Load variables from a dotenv file. Place it before the first request; the path
is resolved relative to the `.http` file.

```sh
# @env-file ./.env.local

@base_url = https://api.example.com

###

GET {{base_url}}/users
```

The dotenv file supports `#` comments, blank lines, and `KEY=value`,
`KEY="value"`, or `KEY='value'` forms.

### @curl

Pass arbitrary `curl` flags per-file (applies to all requests) or per-request.
Flags are whitespace-split and appended to the generated `curl` command.

**Per-file** — place before the first request:

```sh
# @curl --insecure
# @curl --connect-timeout 5

###

GET https://localhost/api
```

**Per-request** — place inside a request block:

```sh
###
# @curl --max-time 10

GET https://slow.example.com/data
```

File-level flags are applied first, then per-request flags. On conflicts (e.g.
two `--max-time` values), `curl` uses the last one, so per-request wins.

### @cookie-jar Directive

Enable a per-file cookie jar by adding `# @cookie-jar` before the first
request. All requests in the same file then share cookies automatically via
`curl`'s native `--cookie` / `--cookie-jar` mechanism.

```sh
# @cookie-jar

POST {{base_url}}/login
Content-Type: application/json

{ "username": "admin", "password": "secret" }

###

GET {{base_url}}/dashboard
```

See [Cookie Jar](#cookie-jar) for the full workflow.

---

## Variables

Use `{{VAR_NAME}}` anywhere in the URL, headers, body, or `curl` flags.

### Inline Variables

Declare variables directly in the `.http` file with `@name = value`. Declarations
are file-scoped and may appear anywhere in the file. Values can be quoted, and
can reference dynamic variables (which are resolved once, at declaration):

```sh
@base_url = https://api.example.com
@token = "abc123"

@my_uuid = {{$uuid}}

###

GET {{base_url}}/users
Authorization: Bearer {{token}}
```

> **Tip:** If you need the *same* dynamic value in multiple places, assign it to
> an inline variable first (as `my_uuid` above), then use `{{my_uuid}}` wherever
> needed.

### Environment Variables

Variable resolution priority (highest first):

1. Response extractors (`@var = @response.body...` set after a request)
2. Inline `@variable = value` declarations in the `.http` file
3. Variables from the `.env` file specified via `# @env-file ./path`
4. Shell environment variables

Missing variables are replaced with an empty string and produce a warning.

### Dynamic Variables

Built-in dynamic variables generate a fresh value on every occurrence. Use the
same syntax with a `$` prefix:

```sh
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
| `{{$base64 value}}` | Base64-encode an env variable name or literal text (requires Neovim 0.10+) | `{{$base64 MY_CREDS}}` where `MY_CREDS = user:pass` → `dXNlcjpwYXNz` |
| `{{$omit}}` | Omit this field from a urlencoded/multipart body or query string | — |

Basic auth is the main use case for `$base64` — the first argument is looked up
as an env variable first (inline `@var`, `.env` file, shell), falling back to
treating it as literal text:

```sh
GET {{base_url}}/secure
Authorization: Basic {{$base64 MY_CREDS}}
```

```sh
# equivalent, using a literal
GET {{base_url}}/secure
Authorization: Basic {{$base64 user:pass}}
```

`{{$omit}}` drops a whole `key=value` pair, so you can toggle optional fields:

```sh
GET {{base_url}}/users?active={{$omit}}&limit=10
```

---

## Response Extractors

After a request completes you can pull values from the response body or headers
and save them as session-scoped variables for later requests. Place the
extractor lines at the end of the request body:

```sh
POST {{base_url}}/login
Content-Type: application/json

{
  "username": "admin",
  "password": "secret"
}

@ACCESS_TOKEN = @response.body.token
@REQUEST_ID = @response.headers.x-request-id

###

GET {{base_url}}/users
Authorization: Bearer {{ACCESS_TOKEN}}
```

- `@response.body.path` — JSON dot-path, supports arrays like `items[0].id`.
- `@response.headers.name` — case-insensitive header lookup.

Extractor lines are stripped from the body before the request is sent. Values
live for the current Neovim session and override other variable sources.

---

## Cookie Jar

Enable the jar per file with the [`@cookie-jar` directive](#cookie-jar-directive).
Once enabled, every request in that file reads and writes the same jar.

```sh
# @cookie-jar

POST {{base_url}}/login
Content-Type: application/json

{ "username": "admin", "password": "secret" }

###

GET {{base_url}}/dashboard
```

- Cookies are stored in a temporary file and live only for the current Neovim
  session (deleted on `VimLeavePre`).
- After any request completes, open the **Cookies** tab to inspect the jar.
- Press `D` inside the Cookies tab to clear the jar, or run
  `:Curlonaut ClearCookies`.
- Press `e` inside the Cookies tab to edit the raw cookie jar file directly, or
  run `:Curlonaut EditCookies`.

---

## Response Formatting

If a formatter is configured for the response's content type, the **Simple** and
**Full** tabs pretty-print the body. Supported content types are JSON, HTML, and
XML. Formatting is best-effort: if the formatter is missing or fails, the raw
body is shown.

```lua
require('curlonaut').setup {
  formatters = {
    json = { command = 'prettierd', args = { '--stdin-filepath', '/tmp/curlonaut_response.json' } },
    html = { command = 'prettierd', args = { '--stdin-filepath', '/tmp/curlonaut_response.html' } },
    xml  = { command = 'xmllint',   args = { '--format', '-' } },
  },
}
```

A formatter can also be given as a shorthand string when the command needs no
extra arguments, e.g. `json = 'prettierd'`.

---

## Health Check

Run `:checkhealth curlonaut` to verify that `curl` and the tree-sitter `http`
parser are available.

---

## Limitations

- **Syntax highlighting with templates.** `{{VAR}}` and `{{$VAR}}` inside JSON
  bodies without surrounding quotes may briefly break treesitter highlighting in
  the `.http` buffer. This is an upstream limitation of the `tree-sitter-http`
  parser (it injects the raw body text into the JSON parser, which sees
  templates as invalid syntax). The request still runs correctly — only the
  editor's syntax coloring is affected. Placing templates inside strings avoids
  the issue.
- **JSON comments** are whole-line only and apply to JSON bodies only. Inline
  comments are not supported.
- **URL-encoded bodies** only strip formatting newlines before `&` and at the end
  of the body.

---

## License

See [LICENSE](LICENSE).
