import Foundation
import HypeCore
import ArgumentParser

struct HypeTalkBenchmarkSuite {
    struct Case {
        enum Mode {
            case handler
            case idleBurst(partCount: Int)
        }

        var name: String
        var script: String
        var handler: String = "main"
        var mode: Mode = .handler
    }

    static let cases: [Case] = [
        Case(name: "looping-and-expressions", script: """
        on main
          put 0 into total
          put empty into bucket
          repeat with i from 1 to 750
            add i to total
            if i mod 5 is 0 then
              put total & comma after bucket
            else
              put word 1 of "alpha beta gamma" into token
            end if
          end repeat
          return total
        end main
        """),
        Case(name: "property-access", script: """
        on main
          create field "output"
          set the width of field "output" to 200
          put empty into seen
          repeat with i from 1 to 350
            put "row" && i into field "output"
            set the left of field "output" to i mod 240
            put the left of field "output" into x
            put the text of field "output" after seen
          end repeat
          return length(seen)
        end main
        """),
        Case(name: "callbacks", script: """
        on main
          put empty into requests
          repeat with i from 1 to 250
            ask ai "summarize turn" && i with message "aiFinished"
            put it after requests
          end repeat
          return length(requests)
        end main

        on aiFinished requestId, status
          return status
        end aiFinished
        """),
        Case(name: "realistic-mix", script: """
        on main
          create field "score"
          create button "start"
          put 0 into score
          put empty into log
          repeat with frame from 1 to 400
            add frame mod 9 to score
            set the name of button "start" to "start" && frame
            put the name of button 1 into buttonName
            put "score" && score into field "score"
            put the text of field "score" into fieldText
            if fieldText contains "score" then
              put char 1 to 5 of fieldText after log
            else
              put "miss" after log
            end if
            if frame mod 50 is 0 then
              ask ai "checkpoint" && frame with message "checkpointDone"
              put it after log
            end if
          end repeat
          return length(log)
        end main

        on checkpointDone requestId, status
          return requestId && status
        end checkpointDone
        """),
        Case(
            name: "idle-hook-burst",
            script: "",
            mode: .idleBurst(partCount: 12)
        )
    ]
}

struct HypeTalkBenchmarkReport: Codable {
    var iterations: Int
    var cases: [HypeTalkBenchmarkCaseReport]
    var totals: HypeTalkBenchmarkTotals
}

struct HypeTalkBenchmarkCaseReport: Codable {
    var name: String
    var iterations: Int
    var parseNanoseconds: UInt64
    var executionNanoseconds: UInt64
    var averageExecutionNanoseconds: UInt64
    var diagnostics: HypeTalkExecutionDiagnostics
}

struct HypeTalkBenchmarkTotals: Codable {
    var executionNanoseconds: UInt64
    var diagnostics: HypeTalkExecutionDiagnostics
}

enum HypeTalkBenchmarkFormat: String, ExpressibleByArgument {
    case text
    case json
}

struct HypeTalkBenchmarkRunner {
    var iterations: Int

    func run(cases: [HypeTalkBenchmarkSuite.Case], documentPath: String?) throws -> HypeTalkBenchmarkReport {
        let safeIterations = max(1, iterations)
        var reports: [HypeTalkBenchmarkCaseReport] = []
        var totalExecution: UInt64 = 0
        var totalDiagnostics = HypeTalkExecutionDiagnostics()

        for benchmarkCase in cases {
            if case .idleBurst(let partCount) = benchmarkCase.mode {
                let report = try runIdleBurstCase(
                    benchmarkCase,
                    iterations: safeIterations,
                    partCount: partCount
                )
                totalExecution += report.executionNanoseconds
                totalDiagnostics.merge(report.diagnostics)
                reports.append(report)
                continue
            }

            let parseStart = DispatchTime.now().uptimeNanoseconds
            let handler = try parseHandler(script: benchmarkCase.script, handlerName: benchmarkCase.handler)
            let parseElapsed = DispatchTime.now().uptimeNanoseconds - parseStart
            let profiler = HypeTalkExecutionProfiler()
            let runtime = BenchmarkRuntime()
            let interpreter = Interpreter()
            var executionElapsed: UInt64 = 0

            for _ in 0..<safeIterations {
                let doc = try loadDocument(path: documentPath)
                let context = ExecutionContext(
                    targetId: doc.cards[0].id,
                    currentCardId: doc.cards[0].id,
                    document: doc,
                    dialogProvider: StubDialogProvider(),
                    drawingProvider: StubDrawingProvider(),
                    systemProvider: StubSystemProvider(),
                    aiProvider: StubAIScriptingProvider(),
                    speechOutputProvider: StubSpeechOutputProvider(),
                    runtimeProvider: runtime,
                    profiler: profiler
                )
                let start = DispatchTime.now().uptimeNanoseconds
                let result = interpreter.execute(handler: handler, params: [], context: context)
                executionElapsed += DispatchTime.now().uptimeNanoseconds - start
                if case .error = result.status {
                    throw HypeCLIError.benchmarkFailed(benchmarkCase.name, result.error?.message ?? "unknown error")
                }
            }

            let diagnostics = profiler.snapshot()
            totalExecution += executionElapsed
            totalDiagnostics.merge(diagnostics)
            reports.append(
                HypeTalkBenchmarkCaseReport(
                    name: benchmarkCase.name,
                    iterations: safeIterations,
                    parseNanoseconds: parseElapsed,
                    executionNanoseconds: executionElapsed,
                    averageExecutionNanoseconds: executionElapsed / UInt64(safeIterations),
                    diagnostics: diagnostics
                )
            )
        }

        return HypeTalkBenchmarkReport(
            iterations: safeIterations,
            cases: reports,
            totals: HypeTalkBenchmarkTotals(executionNanoseconds: totalExecution, diagnostics: totalDiagnostics)
        )
    }

