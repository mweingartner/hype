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
exists, auto-attaches when exactly one live Hype session exists, and otherwise
requires an explicit `hype_attach_session` call.
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

`debug/keepalive` is answered by the socket server without touching document UI
state. The MCP server uses it as the persistent-connection heartbeat.
`debug/listTools` returns Hype's authoring tools plus MCP control tools.
Resources and prompts are exposed as debug methods so the app remains a debug
server rather than an MCP server. `debug/callTool` applies mutations to the
active focused document through `HypeToolExecutor` and
`HypeDocumentMutationCoordinator`, or dispatches control operations such as
preference reads and preview/apply transactions.

## MCP Server

The repo-local MCP server is a TypeScript project in `Tools/hype-mcp-server`.
It implements stdio MCP framing and always exposes connection-management tools:

- `hype_list_sessions`
- `hype_attach_session`
- `hype_detach_session`
- `hype_active_session`
- `hype_ping`

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
command = "node"
args = ["Tools/hype-mcp-server/bin/hype-mcp.js"]
enabled = true
```

The Node server is the only stdio entrypoint. By default it scans the
app-support debug directory used by launched Hype.app instances and any
repo-local `.hype/debug` directory left by development runs.

The repo `.envrc` sets `HYPE_DEBUG_SOCKET_DIR` to the app-support debug
directory so direnv-aware shells and MCP clients use the same default as
`/Applications/Hype.app`.
