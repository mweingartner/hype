import Foundation

public struct SpeakOptions: Sendable {
    public var voice: Expression?
    public var tone: Expression?
    public var pace: Expression?
    public var quality: Expression?
    public var output: Expression?
    public init() {}
    public var expressions: [Expression] { [voice, tone, pace, quality, output].compactMap { $0 } }
}
