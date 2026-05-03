// swift /Users/mweingar/dev/hype-v2/scripts/ai-training/src/eval_apple.swift \
//   <prompts.jsonl> <system-prompt-file> <output.json>
//
// Tiny CLI that runs the HypeTalk eval suite against Apple's
// system Foundation Model. Reads NDJSON prompts from arg 1, the
// system prompt text from arg 2, writes a JSON report to arg 3.
//
// On macOS 26+, the Foundation Models framework exposes Apple's
// on-device 3B-parameter language model via `LanguageModelSession`.
// Each prompt creates a fresh session so context doesn't bleed
// between rows (matching how Ollama / mlx-lm `generate` calls run).

import Foundation
#if canImport(FoundationModels)
import FoundationModels

struct PromptRow: Codable {
    let id: String
    let prompt: String
    let must_contain: [String]?
    let must_not_contain: [String]?
    let category: String?
}

struct ScoreResult: Codable {
    let id: String
    let passed: Bool
    let missing_required: [String]
    let present_forbidden: [String]
    let output_chars: Int
    let seconds: Double
    let output: String
}

struct Report: Codable {
    let model: String
    let prompts_file: String
    let elapsed_seconds: Double
    let pass_count: Int
    let total: Int
    let pass_pct: Double
    let results: [ScoreResult]
}

func score(_ prompt: PromptRow, output: String, seconds: Double) -> ScoreResult {
    let lower = output.lowercased()
    let missing = (prompt.must_contain ?? []).filter { !lower.contains($0.lowercased()) }
    let forbidden = (prompt.must_not_contain ?? []).filter { lower.contains($0.lowercased()) }
    let passed = missing.isEmpty && forbidden.isEmpty
    return ScoreResult(
        id: prompt.id,
        passed: passed,
        missing_required: missing,
        present_forbidden: forbidden,
        output_chars: output.count,
        seconds: seconds,
        output: String(output.prefix(600))
    )
}

@available(macOS 26.0, *)
func runOne(prompt: PromptRow, system: String) async -> (output: String, seconds: Double) {
    let t0 = Date()
    do {
        let session = LanguageModelSession(instructions: system)
        let response = try await session.respond(to: prompt.prompt)
        let secs = Date().timeIntervalSince(t0)
        return (response.content, secs)
    } catch {
        let secs = Date().timeIntervalSince(t0)
        return ("<FoundationModels error: \(error)>", secs)
    }
}

@available(macOS 26.0, *)
@main
struct EvalApple {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count >= 4 else {
            FileHandle.standardError.write(Data(
                "usage: eval_apple <prompts.jsonl> <system-prompt-file> <output.json>\n".utf8
            ))
            exit(2)
        }
        let promptsPath = args[1]
        let systemPath = args[2]
        let outputPath = args[3]

        guard let promptsData = try? String(contentsOfFile: promptsPath, encoding: .utf8) else {
            print("Failed to read prompts: \(promptsPath)")
            exit(1)
        }
        let systemPrompt = (try? String(contentsOfFile: systemPath, encoding: .utf8)) ?? ""

        let dec = JSONDecoder()
        var prompts: [PromptRow] = []
        for line in promptsData.split(separator: "\n") where !line.isEmpty {
            guard let lineData = line.data(using: .utf8) else { continue }
            if let row = try? dec.decode(PromptRow.self, from: lineData) {
                prompts.append(row)
            }
        }

        // Availability check.
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            print("[apple] model: \(model)")
        default:
            print("[apple] model not available: \(model.availability)")
            exit(1)
        }

        print("[apple] running \(prompts.count) prompts against Apple Foundation Models")

        var results: [ScoreResult] = []
        let t_start = Date()
        for (i, row) in prompts.enumerated() {
            let (output, secs) = await runOne(prompt: row, system: systemPrompt)
            let result = score(row, output: output, seconds: secs)
            let flag = result.passed ? "✓" : "✗"
            print(String(format: "  [%2d/%d] %@ %@ (%.1fs)",
                         i + 1, prompts.count, flag, row.id, secs))
            results.append(result)
        }
        let elapsed = Date().timeIntervalSince(t_start)
        let passCount = results.filter { $0.passed }.count
        let passPct = prompts.isEmpty ? 0.0 : Double(passCount) / Double(prompts.count) * 100

        print(String(format: "\n[apple] %d/%d (%.1f%%) in %.0fs",
                     passCount, prompts.count, passPct, elapsed))

        let report = Report(
            model: "apple-foundation-models",
            prompts_file: promptsPath,
            elapsed_seconds: round(elapsed * 10) / 10,
            pass_count: passCount,
            total: prompts.count,
            pass_pct: round(passPct * 10) / 10,
            results: results
        )

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(report) {
            try? data.write(to: URL(fileURLWithPath: outputPath))
            print("[apple] report written to \(outputPath)")
        }
    }
}

#else
@main
struct EvalApple {
    static func main() {
        print("FoundationModels framework not available on this OS")
        exit(1)
    }
}
#endif
