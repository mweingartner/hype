---
type: guide
title: Hype Debug Bridge And MCP Split
description: How Hype.app exposes local debug automation over a Unix socket and how the MCP proxy forwards tools, resources, and prompts.
updated: 2026-07-30
---

# Hype Debug Bridge And MCP Split

Hype.app does not expose MCP directly. The app owns a local debug bridge, and a
separate TypeScript stdio MCP server translates MCP requests into debug bridge
calls.

## Runtime Shape

```text
MCP client
  -> stdio MCP server: Tools/hype-mcp-server/bin/hype-mcp.js
  -> Unix socket debug bridge: <discovery>/<instance>.sock
  -> active Hype.app process
```

The debug bridge starts when the "Enable debug socket" preference is on and
stops when that preference is off or Hype terminates. It does not bind a TCP
port.

## Discovery

Debug bridge writers choose one discovery directory, in order of preference:
1. `HYPE_DEBUG_SOCKET_DIR` env var (if set and non-empty)
2. `~/Library/Application Support/Hype/debug/`

The MCP stdio server scans the configured `HYPE_DEBUG_SOCKET_DIR` when set.
Without it, the server scans the app-support debug directory and any existing
repo-local `.hype/debug/` directory left by development runs. It creates only
the app-support directory on startup.

Each Hype process writes a socket `<discovery>/<pid>.sock` and a descriptor
`<discovery>/<instanceId>.json` where `<pid>` is the process ID of the Hype instance.

The discovery directory is created with `0700` permissions and descriptors are
written with `0600` permissions. Descriptors include:

- `protocolVersion`
- `instanceId`
- `pid`
- `socketPath`
- `startedAt`
- `bundlePath`
- active document identity when available

The TypeScript MCP server prunes stale descriptors when the process no longer
exists or the socket cannot answer `debug/keepalive`, auto-attaches when
exactly one live Hype session exists, and otherwise requires an explicit
`hype_attach_session` call.
It also starts successfully when no Hype process is running; after startup it
continues polling the discovery directory and attaches when a single live debug
socket appears.

## Debug Protocol

The app debug bridge speaks newline-delimited JSON-RPC over the Unix socket. This
is intentionally not MCP. Connections may stay open for multiple JSON-RPC
messages; the server keeps accepting and reading on a dedicated dispatch queue
so lightweight liveness checks still work even if the main UI actor is slow.

Methods:

- `debug/keepalive`
- `debug/hello`
- `debug/getState`
- `debug/listTools`
- `debug/listResources`
- `debug/readResource`
- `debug/listPrompts`
- `debug/getPrompt`
- `debug/callTool`
- `debug/startOperation`
- `debug/pollOperation`
- `debug/forgetOperation`
- `debug/runScript`
- `debug/clickButton`

`debug/keepalive` is answered by the socket server without touching document UI
state. The MCP server uses it as the persistent-connection heartbeat.
`debug/listTools` returns Hype's authoring tools plus MCP control tools.
Resources and prompts are exposed as debug methods so the app remains a debug
server rather than an MCP server. `debug/callTool` applies mutations to the
active focused document through `HypeToolExecutor` and
`HypeDocumentMutationCoordinator`, or dispatches control operations such as
preference reads and preview/apply transactions.

`debug/runScript` and `debug/clickButton` honor the `hype.mcp.allowMutations`
preference in the same way as every other mutation path: when `allowMutations`
is false, both methods return a refusal response without executing. This brings
these two methods into parity with `debug/callTool` and the rest of the
mutation surface.

Requests that can suspend at a script breakpoint should be submitted through
`debug/startOperation`:

```json
{
  "jsonrpc": "2.0",
  "id": "start-click",
  "method": "debug/startOperation",
  "params": {
    "method": "debug/clickButton",
    "params": { "button": "Run", "card": "Card 1" }
  }
}
```

