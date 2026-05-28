import fs from "node:fs/promises"
import fsSync from "node:fs"
import net from "node:net"
import os from "node:os"
import path from "node:path"
import process from "node:process"
import { fileURLToPath } from "node:url"

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

interface McpResource {
  uri: string
  name: string
  description: string
  mimeType?: string
}

interface McpPrompt {
  name: string
  description: string
  arguments?: JsonObject[]
}

let nextDebugId = 1
let attached: HypeSessionDescriptor | null = null
let stdinBuffer = Buffer.alloc(0)
let stdoutFraming: "content-length" | "json-line" = "content-length"
const debugConnections = new Map<string, DebugConnection>()
let discoveryPollInFlight = false

const discoveryPollIntervalMs = 2_000
const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..")

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
  {
    name: "hype_import_hypercard_stack",
    description: "Debugger-only import of a HyperCard stack file. Creates and opens a new temporary .hype document in Hype.app.",
    inputSchema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Absolute path to the HyperCard stack data fork." },
      },
      required: ["path"],
    },
  },
  {
    name: "hype_debug_click_button",
    description: "Debugger-only click simulation for a named button on a card.",
    inputSchema: {
      type: "object",
      properties: {
        button: { type: "string", description: "Button name, e.g. Button 1." },
        card: { type: "string", description: "Optional card name, number, or id. Uses the active card when omitted." },
      },
      required: ["button"],
    },
  },
  {
    name: "hype_debug_script_state",
    description: "Debugger-only snapshot of card/background/stack and optional button script state.",
    inputSchema: {
      type: "object",
      properties: {
        card: { type: "string", description: "Optional card name, number, or id. Uses the active card when omitted." },
        button: { type: "string", description: "Optional button name to include its script." },
      },
      required: [],
    },
  },
]

function discoveryDirectory(): string {
  const configured = process.env.HYPE_DEBUG_SOCKET_DIR?.trim()
  if (configured && configured.length > 0) {
    return configured.replace(/^~/, os.homedir())
  }

  return appSupportDiscoveryDirectory()
}

function appSupportDiscoveryDirectory(): string {
  return path.join(os.homedir(), "Library", "Application Support", "Hype", "debug")
}

function discoveryDirectories(): string[] {
  const configured = process.env.HYPE_DEBUG_SOCKET_DIR?.trim()
  if (configured && configured.length > 0) {
    return [configured.replace(/^~/, os.homedir())]
  }

  const directories = [appSupportDiscoveryDirectory()]
  const repoLocal = path.join(repoRoot, ".hype", "debug")
  if (fsSync.existsSync(repoLocal)) {
    directories.push(repoLocal)
  }
  return directories
}

