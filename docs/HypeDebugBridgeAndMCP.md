---
type: guide
title: Hype MCP Connections
description: Inbound local automation and outbound Brave Search Bridge setup, trust boundaries, discovery, and verification.
updated: 2026-10-08
---

# Hype Debug Bridge And MCP Split

Hype.app does not expose MCP directly. The app owns a local debug bridge, and a
separate TypeScript stdio MCP server translates MCP requests into debug bridge
calls.

## Brave Search Bridge (outbound)

Hype's authoring chat and Asset Repository agent can search through an existing
Brave Search Bridge. This is an outbound connection from the Hype process on the
Mac running Hype, separate from the inbound automation server described below.

1. Keep **Brave Search Bridge.app** running on an awake, logged-in Mac.
2. In **Hype → Settings → Services → Brave Search**, enable Brave Search.
3. On the bridge Mac, use `http://127.0.0.1:18424/mcp`. When Hype runs on another
   Mac, enter an already reachable private network URL from the bridge's
   settings. Localhost always refers to the machine running Hype. Hype does not
   change bridge network settings or create a public route.
4. Click **Check Connection**. It initializes MCP and discovers tools without
   making a paid search. A connected tool count proves discovery, not key
   validity or access to every subscription feature.
5. In a stack's AI chat, ask **“Find Greek food near Rogue River, Oregon.”** The
   transcript shows the discovery and call arguments. Check which upstream
   tool actually ran and that the answer cites clickable source URLs.

The API key stays in the bridge's Keychain. Hype sends no API key, authorization
header, or OAuth credential. Only the enabled flag and endpoint URL are stored
in app preferences (`hype.braveSearch.enabled`, `hype.braveSearch.endpoint`),
also exposed as `braveSearch.enabled` / `braveSearch.endpoint` through the local
debug preference tools. Brave is off by default in a fresh install. This
connection is not part of `.hype` documents or exported runtime defaults.
Existing web-asset search providers remain available independently.

### Discovery and result handling

The catalog adds two tools when enabled:

- `list_brave_tools`: without `tool_name`, return live names and descriptions;
  with `tool_name`, return that tool's full live MCP descriptor and input schema.
- `call_brave_tool`: pass the discovered `tool_name` and a typed JSON object in
  `arguments_json`. Only discovered Brave tool names are accepted.

`BraveSearchSession` obtains descriptors from MCP `tools/list`, follows bounded
pagination, and caches them for one chat turn. The bridge's eight tools are
available through this path, including LLM context, places, and summaries. Their
schemas are not copied into Hype: arrays, unions, constraints, defaults, and
future upstream schema changes remain intact. JSON arguments retain number,
boolean, array, and object types. The bridge validates feature-specific inputs.
Responses preserve `structuredContent`, content blocks, literal JSON snippets,
source URLs, and `isError`; Hype's existing chat renderer displays Markdown
links in the assistant's answer. Retrieved content is untrusted evidence, not
instructions. Place radius is a ranking bias, not a strict distance cutoff.

### Design and safety decision

**Outcome and acceptance:** source-grounded searches from Hype agents, visible
tool invocations, useful offline/provider errors, and clickable citations.
The settings surface has an explicit enable switch, labelled URL field,
connection-check progress and Cancel, a discovered-tool disclosure, and readable
error/status text. Changing the endpoint/enable switch or closing the view
cancels its check and clears stale results. A failed check leaves the endpoint
editable; it does not claim search success.

**Selected approach:** reuse Hype's existing tool catalog, dispatcher,
transaction runner, and result rendering, adding a narrow outbound Streamable
HTTP client (`HypeMCPHTTPClient`). Progressive discovery avoids converting
Brave's rich JSON Schemas into Hype's smaller native tool-schema model or
injecting all eight schemas into every request. A second Brave server/API
implementation would duplicate the user's working bridge and credential owner;
directly mapping eight schemas would require changing every model adapter.
Revisit if provider-native dynamic MCP tools or a general MCP connection manager
become a product requirement, or real-model acceptance shows discovery friction.