The start response is immediate and includes `operationId`, `status`, and
`pollAfterMilliseconds`. Call `debug/pollOperation` with that UUID until the
status becomes `completed` or `failed`; the terminal payload is returned as
`result` or `error`. `debug/forgetOperation` releases a terminal result early.
Completed and failed results otherwise expire after five minutes. The registry
is process-local, bounded to 128 operations, and never persists into a `.hype`
document. Pending operations are retained because a script may remain
intentionally halted until an external debugger resumes it.

Menu automation is exposed through `debug/callTool` control tools:

- `hype_list_menu_commands`
- `hype_trigger_menu_command`

`hype_trigger_menu_command` posts the same in-app notifications used by Hype's
SwiftUI menus, so automation can open auxiliary windows such as Script Debugger
without using macOS Accessibility keystroke permissions. Commands accept stable
ids such as `script_debugger`, `show_console`, `next_card`, and
`select_tool` with an `argument` like `button`.

Automatic UI and debugger testing is exposed through additional live-app
control tools:

- Window state: `hype_list_windows`, `hype_focus_window`, `hype_wait_for_window`
- Modal alerts: `hype_list_alerts`, `hype_dismiss_alert`
- Async debugger operations: `hype_wait_for_debugger_pause`,
  `hype_step_script_execution_and_wait`, `hype_poll_debug_operation`,
  `hype_forget_debug_operation`
- Script editor breakpoints: `hype_get_script_editor_state`,
  `hype_toggle_script_editor_breakpoint`

These tools intentionally use in-process AppKit and debugger state rather than
System Events or screen coordinates, so they work without macOS Accessibility
permissions and return structured JSON that tests can assert on directly.
Script editor breakpoints can target handler entry lines and executable
statement lines. Handler-level breakpoints pause before the handler body starts;
statement-level line breakpoints pause immediately before the matching
statement executes, with current locals/globals available in the pause state.
Blank, comment-only, and handler terminator lines are rejected because they
have no executable location. Step Into pauses at the next statement or nested
handler entry. Step Over skips nested handler execution and pauses at the next
statement in the current or calling handler. Step requests and pending
breakpoint-hit annotations are scoped to their dispatch and handler execution,
so concurrent stack runtimes cannot consume each other's debugger state.
The two historically named wait tools now start operations and return
immediately; callers poll the returned UUID instead of occupying an MCP or
debug-socket request. The stdio bridge also starts `hype_debug_click_button` and
`hype_dispatch_message` through `debug/startOperation`, so a breakpoint reached
inside the dispatched script cannot block the MCP caller.

## MCP Server

The repo-local MCP server is a TypeScript project in `Tools/hype-mcp-server`.
It implements stdio MCP framing and always exposes connection-management tools:

- `hype_list_sessions`
- `hype_attach_session`
- `hype_detach_session`
- `hype_active_session`
- `hype_ping`
- `hype_start_debug_operation`

When attached to a Hype process, the MCP server keeps one Unix-socket debug
connection open, sends periodic `debug/keepalive` requests, and reuses that
connection for proxied calls. `tools/list`, `resources/list`, and
`prompts/list` include the active Hype surface, and calls/read/get requests are
proxied over the debug bridge.
When detached, startup and `tools/list` still complete with only the
connection-management tools while background discovery continues.

## Local Client Config

Project `opencode.json` launches the MCP server as a local stdio process:

```json
{
  "mcp": {
    "hype": {
      "type": "local",
      "command": ["node", "Tools/hype-mcp-server/bin/hype-mcp.js"],
      "enabled": true
    }
  }
}
```

Repo-local Codex config uses the same server:

```toml
[mcp_servers.hype]
command = "/usr/bin/env"
args = ["node", "/path/to/hype/Tools/hype-mcp-server/bin/hype-mcp.js"]

[mcp_servers.hype.env]
HYPE_DEBUG_SOCKET_DIR = "/path/to/hype/.hype/debug"
```

The Node server is the only stdio entrypoint. By default it scans the
app-support debug directory used by launched Hype.app instances and any
repo-local `.hype/debug` directory left by development runs.

The repo `.envrc` sets `HYPE_DEBUG_SOCKET_DIR` to the app-support debug
directory so direnv-aware shells and MCP clients use the same default as
`/Applications/Hype.app`.
