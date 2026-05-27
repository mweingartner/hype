# Hype MCP Server

This stdio MCP server is the only MCP-facing process for Hype. Hype.app no
longer exposes MCP directly. Instead, the app publishes a local debug bridge as
a per-instance Unix domain socket under `/tmp/hype-debug-$UID/`; this server
discovers live Hype instances, attaches to one, and proxies MCP tool calls to
the app's debug protocol.

Run from the repository root:

```sh
node Tools/hype-mcp-server/bin/hype-mcp.js
```

Useful MCP tools exposed even when detached:

- `hype_list_sessions`
- `hype_attach_session`
- `hype_detach_session`
- `hype_active_session`
- `hype_ping`

When attached, `tools/list` also includes the active Hype process's authoring
tools from `HypeToolDefinitions`.
