import fs from "node:fs/promises"
import fsSync from "node:fs"
import net from "node:net"
import os from "node:os"
import path from "node:path"
import process from "node:process"

type JsonObject = Record<string, unknown>

interface HypeSessionDescriptor {
  protocolVersion?: number
  instanceId: string
  pid: number
  socketPath: string
  startedAt?: string
  bundlePath?: string
  activeDocumentName?: string | null
  activeDocumentId?: string | null
}

interface McpTool {
  name: string
  description: string
  inputSchema: JsonObject
}

let nextDebugId = 1
let attached: HypeSessionDescriptor | null = null
let stdinBuffer = Buffer.alloc(0)

const connectionTools: McpTool[] = [
  {
    name: "hype_list_sessions",
    description: "List discoverable running Hype.app debug sessions.",
    inputSchema: { type: "object", properties: {}, required: [] },
  },
  {
    name: "hype_attach_session",
    description: "Attach this MCP server to a running Hype.app session by instance_id or socket_path. If omitted and exactly one session exists, attaches to it.",
    inputSchema: {
      type: "object",
      properties: {
        instance_id: { type: "string", description: "Hype debug session instance id." },
        socket_path: { type: "string", description: "Explicit Hype debug Unix socket path." },
      },
      required: [],
    },
  },
  {
    name: "hype_detach_session",
    description: "Detach from the current Hype.app debug session.",
    inputSchema: { type: "object", properties: {}, required: [] },
  },
  {
    name: "hype_active_session",
    description: "Show the currently attached Hype.app debug session.",
    inputSchema: { type: "object", properties: {}, required: [] },
  },
  {
    name: "hype_ping",
    description: "Ping the attached Hype.app debug session.",
    inputSchema: { type: "object", properties: {}, required: [] },
  },
]

function discoveryDirectory(): string {
  const configured = process.env.HYPE_DEBUG_SOCKET_DIR?.trim()
  if (configured && configured.length > 0) {
    return configured.replace(/^~/, os.homedir())
  }

  const repoLocal = path.join(process.cwd(), ".hype", "debug")
  try {
    fsSync.mkdirSync(repoLocal, { recursive: true, mode: 0o700 })
    return repoLocal
  } catch {
    return path.join(os.homedir(), "Library", "Application Support", "Hype", "debug")
  }
}

async function discoverSessions(): Promise<HypeSessionDescriptor[]> {
  const dir = discoveryDirectory()
  let entries: string[] = []
  try {
    entries = await fs.readdir(dir)
  } catch {
    return []
  }

  const sessions: HypeSessionDescriptor[] = []
  for (const entry of entries) {
    if (!entry.endsWith(".json")) continue
    const descriptorPath = path.join(dir, entry)
    try {
      const descriptor = JSON.parse(await fs.readFile(descriptorPath, "utf8")) as HypeSessionDescriptor
      if (!descriptor.instanceId || !descriptor.socketPath || !descriptor.pid) continue
      if (!isPidLive(descriptor.pid)) {
        await pruneDescriptor(descriptorPath, descriptor.socketPath)
        continue
      }
      sessions.push(descriptor)
    } catch {
      continue
    }
  }

  return sessions.sort((a, b) => (b.startedAt ?? "").localeCompare(a.startedAt ?? ""))
}

function isPidLive(pid: number): boolean {
  try {
    process.kill(pid, 0)
    return true
  } catch {
    return false
  }
}

async function pruneDescriptor(descriptorPath: string, socketPath: string): Promise<void> {
  await Promise.allSettled([fs.rm(descriptorPath, { force: true }), fs.rm(socketPath, { force: true })])
}

async function enrichSession(session: HypeSessionDescriptor): Promise<HypeSessionDescriptor> {
  try {
    const state = await debugRPC(session.socketPath, "debug/getState", {})
    return { ...session, ...(state as HypeSessionDescriptor) }
  } catch {
    return session
  }
}

async function ensureAttached(): Promise<HypeSessionDescriptor | null> {
  if (attached) {
    try {
      await debugRPC(attached.socketPath, "debug/hello", {})
      return attached
    } catch {
      attached = null
    }
  }

  const sessions = await discoverSessions()
  if (sessions.length === 1) {
    attached = await enrichSession(sessions[0])
    return attached
  }
  return null
}

async function attachSession(args: JsonObject): Promise<string> {
  const sessions = await discoverSessions()
  const instanceId = stringArg(args, "instance_id")
  const socketPath = stringArg(args, "socket_path")
  let session: HypeSessionDescriptor | undefined
  if (socketPath) {
    session = sessions.find((candidate) => candidate.socketPath === socketPath) ?? {
      instanceId: path.basename(socketPath, ".sock"),
      pid: 0,
      socketPath,
    }
  } else if (instanceId) {
    session = sessions.find((candidate) => candidate.instanceId === instanceId)
  } else if (sessions.length === 1) {
    session = sessions[0]
  }

  if (!session) {
    return sessions.length === 0
      ? "No running Hype debug sessions found. Launch Hype.app and open or focus a stack."
      : `No matching Hype session. Found ${sessions.length}; call hype_list_sessions and pass instance_id.`
  }

  attached = await enrichSession(session)
  await debugRPC(attached.socketPath, "debug/hello", {})
  return `Attached to Hype session ${attached.instanceId}${attached.activeDocumentName ? ` (${attached.activeDocumentName})` : ""}`
}

function stringArg(args: JsonObject, key: string): string {
  const value = args[key]
  return typeof value === "string" ? value.trim() : ""
}

