import Foundation

public struct HypeTalkExecutionDiagnostics: Codable, Sendable, Equatable {
    public var handlerInvocations: Int
    public var statements: Int
    public var expressions: Int
    public var propertyReads: Int
    public var propertyWrites: Int
    public var loopIterations: Int
    public var callbackRequests: Int
    public var statementKinds: [String: Int]
    public var expressionKinds: [String: Int]
    public var propertyReadKinds: [String: Int]
    public var propertyWriteKinds: [String: Int]
    public var callbackKinds: [String: Int]

    public init(
        handlerInvocations: Int = 0,
        statements: Int = 0,
        expressions: Int = 0,
        propertyReads: Int = 0,
        propertyWrites: Int = 0,
        loopIterations: Int = 0,
        callbackRequests: Int = 0,
        statementKinds: [String: Int] = [:],
        expressionKinds: [String: Int] = [:],
        propertyReadKinds: [String: Int] = [:],
        propertyWriteKinds: [String: Int] = [:],
        callbackKinds: [String: Int] = [:]
    ) {
        self.handlerInvocations = handlerInvocations
        self.statements = statements
        self.expressions = expressions
        self.propertyReads = propertyReads
        self.propertyWrites = propertyWrites
        self.loopIterations = loopIterations
        self.callbackRequests = callbackRequests
        self.statementKinds = statementKinds
        self.expressionKinds = expressionKinds
        self.propertyReadKinds = propertyReadKinds
        self.propertyWriteKinds = propertyWriteKinds
        self.callbackKinds = callbackKinds
    }

    public mutating func merge(_ other: HypeTalkExecutionDiagnostics) {
        handlerInvocations += other.handlerInvocations
        statements += other.statements
        expressions += other.expressions
        propertyReads += other.propertyReads
        propertyWrites += other.propertyWrites
        loopIterations += other.loopIterations
        callbackRequests += other.callbackRequests
        mergeCounts(other.statementKinds, into: &statementKinds)
        mergeCounts(other.expressionKinds, into: &expressionKinds)
        mergeCounts(other.propertyReadKinds, into: &propertyReadKinds)
        mergeCounts(other.propertyWriteKinds, into: &propertyWriteKinds)
        mergeCounts(other.callbackKinds, into: &callbackKinds)
    }

    private func mergeCounts(_ source: [String: Int], into destination: inout [String: Int]) {
        for (key, value) in source {
            destination[key, default: 0] += value
        }
    }
}

public final class HypeTalkExecutionProfiler: @unchecked Sendable {
    private let lock = NSLock()
    private var diagnostics = HypeTalkExecutionDiagnostics()

    public init() {}

    public func recordHandlerInvocation(_ name: String) {
        lock.withLock {
            diagnostics.handlerInvocations += 1
        }
    }

    public func recordStatement(_ kind: String) {
        lock.withLock {
            diagnostics.statements += 1
            diagnostics.statementKinds[kind, default: 0] += 1
        }
    }

    public func recordExpression(_ kind: String) {
        lock.withLock {
            diagnostics.expressions += 1
            diagnostics.expressionKinds[kind, default: 0] += 1
        }
    }

    public func recordPropertyRead(_ property: String) {
        let key = property.lowercased()
        lock.withLock {
            diagnostics.propertyReads += 1
            diagnostics.propertyReadKinds[key, default: 0] += 1
        }
    }

    public func recordPropertyWrite(_ property: String) {
        let key = property.lowercased()
        lock.withLock {
            diagnostics.propertyWrites += 1
            diagnostics.propertyWriteKinds[key, default: 0] += 1
        }
    }

    public func recordLoopIteration(_ kind: String) {
        lock.withLock {
            diagnostics.loopIterations += 1
            diagnostics.statementKinds["\(kind).iteration", default: 0] += 1
        }
    }

    public func recordCallbackRequest(_ kind: String) {
        lock.withLock {
            diagnostics.callbackRequests += 1
            diagnostics.callbackKinds[kind, default: 0] += 1
        }
    }

    public func snapshot() -> HypeTalkExecutionDiagnostics {
        lock.withLock { diagnostics }
    }
}
