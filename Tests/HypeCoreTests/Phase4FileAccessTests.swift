import Testing
import Foundation
@testable import HypeCore

// MARK: - Temp directory helpers

/// Create a fresh temporary directory for sandbox testing.
/// Caller is responsible for cleanup (deferred removal).
private func makeTempRoot() throws -> URL {
    let tmp = FileManager.default.temporaryDirectory
    let dir = tmp.appendingPathComponent("HypePhase4Tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Write `content` directly to `url`, bypassing the sandbox (test setup only).
private func writeRaw(_ content: String, to url: URL) throws {
    let parent = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    try Data(content.utf8).write(to: url)
}

// MARK: - SandboxedFileAccessProvider.resolveSandboxedURL unit tests

@Suite("Phase 4 — SandboxedFileAccessProvider path validation", .serialized)
struct Phase4PathValidationTests {

    @Test("accepts plain filename")
    func acceptsPlainFilename() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try SandboxedFileAccessProvider.resolveSandboxedURL(name: "a.txt", root: root)
        #expect(url.lastPathComponent == "a.txt")
    }

    @Test("accepts subdirectory path")
    func acceptsSubdirectoryPath() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try SandboxedFileAccessProvider.resolveSandboxedURL(name: "sub/a.txt", root: root)
        #expect(url.path.hasSuffix("sub/a.txt"))
    }

    @Test("rejects empty name")
    func rejectsEmptyName() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: FileAccessError.invalidPath) {
            try SandboxedFileAccessProvider.resolveSandboxedURL(name: "", root: root)
        }
    }

    @Test("rejects whitespace-only name")
    func rejectsWhitespaceName() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: FileAccessError.invalidPath) {
            try SandboxedFileAccessProvider.resolveSandboxedURL(name: "   ", root: root)
        }
    }

    @Test("rejects absolute path")
    func rejectsAbsolutePath() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: FileAccessError.invalidPath) {
            try SandboxedFileAccessProvider.resolveSandboxedURL(name: "/etc/passwd", root: root)
        }
    }

    @Test("rejects simple traversal '../escape'")
    func rejectsSimpleTraversal() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: (any Error).self) {
            try SandboxedFileAccessProvider.resolveSandboxedURL(name: "../escape", root: root)
        }
    }

    @Test("rejects deep traversal 'sub/../../escape'")
    func rejectsDeepTraversal() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: (any Error).self) {
            try SandboxedFileAccessProvider.resolveSandboxedURL(name: "sub/../../escape", root: root)
        }
    }

    @Test("rejects symlink inside root pointing outside")
    func rejectsSymlinkOutsideRoot() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // Create a target outside the root.
        let externalTarget = FileManager.default.temporaryDirectory
            .appendingPathComponent("HypePhase4Ext-\(UUID().uuidString)")
        try Data("external".utf8).write(to: externalTarget)
        defer { try? FileManager.default.removeItem(at: externalTarget) }
        // Create a symlink inside the root pointing to the external file.
        let linkURL = root.appendingPathComponent("evil.txt")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: externalTarget)
        #expect(throws: FileAccessError.outsideSandbox) {
            try SandboxedFileAccessProvider.resolveSandboxedURL(name: "evil.txt", root: root)
        }
    }

    @Test("rejects sibling-prefix path '../<rootname>-evil/x'")
    func rejectsSiblingPrefix() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let siblingName = root.lastPathComponent + "-evil"
        let attempt = "../\(siblingName)/x"
        #expect(throws: (any Error).self) {
            try SandboxedFileAccessProvider.resolveSandboxedURL(name: attempt, root: root)
        }
    }
}

// MARK: - SandboxedFileAccessProvider I/O tests

@Suite("Phase 4 — SandboxedFileAccessProvider I/O", .serialized)
struct Phase4FileIOTests {