async function debugRPC(socketPath: string, method: string, params: JsonObject): Promise<unknown> {
  const id = nextDebugId++
  const request = JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n"
  return await new Promise((resolve, reject) => {
    const socket = net.createConnection(socketPath)
    let settled = false
    let data = ""
    const timer = setTimeout(() => {
      if (!settled) {
        settled = true
        socket.destroy()
        reject(new Error("Hype debug request timed out"))
      }
    }, 5000)

    socket.on("connect", () => socket.write(request))
    socket.on("data", (chunk) => {
      data += chunk.toString("utf8")
      if (!data.includes("\n")) return
      if (settled) return
      settled = true
      clearTimeout(timer)
      socket.end()
      try {
        const response = JSON.parse(data.slice(0, data.indexOf("\n")))
        if (response.error) reject(new Error(response.error.message ?? "Hype debug error"))
        else resolve(response.result)
      } catch (error) {
        reject(error)
      }
    })
    socket.on("error", (error) => {
      if (!settled) {
        settled = true
        clearTimeout(timer)
        reject(error)
      }
    })
  })
}

process.stdin.on("data", (chunk) => {
  stdinBuffer = Buffer.concat([stdinBuffer, chunk])
  void processMessages()
})

async function processMessages(): Promise<void> {
  while (true) {
    const headerEnd = stdinBuffer.indexOf("\r\n\r\n")
    if (headerEnd < 0) return
    const header = stdinBuffer.slice(0, headerEnd).toString("utf8")
    const match = /^content-length:\s*(\d+)$/im.exec(header)
    if (!match) {
      stdinBuffer = Buffer.alloc(0)
      return
    }
    const length = Number(match[1])
    const bodyStart = headerEnd + 4
    if (stdinBuffer.length < bodyStart + length) return
    const body = stdinBuffer.slice(bodyStart, bodyStart + length).toString("utf8")
    stdinBuffer = stdinBuffer.slice(bodyStart + length)
    let message: JsonObject
    try {
      message = JSON.parse(body) as JsonObject
    } catch {
      send({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } })
      continue
    }
    await handleMCPMessage(message)
  }
}

async function handleMCPMessage(message: JsonObject): Promise<void> {
  const method = typeof message.method === "string" ? message.method : ""
  const id = message.id
  if (!id && method.startsWith("notifications/")) return

  try {
    switch (method) {
      case "initialize":
        sendResult(id, {
          protocolVersion: "2024-11-05",
          capabilities: { tools: { listChanged: false } },
          serverInfo: { name: "hype-mcp-server", version: "0.1.0" },
        })
        return
      case "ping":
        sendResult(id, {})
        return
      case "tools/list":
        sendResult(id, { tools: await listTools() })
        return
      case "tools/call":
        sendResult(id, await callMCPTool((message.params as JsonObject | undefined) ?? {}))
        return
      default:
        sendError(id, -32601, "Method not found")
    }
  } catch (error) {
    sendError(id, -32603, error instanceof Error ? error.message : "Internal error")
  }
}

async function listTools(): Promise<McpTool[]> {
  const session = await ensureAttached()
  if (!session) return connectionTools
  try {
    const result = (await debugRPC(session.socketPath, "debug/listTools", {})) as { tools?: McpTool[] }
    return [...connectionTools, ...(result.tools ?? [])]
  } catch {
    attached = null
    return connectionTools
  }
}

async function callMCPTool(params: JsonObject): Promise<JsonObject> {
  const name = typeof params.name === "string" ? params.name : ""
  const args = ((params.arguments as JsonObject | undefined) ?? {})
  switch (name) {
    case "hype_list_sessions": {
      const sessions = await Promise.all((await discoverSessions()).map(enrichSession))
      return textContent(JSON.stringify(sessions, null, 2), false)
    }
    case "hype_attach_session":
      return textContent(await attachSession(args), false)
    case "hype_detach_session":
      attached = null
      return textContent("Detached from Hype session.", false)
    case "hype_active_session":
      return textContent(attached ? JSON.stringify(await enrichSession(attached), null, 2) : "No Hype session attached.", false)
    case "hype_ping": {
      const session = await ensureAttached()
      if (!session) return textContent("No Hype session attached.", true)
      const state = await debugRPC(session.socketPath, "debug/hello", {})
      return textContent(JSON.stringify(state, null, 2), false)
    }
    default: {
      const session = await ensureAttached()
      if (!session) return textContent("No active Hype session attached. Launch Hype.app or call hype_attach_session.", true)
      try {
        const result = (await debugRPC(session.socketPath, "debug/callTool", { name, arguments: args })) as { text?: string; isError?: boolean }
        return textContent(result.text ?? "", result.isError === true)
      } catch (error) {
        attached = null
        return textContent(error instanceof Error ? error.message : "Hype debug call failed", true)
      }
    }
  }
}

function textContent(text: string, isError: boolean): JsonObject {
  return { content: [{ type: "text", text }], isError }
}

function sendResult(id: unknown, result: JsonObject): void {
  send({ jsonrpc: "2.0", id: id ?? null, result })
}

function sendError(id: unknown, code: number, message: string): void {
  send({ jsonrpc: "2.0", id: id ?? null, error: { code, message } })
}

function send(message: JsonObject): void {
  const json = JSON.stringify(message)
  process.stdout.write(`Content-Length: ${Buffer.byteLength(json, "utf8")}\r\n\r\n${json}`)
}