**Boundaries:** searches send queries to Brave and can consume quota, even with
on-device model inference. Search results also become part of the normal Hype
chat/tool history and may be sent to the selected model provider. Include only
information needed for the requested search. Network tools are opt-in authoring
capabilities, not implicit permission for deployed scripts or private AI Context
Library disclosure. `call_brave_tool` defers until Apply during transaction
preview and is executed once; document rollback cannot undo a submitted search.

HTTP uses an ephemeral URLSession, no cookies/cache/auth, a 30-second resource
deadline, a 4 MiB response bound, and redirect refusal. The client accepts JSON
and POST SSE responses, checks matching JSON-RPC IDs, sends the negotiated MCP
version/session headers, and reinitializes a session rejected with HTTP 404.
Ambiguous network failures are never automatically replayed. Stop cancels Hype's
request; the bridge/provider may already have processed it or spent quota.
Unavailable, timeout, HTTP, JSON-RPC, argument, and upstream `isError` failures
are returned to the agent with actionable messages. Brave plan/entitlement
errors retain the bridge's explanation. Hype does not verify another machine's
routing/firewall, uptime, or access to all subscription features.

### Verification commands

```sh
scripts/test.sh --filter BraveSearch --filter HypeMCPHTTPClientTests
/usr/bin/python3 scripts/verify-brave-transport.py
HYPE_BRAVE_LIVE_TEST=1 scripts/test.sh --filter BraveSearch
scripts/test.sh --no-parallel --filter InterpreterFuzzNoCrashTests --filter InterpreterMetamorphicTests
```

Fixture checks cover typed forwarding, schema fidelity, source preservation,
disabled/offline/timeout/provider errors, cancellation, malformed protocol
inputs, and quota-safe transaction previews. The Python fixture binds only to
loopback on an ephemeral port, uses no credential, and exercises actual HTTP
timeouts, cancellation, redirect refusal, and expired-session recovery. The
opt-in live test only discovers the running bridge; it does not search. A live
search must additionally be initiated from installed Hype's chat and checked
against its actual tool trace and source-linked answer.

Local verification on October 7, 2026: 34 focused tests passed, including live
eight-tool discovery and the interpreter fuzz/property checks. The broader
core/CLI run passed 3,640 tests; the standalone real-HTTP fixture passed five.
The optimized app was installed at `/Applications/Hype.app`, passed strict/deep
signature verification, and launched. Its executable matched the built copy
(SHA-256 `875318acc1063630f21137edb4c7cfbc9b4e267aaf07eb184094402869fb663a`).
An installed-app debug-dispatch search invoked `brave_web_search` with the
acceptance query and received five result blocks containing source URLs.
This proves the installed Hype → bridge → Brave path. On October 8, the
installed app's Settings surface was visually checked and Check Connection
displayed eight discovered tools. Model-driven chat acceptance remains open:
the configured `qwen3.8:27b-mlx` returned search plans without tool calls,
an installed `granite4.1:8b` attempt timed out, and `gpt-oss:20b` failed to load
with a missing `gpt-oss.expert_feed_forward_length` model metadata error.
The original model setting was restored. Closing evidence is a working
tool-capable model's actual chat trace and source-linked answer; successful
bridge discovery or dispatcher calls alone do not close that condition.
The installed build and broad tests used the current worktree, including
unrelated pre-existing runtime export changes; those changes are excluded from
this integration's commit.

Implementation references: the [official Brave MCP server](https://github.com/brave/brave-search-mcp-server)
and the [MCP Streamable HTTP specification](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports).
The inspected bridge reported upstream version 2.1.4. Those two primary sources,
the local bridge README/verification record, and direct endpoint/app execution
provide the integration evidence; discovery alone does not establish all
feature entitlements.

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