async function discoverSessions(): Promise<HypeSessionDescriptor[]> {
  const sessions: HypeSessionDescriptor[] = []
  for (const dir of discoveryDirectories()) {
    let entries: string[] = []
    try {
      entries = await fs.readdir(dir)
    } catch {
      continue
    }

    for (const entry of entries) {
      if (!entry.endsWith(".json")) continue
      const descriptorPath = path.join(dir, entry)
      try {
        const descriptor = JSON.parse(await fs.readFile(descriptorPath, "utf8")) as HypeSessionDescriptor
        if (!descriptor.instanceId || !descriptor.socketPath || !descriptor.pid) continue
        if (!isPidLive(descriptor.pid)) {
          await pruneOrphanedSocket(descriptor, descriptorPath)
          continue
        }
        sessions.push(descriptor)
      } catch {
        continue
      }
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

async function pruneOrphanedSocket(session: HypeSessionDescriptor, descriptorPath?: string): Promise<void> {
  try { await fs.rm(session.socketPath, { force: true }) } catch {}
  if (descriptorPath) {
    try { await fs.rm(descriptorPath, { force: true }) } catch {}
  }
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
      await debugRPC(attached.socketPath, "debug/keepalive", {})
      return attached
    } catch {
      closeDebugConnection(attached.socketPath)
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

function startBackgroundDiscovery(): void {
  void pollForAttach()
  const timer = setInterval(() => {
    void pollForAttach()
  }, discoveryPollIntervalMs)
  timer.unref()
}

async function pollForAttach(): Promise<void> {
  if (discoveryPollInFlight) return
  discoveryPollInFlight = true
  try {
    await ensureAttached()
  } catch {
    // Discovery is opportunistic; MCP startup and detached connection tools must
    // keep working while Hype.app is not running or is between debug sockets.
  } finally {
    discoveryPollInFlight = false
  }
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
  await debugRPC(attached.socketPath, "debug/keepalive", {})
  return `Attached to Hype session ${attached.instanceId}${attached.activeDocumentName ? ` (${attached.activeDocumentName})` : ""}`
}

function stringArg(args: JsonObject, key: string): string {
  const value = args[key]
  return typeof value === "string" ? value.trim() : ""
}

interface PendingDebugRequest {
  resolve: (value: unknown) => void
  reject: (error: Error) => void
  timer: NodeJS.Timeout
}

class DebugConnection {
  private socket: net.Socket | null = null
  private buffer = ""
  private connectPromise: Promise<void> | null = null
  private readonly pending = new Map<number, PendingDebugRequest>()
  private readonly keepalive: NodeJS.Timeout

  constructor(private readonly socketPath: string) {
    this.keepalive = setInterval(() => {
      void this.request("debug/keepalive", {}).catch(() => this.close())
    }, 10_000)
    this.keepalive.unref()
  }

  async request(method: string, params: JsonObject): Promise<unknown> {
    await this.connect()
    const socket = this.socket
    if (!socket || socket.destroyed) throw new Error("Hype debug socket is not connected")

    const id = nextDebugId++
    const request = JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n"
    return await new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id)
        reject(new Error("Hype debug request timed out"))
      }, 5_000)
      this.pending.set(id, { resolve, reject, timer })
      socket.write(request, (error) => {
        if (error) {
          this.rejectPending(id, error)
          this.close()
        }
      })
    })
  }

  close(): void {
    clearInterval(this.keepalive)
    if (this.socket && !this.socket.destroyed) this.socket.destroy()
    this.socket = null
    this.connectPromise = null
    for (const [id, pending] of this.pending) {
      clearTimeout(pending.timer)
      pending.reject(new Error("Hype debug connection closed"))
      this.pending.delete(id)
    }
  }

  private async connect(): Promise<void> {
    if (this.socket && !this.socket.destroyed) return
    if (this.connectPromise) return await this.connectPromise

    this.connectPromise = new Promise<void>((resolve, reject) => {
      const socket = net.createConnection(this.socketPath)
      let settled = false
      const timer = setTimeout(() => {
        if (settled) return
        settled = true
        socket.destroy()
        reject(new Error("Hype debug connection timed out"))
      }, 5_000)

      socket.on("connect", () => {
        if (settled) return
        settled = true
        clearTimeout(timer)
        this.socket = socket
        resolve()
      })
      socket.on("data", (chunk) => this.handleData(chunk))
      socket.on("error", (error) => {
        if (!settled) {
          settled = true
          clearTimeout(timer)
          reject(error)
        }
        this.close()
      })
      socket.on("close", () => this.close())
    }).finally(() => {
      this.connectPromise = null
    })

    await this.connectPromise
  }

  private handleData(chunk: Buffer): void {
    this.buffer += chunk.toString("utf8")
    while (this.buffer.includes("\n")) {
      const newline = this.buffer.indexOf("\n")
      const line = this.buffer.slice(0, newline)
      this.buffer = this.buffer.slice(newline + 1)
      if (!line.trim()) continue
      let response: JsonObject
      try {
        response = JSON.parse(line) as JsonObject
      } catch {
        continue
      }
      const id = typeof response.id === "number" ? response.id : undefined
      if (id === undefined) continue
      const pending = this.pending.get(id)
      if (!pending) continue
      this.pending.delete(id)
      clearTimeout(pending.timer)
      if (response.error) {
        const error = response.error as { message?: string }
        pending.reject(new Error(error.message ?? "Hype debug error"))
      } else {
        pending.resolve(response.result)
      }
    }
  }

  private rejectPending(id: number, error: Error): void {
    const pending = this.pending.get(id)
    if (!pending) return
    this.pending.delete(id)
    clearTimeout(pending.timer)
    pending.reject(error)
  }
}

