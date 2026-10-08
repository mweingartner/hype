import Foundation
import Testing
@testable import HypeCore

#if os(macOS)
@Suite("Installed app MCP stdio bridge")
struct MCPStdioBridgeClientTests {
    @Test("Typed requests and structured results cross the real child process")
    func structuredReply() async throws {
        let executable = try fixture("""
        import sys,json
        for line in sys.stdin:
          r=json.loads(line)
          if 'id' not in r: continue
          result={'protocolVersion':'2025-11-25','capabilities':{}}
          if r['method']=='tools/call': result={'structuredContent':r['params']['arguments']}
          print(json.dumps({'jsonrpc':'2.0','id':r['id'],'result':result}),flush=True)
        """)
        defer { try? FileManager.default.removeItem(at: executable) }
        let client = MCPStdioBridgeClient(executableURL: executable)
        let arguments: [String: HypeMCPJSONValue] = ["text": .string("Exact words"), "pace": .number(0.9)]
        #expect(try await client.callTool("chatter_speak", arguments: arguments) == .object(arguments))
    }

    @Test("Text content JSON is supported; isError remains a failure")
    func errorReply() async throws {
        let executable = try fixture("""
        import sys,json
        for line in sys.stdin:
          r=json.loads(line)
          if 'id' not in r: continue
          result={'protocolVersion':'2025-11-25','capabilities':{}}
          if r['method']=='tools/call': result={'content':[{'type':'text','text':'Voice is not available'}],'isError':True}
          print(json.dumps({'jsonrpc':'2.0','id':r['id'],'result':result}),flush=True)
        """)
        defer { try? FileManager.default.removeItem(at: executable) }
        do { _ = try await MCPStdioBridgeClient(executableURL: executable).callTool("chatter_speak", arguments: [:]); Issue.record("Expected MCP failure") }
        catch { #expect(error.localizedDescription == "Voice is not available") }
    }

    @Test("Child deadlines and cancellation terminate stalled proxies")
    func interruption() async throws {
        let executable = try fixture("import time\ntime.sleep(10)")
        defer { try? FileManager.default.removeItem(at: executable) }
        let start = ContinuousClock.now
        do { _ = try await MCPStdioBridgeClient(executableURL: executable, timeout: 0.2).callTool("chatter_voices", arguments: [:]); Issue.record("Expected timeout") }
        catch { #expect(error.localizedDescription.contains("timed out")) }
        #expect(start.duration(to: .now) < .seconds(3))
        let task = Task { try await MCPStdioBridgeClient(executableURL: executable).callTool("chatter_voices", arguments: [:]) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
    }

    @Test("Rejected initialization never sends a speech request")
    func handshakeFailure() async throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("hype-init-\(UUID().uuidString).txt")
        let executable = try fixture("""
        import sys,json
        for line in sys.stdin:
          r=json.loads(line)
          with open('\(log.path)','a') as f: f.write(r['method']+'\\n')
          print(json.dumps({'jsonrpc':'2.0','id':r.get('id'),'error':{'code':-32000,'message':'Connection refused'}}),flush=True)
        """)
        defer { try? FileManager.default.removeItem(at: executable); try? FileManager.default.removeItem(at: log) }
        do { _ = try await MCPStdioBridgeClient(executableURL: executable).callTool("chatter_speak", arguments: ["text": .string("Must not speak")]); Issue.record("Expected initialization failure") }
        catch { #expect(error.localizedDescription == "Connection refused") }
        #expect(try String(contentsOf: log, encoding: .utf8) == "initialize\n")
    }

    private func fixture(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hype-mcp-\(UUID().uuidString).py")
        try Data(("#!/usr/bin/python3\n" + body + "\n").utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
#endif