    private func parseHandler(script: String, handlerName: String) throws -> Handler {
        var lexer = Lexer(source: script)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let ast = try parser.parse()
        if let handler = ast.handlers.first(where: { $0.name.lowercased() == handlerName.lowercased() }) {
            return handler
        }
        if let handler = ast.handlers.first {
            return handler
        }
        throw HypeCLIError.noHandlerFound
    }

    private func runIdleBurstCase(
        _ benchmarkCase: HypeTalkBenchmarkSuite.Case,
        iterations: Int,
        partCount: Int
    ) throws -> HypeTalkBenchmarkCaseReport {
        let setupStart = DispatchTime.now().uptimeNanoseconds
        let (document, partIds) = makeIdleBurstDocument(partCount: partCount)
        let setupElapsed = DispatchTime.now().uptimeNanoseconds - setupStart

        let semaphore = DispatchSemaphore(value: 0)
        let box = IdleBurstBenchmarkBox()
        Task {
            let runtime = StackRuntime(
                document: document,
                configuration: StackRuntimeConfiguration()
            )
            var elapsed: UInt64 = 0
            for _ in 0..<iterations {
                let start = DispatchTime.now().uptimeNanoseconds
                await runtime.dispatchIdleBurst(
                    cardTargetID: document.cards[0].id,
                    partTargetIDs: partIds,
                    currentCardId: document.cards[0].id,
                    includeCardTarget: false
                )
                elapsed += DispatchTime.now().uptimeNanoseconds - start
            }
            let finalDocument = await runtime.currentDocument()
            box.executionNanoseconds = elapsed
            box.didMutate = finalDocument.parts.contains { part in
                partIds.contains(part.id) && part.left > 10
            }
            semaphore.signal()
        }
        semaphore.wait()

        guard box.didMutate else {
            throw HypeCLIError.benchmarkFailed(benchmarkCase.name, "idle burst did not mutate animated parts")
        }

        return HypeTalkBenchmarkCaseReport(
            name: benchmarkCase.name,
            iterations: iterations,
            parseNanoseconds: setupElapsed,
            executionNanoseconds: box.executionNanoseconds,
            averageExecutionNanoseconds: box.executionNanoseconds / UInt64(iterations),
            diagnostics: HypeTalkExecutionDiagnostics()
        )
    }

    private func makeIdleBurstDocument(partCount: Int) -> (HypeDocument, [UUID]) {
        var document = HypeDocument.newDocument()
        let cardId = document.cards[0].id
        var partIds: [UUID] = []
        for index in 0..<max(1, partCount) {
            var part = Part(
                partType: .button,
                cardId: cardId,
                name: "idle-\(index)",
                left: 10 + Double(index * 4),
                top: 10 + Double(index * 3),
                width: 48,
                height: 24
            )
            part.script = """
            on idle
              set the left of me to the left of me + 1
              set the top of me to the top of me + 1
            end idle
            """
            document.addPart(part)
            partIds.append(part.id)
        }
        return (document, partIds)
    }

    private func loadDocument(path: String?) throws -> HypeDocument {
        if let path {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try JSONDecoder().decode(HypeDocument.self, from: data)
        }
        return HypeDocument.newDocument()
    }
}

private final class IdleBurstBenchmarkBox: @unchecked Sendable {
    var executionNanoseconds: UInt64 = 0
    var didMutate = false
}

