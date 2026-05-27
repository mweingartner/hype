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

The debug bridge starts when Hype launches and stops when Hype terminates. It is
not configurable through the old MCP preferences UI, and it does not bind a TCP
port.

## Discovery

Discovery path (in order of preference):
1. `HYPE_DEBUG_SOCKET_DIR` env var (if set and non-empty)
2. `.hype/debug/sockets/` relative to the repo root (cwd)
3. `~/Library/Application Support/com.hype.app/debug/sockets/`

Each Hype process writes a descriptor to `<discovery>/<instance>.json`.

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

## Debug Protocol

The app debug bridge speaks newline-delimited JSON-RPC over the Unix socket. This
is intentionally not MCP.

Methods:

- `debug/hello`
- `debug/getState`
- `debug/listTools`
- `debug/callTool`

`debug/listTools` returns the same tool schemas Hype's AI surfaces use.
`debug/callTool` applies mutations to the active focused document through
`HypeToolExecutor` and `HypeDocumentMutationCoordinator`.

## MCP Server

The repo-local MCP server is a TypeScript project in `Tools/hype-mcp-server`.
It implements stdio MCP framing and always exposes connection-management tools:

- `hype_list_sessions`
- `hype_attach_session`
- `hype_detach_session`
- `hype_active_session`
- `hype_ping`

When attached to a Hype process, `tools/list` also includes the active Hype tool
surface, and `tools/call` proxies those tool calls over the debug bridge.

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
