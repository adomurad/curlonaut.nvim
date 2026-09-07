# roadmap

❌ Missing Features (categorized)
High Impact / Quality of Life
1. ✅ Request Cancellation – `:Curlonaut CancelRequest` and `<C-c>` in http / results buffers. Uses SIGKILL.
2. ✅ cURL Command Export / Copy – Added `Curl` results tab and `:Curlonaut CopyCurl` command.
 3. ✅ Response Time Display – No timing info (DNS, connect, TTFB, total) in the results panel.
 4. ✅ Request Timeout Option – Use `# @curl --max-time` / `--connect-timeout` per-file or per-request.
 5. Run All Requests in File – Currently only `RunRequest`.
6. ✅ Jump Between Requests – No keymaps to navigate to next/previous request block in the .http file.
HTTP Advanced Features
 7. Cookie Jar / Cookie Persistence – Cookies are not saved between requests in a session.
 8. Redirect Control – No option to follow or not follow redirects (curl -L / --max-redirs).
 9. ✅ Basic Auth helper – `Authorization: Basic {{$base64 MY_CREDS}}` base64-encodes an env variable (`MY_CREDS=user:pass`) or literal text. Bearer / Digest still via `# @curl` flags.
 10. ✅ SSL Options – Use `# @curl --insecure` / `--cacert` / `--cert` per-file or per-request.
 11. Proxy Support – No curl --proxy integration.
 12. ✅ Custom cURL Arguments – Use `# @curl <flag>` per-file or per-request.
Environment & Variables
13. Multiple Environment Profiles – Only supports a single # @env-file. No way to switch between dev.env, staging.env, prod.env.
 ✅ 14. Dynamic Variables – Built-ins like {{$uuid}}, {{$timestamp}}, {{$randomInt}}, {{$isoTimestamp}}, {{$randomFloat}}, {{$randomBool}}, {{$randomHex}}, {{$date}}.
15. Shared / Global Headers – No way to define headers that apply to all requests in a file (e.g., a shared Authorization header).
16. Request Names / Labels – Requests can only be identified by method/URL, not by a human-readable label.
Response Handling
17. Save Response to File – No >> ./output.json or similar syntax to persist the response body.
18. Binary / Image Response Handling – Probably breaks on non-text responses.
19. Clipboard Copy – No quick way to copy response body or headers from the results buffer.
20. SSE (Server-Sent Events) Streaming – No special handling for streaming text/event-stream responses.
21. WebSocket Support – Not expected in a simple plugin, but worth noting.
Scripting & Testing
22. Pre-request / Post-request Scripts – No Lua or JS hooks to run before/after a request.
23. Response Assertions / Tests – No way to assert status code, header presence, or body content.
24. Request Chaining / Dependencies – No explicit depends on or sequencing between requests.
Developer Experience
25. Import from cURL – No command to paste a raw curl command and convert it into a .http block.
26. Request History / Replay – No history of executed requests for quick re-run.
27. Pretty Print for More Content Types – Only JSON/HTML/XML supported. YAML, TOML, etc. are not.
28. Results Buffer Customization – Window size, position, and split direction are hardcoded.
 29. ✅ BASE64 creds – `{{$base64 VAR}}` / `{{$base64 literal text}}` dynamic variable (vim.base64, Neovim 0.10+).