    @Test("read happy path")
    func readHappyPath() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("hello.txt")
        try writeRaw("Hello, World!", to: fileURL)
        let provider = SandboxedFileAccessProvider(root: root)
        let contents = try await provider.readFile(named: "hello.txt")
        #expect(contents == "Hello, World!")
    }

    @Test("read missing file — .notFound")
    func readMissing() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = SandboxedFileAccessProvider(root: root)
        await #expect(throws: FileAccessError.notFound) {
            try await provider.readFile(named: "does-not-exist.txt")
        }
    }

    @Test("write then readback")
    func writeThenReadback() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = SandboxedFileAccessProvider(root: root)
        try await provider.writeFile("test content", named: "out.txt")
        let contents = try await provider.readFile(named: "out.txt")
        #expect(contents == "test content")
    }

    @Test("overwrite replaces not appends")
    func overwriteReplaces() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = SandboxedFileAccessProvider(root: root)
        try await provider.writeFile("first", named: "f.txt")
        try await provider.writeFile("second", named: "f.txt")
        let contents = try await provider.readFile(named: "f.txt")
        #expect(contents == "second", "overwrite should replace, not append")
    }

    @Test("StubFileAccessProvider.readFile throws .accessDenied")
    func stubReadDenied() async throws {
        let stub = StubFileAccessProvider()
        await #expect(throws: FileAccessError.accessDenied) {
            try await stub.readFile(named: "anything.txt")
        }
    }

    @Test("StubFileAccessProvider.writeFile throws .accessDenied")
    func stubWriteDenied() async throws {
        let stub = StubFileAccessProvider()
        await #expect(throws: FileAccessError.accessDenied) {
            try await stub.writeFile("data", named: "anything.txt")
        }
    }

    @Test("SandboxedFileAccessProvider(root: nil) denies reads")
    func nilRootDeniesRead() async throws {
        let provider = SandboxedFileAccessProvider(root: nil)
        await #expect(throws: FileAccessError.accessDenied) {
            try await provider.readFile(named: "x.txt")
        }
    }

    @Test("SandboxedFileAccessProvider(root: nil) denies writes")
    func nilRootDeniesWrite() async throws {
        let provider = SandboxedFileAccessProvider(root: nil)
        await #expect(throws: FileAccessError.accessDenied) {
            try await provider.writeFile("data", named: "x.txt")
        }
    }

    @Test("write >10MB — .tooLarge")
    func writeTooLarge() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = SandboxedFileAccessProvider(root: root)
        let oversized = String(repeating: "x", count: SandboxedFileAccessProvider.maxWriteBytes + 1)
        await #expect(throws: FileAccessError.tooLarge) {
            try await provider.writeFile(oversized, named: "big.txt")
        }
    }

    @Test("read pre-placed >10MB file — .tooLarge")
    func readTooLarge() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // Write a file that is just over the read limit directly via FileManager.
        let oversize = Data(repeating: 0x41, count: SandboxedFileAccessProvider.maxReadBytes + 1)
        let fileURL = root.appendingPathComponent("big.txt")
        try oversize.write(to: fileURL)
        let provider = SandboxedFileAccessProvider(root: root)
        await #expect(throws: FileAccessError.tooLarge) {
            try await provider.readFile(named: "big.txt")
        }
    }
}

// MARK: - FileAccessError.scriptMessage security test

@Suite("Phase 4 — FileAccessError message does not leak paths", .serialized)
struct Phase4ErrorMessageTests {

    @Test("scriptMessage contains no file system path")
    func scriptMessageNoPath() {
        let errors: [FileAccessError] = [.accessDenied, .invalidPath, .outsideSandbox, .tooLarge, .notFound, .ioFailure]
        for e in errors {
            let msg = e.scriptMessage
            #expect(!msg.contains("/"), "scriptMessage must not contain a path separator: '\(msg)'")
        }
    }
}

// MARK: - Interpreter integration tests

/// Build a minimal document and run a script through `MessageDispatcher`.
private func makeDoc4F() -> (doc: HypeDocument, cardId: UUID, btnId: UUID) {
    var doc = HypeDocument.newDocument(name: "Phase4FileTest")
    let cardId = doc.sortedCards[0].id
    let btn = Part(partType: .button, cardId: cardId, name: "Btn",
                   left: 10, top: 10, width: 80, height: 30)
    doc.addPart(btn)
    return (doc, cardId, btn.id)
}

@Suite("Phase 4 — Interpreter file access integration", .serialized)
struct Phase4InterpreterFileTests {