async function debugRPC(socketPath: string, method: string, params: JsonObject): Promise<unknown> {
  let connection = debugConnections.get(socketPath)
  if (!connection) {
    connection = new DebugConnection(socketPath)
    debugConnections.set(socketPath, connection)
  }
  try {
    return await connection.request(method, params)
  } catch (error) {
    closeDebugConnection(socketPath)
    throw error
  }
}

function closeDebugConnection(socketPath: string): void {
  const connection = debugConnections.get(socketPath)
  if (!connection) return
  debugConnections.delete(socketPath)
  connection.close()
}

process.stdin.on("data", (chunk) => {
  stdinBuffer = Buffer.concat([stdinBuffer, chunk])
  void processMessages()
})

async function processMessages(): Promise<void> {
  while (true) {
    const headerBoundary = findHeaderBoundary(stdinBuffer)
    if (headerBoundary) {
      stdoutFraming = "content-length"
      const { headerEnd, bodyOffset } = headerBoundary
      const header = stdinBuffer.slice(0, headerEnd).toString("utf8")
      const match = /^content-length:\s*(\d+)$/im.exec(header)
      if (!match) {
        stdinBuffer = Buffer.alloc(0)
        return
      }
      const length = Number(match[1])
      const bodyStart = bodyOffset
      if (stdinBuffer.length < bodyStart + length) return
      const body = stdinBuffer.slice(bodyStart, bodyStart + length).toString("utf8")
      stdinBuffer = stdinBuffer.slice(bodyStart + length)
      await processMessageBody(body)
      continue
    }

    const lineEnd = stdinBuffer.indexOf("\n")
    if (lineEnd < 0) return
    stdoutFraming = "json-line"
    const body = stdinBuffer.slice(0, lineEnd).toString("utf8").trim()
    stdinBuffer = stdinBuffer.slice(lineEnd + 1)
    if (!body) continue
    await processMessageBody(body)
  }
}

async function processMessageBody(body: string): Promise<void> {
  let message: JsonObject
  try {
    message = JSON.parse(body) as JsonObject
  } catch {
    send({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } })
    return
  }
  await handleMCPMessage(message)
}

function findHeaderBoundary(buffer: Buffer): { headerEnd: number; bodyOffset: number } | null {
  const crlf = buffer.indexOf("\r\n\r\n")
  const lf = buffer.indexOf("\n\n")

  if (crlf < 0 && lf < 0) return null
  if (crlf >= 0 && (lf < 0 || crlf <= lf)) {
    return { headerEnd: crlf, bodyOffset: crlf + 4 }
  }
  return { headerEnd: lf, bodyOffset: lf + 2 }
}