final class BenchmarkRuntime: ScriptRuntimeProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var properties: [UUID: [String: String]] = [:]

    func sleep(seconds: TimeInterval) async throws {}

    func navigateToCard(_ cardId: UUID) async {}

    func publishDocument(_ document: HypeDocument) async {}

    func enqueueMessage(
        _ message: String,
        params: [Value],
        targetId: UUID,
        currentCardId: UUID,
        mouseX: Double,
        mouseY: Double,
        scriptContext: ScriptDispatchContext?
    ) async {}

    func startAIRequest(prompt: String, model: String?, callbackMessage: String, owner: RuntimeOwnerContext) async throws -> UUID {
        UUID()
    }

    func startMeshyRequest(
        prompt: String,
        style: String?,
        model: String?,
        callbackMessage: String,
        owner: RuntimeOwnerContext
    ) async throws -> UUID {
        UUID()
    }

    func startRemeshRequest(
        sourceAssetName: String,
        targetPolycount: Int,
        callbackMessage: String,
        owner: RuntimeOwnerContext
    ) async throws -> UUID {
        UUID()
    }

    func startRetextureRequest(
        sourceAssetName: String,
        stylePrompt: String,
        callbackMessage: String,
        owner: RuntimeOwnerContext
    ) async throws -> UUID {
        UUID()
    }

    func setSpeechListenerActive(_ active: Bool, owner: RuntimeOwnerContext) async throws {}
    func isSpeechListenerActive() async -> Bool { false }
    func startHTTPRequest(_ spec: OutboundHTTPRequestSpec, owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func reply(to requestID: UUID, status: Int, headersText: String, body: String) async throws {}
    func startListener(_ spec: ListenerSpec, owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func connectTCP(_ spec: TCPConnectionSpec, owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func send(_ data: String, toConnection id: UUID) async throws {}
    func closeConnection(_ id: UUID) async {}
    func stopListener(_ id: UUID) async {}

    func runtimeProperty(objectType: String, id: UUID, property: String, argument: String?) async -> String {
        lock.withLock {
            properties[id]?[property.lowercased()] ?? ""
        }
    }

    func pushCardToHistory(_ cardId: UUID) async {}
    func popCardFromHistory() async -> UUID? { nil }
    func recentCards() async -> String { "" }

    // Phase 2 — no-op stubs for benchmark/CLI paths
    func setFoundState(_ state: FoundState?) async {}
    func foundState() async -> FoundState? { nil }
    func setSelectedState(_ state: SelectedState?) async {}
    func selectedState() async -> SelectedState? { nil }
    func setClickState(_ state: ClickState) async {}
    func clickState() async -> ClickState? { nil }
}

func printBenchmarkReport(_ report: HypeTalkBenchmarkReport, format: HypeTalkBenchmarkFormat) throws {
    switch format {
    case .json:
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        print(String(data: data, encoding: .utf8) ?? "{}")
    case .text:
        print("HypeTalk benchmark")
        print("iterations: \(report.iterations)")
        for item in report.cases {
            print("")
            print(item.name)
            print("  parse: \(formatMilliseconds(item.parseNanoseconds)) ms")
            print("  execute total: \(formatMilliseconds(item.executionNanoseconds)) ms")
            print("  execute avg: \(formatMilliseconds(item.averageExecutionNanoseconds)) ms")
            print("  statements: \(item.diagnostics.statements)")
            print("  expressions: \(item.diagnostics.expressions)")
            print("  property reads: \(item.diagnostics.propertyReads)")
            print("  property writes: \(item.diagnostics.propertyWrites)")
            print("  loop iterations: \(item.diagnostics.loopIterations)")
            print("  callback requests: \(item.diagnostics.callbackRequests)")
            printTopCounts("  hot statements", item.diagnostics.statementKinds)
            printTopCounts("  hot expressions", item.diagnostics.expressionKinds)
            printTopCounts("  hot property reads", item.diagnostics.propertyReadKinds)
        }
        print("")
        print("total execute: \(formatMilliseconds(report.totals.executionNanoseconds)) ms")
    }
}

private func printTopCounts(_ title: String, _ counts: [String: Int], limit: Int = 5) {
    let top = counts.sorted { lhs, rhs in
        if lhs.value == rhs.value { return lhs.key < rhs.key }
        return lhs.value > rhs.value
    }.prefix(limit)
    guard !top.isEmpty else { return }
    let rendered = top.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
    print("\(title): \(rendered)")
}

private func formatMilliseconds(_ nanoseconds: UInt64) -> String {
    String(format: "%.3f", Double(nanoseconds) / 1_000_000)
}