    @Test("read from file with denying provider — ScriptError 'File access is not enabled'")
    func readWithDenyingProvider() async {
        let (doc, cardId, btnId) = makeDoc4F()
        var d = doc
        d.updatePart(id: btnId) { $0.script = "on mouseUp\n  read from file \"x.txt\"\nend mouseUp" }
        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [d] in
            dispatcher.dispatch(
                message: "mouseUp", params: [], targetId: btnId,
                document: d, currentCardId: cardId,
                fileProvider: StubFileAccessProvider()  // deny-all
            )
        }
        #expect(result.status == .error, "read with deny provider should error")
        #expect(result.error?.message == FileAccessError.accessDenied.scriptMessage,
                "error message should match FileAccessError.accessDenied.scriptMessage")
    }

    @Test("read from file with sandbox provider — `it` populated with file contents")
    func readSetsIt() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("data.txt")
        try writeRaw("hello from file", to: fileURL)

        let (doc, cardId, btnId) = makeDoc4F()
        var d = doc
        let fld = Part(partType: .field, cardId: cardId, name: "Out",
                       left: 0, top: 0, width: 100, height: 30)
        d.addPart(fld)
        let fieldId = fld.id
        d.updatePart(id: btnId) { $0.script = """
on mouseUp
  read from file "data.txt"
  put it into field "Out"
end mouseUp
""" }
        let dispatcher = MessageDispatcher()
        let provider = SandboxedFileAccessProvider(root: root)
        let result = await runOnLargeStack { [d] in
            dispatcher.dispatch(
                message: "mouseUp", params: [], targetId: btnId,
                document: d, currentCardId: cardId,
                fileProvider: provider
            )
        }
        let modified = result.modifiedDocument ?? d
        let outText = modified.parts.first(where: { $0.id == fieldId })?.textContent
        #expect(outText == "hello from file", "it should contain the file contents")
    }

    @Test("ScriptError from read does NOT contain the sandbox temp-dir path (Finding 7)")
    func errorMessageDoesNotLeakPath() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let (doc, cardId, btnId) = makeDoc4F()
        var d = doc
        d.updatePart(id: btnId) { $0.script = "on mouseUp\n  read from file \"missing.txt\"\nend mouseUp" }
        let dispatcher = MessageDispatcher()
        let provider = SandboxedFileAccessProvider(root: root)
        let result = await runOnLargeStack { [d] in
            dispatcher.dispatch(
                message: "mouseUp", params: [], targetId: btnId,
                document: d, currentCardId: cardId,
                fileProvider: provider
            )
        }
        #expect(result.status == .error)
        let errorMsg = result.error?.message ?? ""
        #expect(!errorMsg.contains(root.path),
                "ScriptError.message must not contain the absolute temp dir path. Got: '\(errorMsg)'")
        #expect(!errorMsg.contains("/tmp"),
                "ScriptError.message must not contain /tmp. Got: '\(errorMsg)'")
    }

    @Test("write to file then read back via interpreter")
    func writeAndReadBack() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let (doc, cardId, btnId) = makeDoc4F()
        var d = doc
        let fld = Part(partType: .field, cardId: cardId, name: "Result",
                       left: 0, top: 0, width: 100, height: 30)
        d.addPart(fld)
        let fieldId = fld.id
        d.updatePart(id: btnId) { $0.script = """
on mouseUp
  write "written content" to file "result.txt"
  read from file "result.txt"
  put it into field "Result"
end mouseUp
""" }
        let dispatcher = MessageDispatcher()
        let provider = SandboxedFileAccessProvider(root: root)
        let result = await runOnLargeStack { [d] in
            dispatcher.dispatch(
                message: "mouseUp", params: [], targetId: btnId,
                document: d, currentCardId: cardId,
                fileProvider: provider
            )
        }
        #expect(result.status != .error, "write+read should succeed: \(result.error?.message ?? "nil")")
        let modified = result.modifiedDocument ?? d
        let outText = modified.parts.first(where: { $0.id == fieldId })?.textContent
        #expect(outText == "written content")
    }

    /// Regression (security code-review finding): the `fileProvider` (and
    /// `hostProvider`) must propagate through `send`-dispatched handlers.
    /// Before the fix, `MessageDispatcher.dispatchAsync` invoked from the
    /// interpreter's `.send` case omitted these args, so a handler reached
    /// via `send` silently received `StubFileAccessProvider()` (deny-all)
    /// and `read`/`write file` failed with "File access is not enabled"
    /// even when the stack had file access on. This test would FAIL (empty
    /// field / accessDenied error) prior to threading `context.fileProvider`
    /// into the `.send` dispatch.
    @Test("file access propagates through `send` to another handler")
    func fileProviderPropagatesThroughSend() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRaw("via send", to: root.appendingPathComponent("data.txt"))

        let (doc, cardId, btnId) = makeDoc4F()
        var d = doc
        let fld = Part(partType: .field, cardId: cardId, name: "Out",
                       left: 0, top: 0, width: 100, height: 30)
        d.addPart(fld)
        let fieldId = fld.id
        d.updatePart(id: btnId) { $0.script = """
on mouseUp
  send "doRead" to me
end mouseUp

on doRead
  read from file "data.txt"
  put it into field "Out"
end doRead
""" }
        let dispatcher = MessageDispatcher()
        let provider = SandboxedFileAccessProvider(root: root)
        let result = await runOnLargeStack { [d] in
            dispatcher.dispatch(
                message: "mouseUp", params: [], targetId: btnId,
                document: d, currentCardId: cardId,
                fileProvider: provider
            )
        }
        #expect(result.status != .error,
                "send-dispatched read should succeed: \(result.error?.message ?? "nil")")
        let modified = result.modifiedDocument ?? d
        let outText = modified.parts.first(where: { $0.id == fieldId })?.textContent
        #expect(outText == "via send",
                "file contents read inside a send-dispatched handler must reach the field")
    }
}
