import Foundation
@testable import HypeCore
import Testing

@Suite("HypeCLI Integration Tests")
struct HypeCLITests {

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var binaryPath: String {
        projectRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/hypetalk").path
    }

    private var scriptDir: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("HypeCLITests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func runHypetalkScript(_ script: String) -> ProcessResult {
        let scriptFile = scriptDir.appendingPathComponent("script.hypetalk")
        try? script.write(to: scriptFile, atomically: true, encoding: .utf8)

        return runBinary(filePath: scriptFile.path)
    }

    private func runBinary(filePath: String) -> ProcessResult {
        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = [filePath]
        process.currentDirectoryURL = projectRoot

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ProcessResult(stdout: "", stderr: error.localizedDescription, exitStatus: -1)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return ProcessResult(
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            exitStatus: process.terminationStatus
        )
    }

    @Test func testArithmeticAddition() {
        let result = runHypetalkScript("""
        on main
        put 2 + 3 into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "5")
    }

    @Test func testStringConcatenation() {
        let result = runHypetalkScript("""
        on main
        put "Hello, " & "World" into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "Hello, World")
    }

    @Test func testSpacedConcatenation() {
        let result = runHypetalkScript("""
        on main
        put "Hello" && "World" into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "Hello World")
    }

    @Test func testVariableAssignment() {
        let result = runHypetalkScript("""
        on main
        put 42 into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "42")
    }

    @Test func testNestedExpression() {
        let result = runHypetalkScript("""
        on main
        put (3 + 4) * 2 into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "14")
    }

    @Test func testStringLength() {
        let result = runHypetalkScript("""
        on main
        put length("Hello") into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "5")
    }

    @Test func testChunkWordOf() {
        let result = runHypetalkScript("""
        on main
        put word 2 of "one two three" into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "two")
    }

    @Test func testChunkCharOf() {
        let result = runHypetalkScript("""
        on main
        put char 1 of "Hello" into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "H")
    }

    @Test func testIsAOperator() {
        let result = runHypetalkScript("""
        on main
        if 42 is a number then
          return "yes"
        else
          return "no"
        end if
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "yes")
    }

    @Test func testIsNotAOperator() {
        let result = runHypetalkScript("""
        on main
        if "hello" is not a number then
          return "yes"
        else
          return "no"
        end if
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "yes")
    }

    @Test func testContainsOperator() {
        let result = runHypetalkScript("""
        on main
        if "Hello World" contains "World" then
          return "yes"
        else
          return "no"
        end if
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "yes")
    }

    @Test func testRepeatLoop() {
        let result = runHypetalkScript("""
        on main
        put 0 into total
        repeat with i from 1 to 5
          add i to total
        end repeat
        return total
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "15")
    }

    @Test func testIfThenElse() {
        let result = runHypetalkScript("""
        on main
        if 5 > 3 then
          return "greater"
        else
          return "lesser"
        end if
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "greater")
    }

    @Test func testIfElseIf() {
        let result = runHypetalkScript("""
        on main
        if 1 > 2 then
          return "a"
        else if 2 > 1 then
          return "b"
        else
          return "c"
        end if
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "b")
    }

    @Test func testDivideOperator() {
        let result = runHypetalkScript("""
        on main
        put 10 div 3 into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "3")
    }

    @Test func testModuloOperator() {
        let result = runHypetalkScript("""
        on main
        put 10 mod 3 into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "1")
    }

    @Test func testPowerOperator() {
        let result = runHypetalkScript("""
        on main
        put 2 ^ 8 into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "256")
    }

    @Test func testGlobalVariable() {
        let result = runHypetalkScript("""
        on main
        global x
        put 42 into x
        return x
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "42")
    }

    @Test func testExitRepeat() {
        let result = runHypetalkScript("""
        on main
        put 0 into i
        repeat 100
          add 1 to i
          if i > 10 then
            exit repeat
          end if
        end repeat
        return i
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "11")
    }

    @Test func testBeepStatement() {
        let result = runHypetalkScript("""
        on main
        beep
        return "ok"
        end main
        """)
        #expect(result.exitStatus == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "ok")
    }
}

struct ProcessResult: Sendable {
    let stdout: String
    let stderr: String
    let exitStatus: Int32
}