async function handleMCPMessage(message: JsonObject): Promise<void> {
  const method = typeof message.method === "string" ? message.method : ""
  const id = message.id
  if (!id && method.startsWith("notifications/")) return

  try {
    switch (method) {
      case "initialize":
        sendResult(id, {
          protocolVersion: "2025-06-18",
          capabilities: {
            tools: { listChanged: false },
            resources: { subscribe: false, listChanged: false },
            prompts: { listChanged: false },
          },
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
      case "resources/list":
        sendResult(id, { resources: await listResources() })
        return
      case "resources/read":
        sendResult(id, await readResource((message.params as JsonObject | undefined) ?? {}))
        return
      case "prompts/list":
        sendResult(id, { prompts: await listPrompts() })
        return
      case "prompts/get":
        sendResult(id, await getPrompt((message.params as JsonObject | undefined) ?? {}))
        return
      default:
        sendError(id, -32601, "Method not found")
    }
  } catch (error) {
    sendError(id, -32603, error instanceof Error ? error.message : "Internal error")
  }
}

async function listTools(): Promise<McpTool[]> {
  const session = attached
  if (!session) return connectionTools
  if (discoveryPollInFlight) return connectionTools
  try {
    const result = (await debugRPC(session.socketPath, "debug/listTools", {})) as { tools?: McpTool[] }
    return [...connectionTools, ...(result.tools ?? [])]
  } catch {
    attached = null
    return connectionTools
  }
}

async function listResources(): Promise<McpResource[]> {
  const session = attached
  if (!session) {
    return [{
      uri: "hype://app/state",
      name: "App State",
      description: "Current Hype app and debug-session state.",
      mimeType: "application/json",
    }]
  }
  if (discoveryPollInFlight) {
    return [{
      uri: "hype://app/state",
      name: "App State",
      description: "Current Hype app and debug-session state.",
      mimeType: "application/json",
    }]
  }
  try {
    const result = (await debugRPC(session.socketPath, "debug/listResources", {})) as { resources?: McpResource[] }
    return result.resources ?? []
  } catch {
    attached = null
    return []
  }
}

async function readResource(params: JsonObject): Promise<JsonObject> {
  const uri = stringArg(params, "uri")
  if (!uri) throw new Error("resources/read requires params.uri")
  const session = await ensureAttached()
  if (!session) {
    return {
      contents: [{
        uri,
        mimeType: "application/json",
        text: JSON.stringify({ error: "No active Hype session attached." }, null, 2),
      }],
    }
  }
  const result = (await debugRPC(session.socketPath, "debug/readResource", { uri })) as {
    uri?: string
    mimeType?: string
    value?: unknown
  }
  return {
    contents: [{
      uri: result.uri ?? uri,
      mimeType: result.mimeType ?? "application/json",
      text: JSON.stringify(result.value ?? null, null, 2),
    }],
  }
}

async function listPrompts(): Promise<McpPrompt[]> {
  const session = attached
  if (!session) return []
  if (discoveryPollInFlight) return []
  try {
    const result = (await debugRPC(session.socketPath, "debug/listPrompts", {})) as { prompts?: McpPrompt[] }
    return result.prompts ?? []
  } catch {
    attached = null
    return []
  }
}

async function getPrompt(params: JsonObject): Promise<JsonObject> {
  const name = stringArg(params, "name")
  if (!name) throw new Error("prompts/get requires params.name")
  const session = await ensureAttached()
  if (!session) throw new Error("No active Hype session attached.")
  const result = (await debugRPC(session.socketPath, "debug/getPrompt", {
    name,
    arguments: (params.arguments as JsonObject | undefined) ?? {},
  })) as { value?: JsonObject }
  return result.value ?? {}
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
      if (attached) closeDebugConnection(attached.socketPath)
      attached = null
      return textContent("Detached from Hype session.", false)
    case "hype_active_session":
      return textContent(attached ? JSON.stringify(await enrichSession(attached), null, 2) : "No Hype session attached.", false)
    case "hype_ping": {
      const session = await ensureAttached()
      if (!session) return textContent("No Hype session attached.", true)
      const state = await debugRPC(session.socketPath, "debug/getState", {})
      return textContent(JSON.stringify(state, null, 2), false)
    }
    case "hype_import_hypercard_stack": {
      const session = await ensureAttached()
      if (!session) return textContent("No Hype session attached.", true)
      const path = stringArg(args, "path")
      if (!path) return textContent("hype_import_hypercard_stack requires path.", true)
      const result = await debugRPC(session.socketPath, "debug/importHyperCardStack", { path })
      return textContent(JSON.stringify(result, null, 2), false)
    }
    case "hype_debug_click_button": {
      const session = await ensureAttached()
      if (!session) return textContent("No Hype session attached.", true)
      const button = stringArg(args, "button")
      if (!button) return textContent("hype_debug_click_button requires button.", true)
      const card = stringArg(args, "card")
      const result = await debugRPC(session.socketPath, "debug/clickButton", { button, card })
      return textContent(JSON.stringify(result, null, 2), false)
    }
    case "hype_debug_script_state": {
      const session = await ensureAttached()
      if (!session) return textContent("No Hype session attached.", true)
      const result = await debugRPC(session.socketPath, "debug/getScriptState", {
        card: stringArg(args, "card"),
        button: stringArg(args, "button"),
      })
      return textContent(JSON.stringify(result, null, 2), false)
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
  if (stdoutFraming === "json-line") {
    process.stdout.write(`${json}\n`)
    return
  }
  process.stdout.write(`Content-Length: ${Buffer.byteLength(json, "utf8")}\r\n\r\n${json}`)
}

function ensureSocketDirectory(): void {
  const socketDir = discoveryDirectory()
  try {
    fsSync.mkdirSync(socketDir, { recursive: true, mode: 0o700 })
  } catch {
    // Directory may already exist
  }
}

function bootstrap(): void {
  ensureSocketDirectory()
  startBackgroundDiscovery()
}

bootstrap()
