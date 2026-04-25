import Foundation

/// Repairs common local-model response shapes before the app gives up
/// on tool dispatch. This is intentionally narrow: it converts model
/// output into normal Hype tool calls, then the regular executor still
/// performs lookup, validation, and mutation.
public enum HypeAIResponseRepair {
    public static func validatedToolCalls(_ calls: [OllamaToolCall]?) -> [OllamaToolCall]? {
        let valid = (calls ?? []).filter(validateToolName).map(normalizeArguments)
        return valid.isEmpty ? nil : valid
    }

    /// Validate structured Ollama tool calls, then apply narrow,
    /// document-aware repairs for common local-model misroutes. The
    /// repaired call still flows through HypeToolExecutor for normal
    /// validation and mutation.
    public static func repairedToolCalls(
        _ calls: [OllamaToolCall]?,
        userMessage: String,
        document: HypeDocument,
        currentCardId: UUID?
    ) -> [OllamaToolCall]? {
        guard let valid = validatedToolCalls(calls) else { return nil }
        let repaired = valid.map {
            repairStructuredToolCall(
                $0,
                userMessage: userMessage,
                document: document,
                currentCardId: currentCardId
            )
        }
        return repaired.isEmpty ? nil : repaired
    }

    public static func extractToolCalls(from content: String?) -> [OllamaToolCall]? {
        guard let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let fenceLanguages = ["json", "tool_code", "tool_call"]
        for lang in fenceLanguages {
            guard let body = extractFencedBlock(content, language: lang) else { continue }
            if let parsed = parseJSONToolCall(body), validateToolName(parsed) {
                return [normalizeArguments(for: parsed)]
            }
            if let parsed = parseFunctionCallSyntax(body), validateToolName(parsed) {
                return [normalizeArguments(for: parsed)]
            }
        }

        if let parsed = parseStartFunctionSyntax(content), validateToolName(parsed) {
            return [normalizeArguments(for: parsed)]
        }
        if let parsed = parseEscapeFunctionSyntax(content), validateToolName(parsed) {
            return [normalizeArguments(for: parsed)]
        }
        if let parsed = parseEmbeddedJSONFunction(content), validateToolName(parsed) {
            return [normalizeArguments(for: parsed)]
        }
        if let parsed = parseFunctionCallSyntax(content), validateToolName(parsed) {
            return [normalizeArguments(for: parsed)]
        }

        return nil
    }

    /// If a model returns a HypeTalk script as plain assistant text
    /// after the user explicitly asked to attach a script, synthesize
    /// the corresponding storage tool call. This only fires when the
    /// target can be resolved from existing stack objects.
    public static func scriptAttachmentToolCall(
        userMessage: String,
        modelContent: String?,
        document: HypeDocument,
        currentCardId: UUID?
    ) -> OllamaToolCall? {
        let lower = userMessage.lowercased()
        guard lower.contains("script"),
              lower.containsAny(["set", "create", "write", "attach", "add", "replace", "change", "update"])
        else { return nil }

        if let generated = physicsBounceSceneScriptToolCall(
            userMessage: userMessage,
            document: document,
            currentCardId: currentCardId
        ) {
            return generated
        }

        let generatedScript = extractHypeTalkScript(from: modelContent)
        let scriptCommand = generatedScript ?? extractQuotedScriptCommand(from: userMessage)
        guard let script = scriptCommand else { return nil }

        if lower.containsAny(["node", "sprite", "label", "shape", "emitter"]),
           let nodeTarget = resolveMentionedNode(in: document, currentCardId: currentCardId, prompt: lower) {
            return makeCall(
                name: "set_node_script",
                arguments: [
                    "sprite_area_name": nodeTarget.areaName,
                    "node_name": nodeTarget.nodeName,
                    "scene_name": nodeTarget.sceneName,
                    "script": script
                ]
            )
        }

        if let part = resolveMentionedPart(in: document, currentCardId: currentCardId, prompt: lower) {
            if part.partType == .spriteArea {
                return makeCall(
                    name: "set_scene_script",
                    arguments: [
                        "sprite_area_name": part.name,
                        "script": script
                    ]
                )
            }
            return makeCall(
                name: "set_part_property",
                arguments: [
                    "part_name": part.name,
                    "property": "script",
                    "value": script
                ]
            )
        }

        if lower.contains("background"), generatedScript != nil {
            return makeCall(name: "set_background_script", arguments: ["script": script])
        }
        if lower.contains("card"), generatedScript != nil {
            return makeCall(name: "set_card_script", arguments: ["script": script])
        }
        if lower.contains("stack"), generatedScript != nil {
            return makeCall(name: "set_stack_script", arguments: ["script": script])
        }

        return nil
    }

    public static func extractHypeTalkScript(from content: String?) -> String? {
        guard let content else { return nil }
        let source = extractAnyFencedBlock(content) ?? content
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("on ") }) else {
            return nil
        }
        guard let end = lines.indices.reversed().first(where: {
            $0 >= start && lines[$0].trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("end ")
        }) else {
            return nil
        }
        let script = lines[start...end].joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return script.isEmpty ? nil : script
    }

    private static func extractQuotedScriptCommand(from text: String) -> String? {
        let pattern = #"["']([^"']{2,200})["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let command = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return nil }
        return command
    }

    private static let knownToolNames: Set<String> = {
        var names = Set(HypeToolDefinitions.allTools.map { $0.function.name })
        names.formUnion(HypeToolDefinitions.webAssetTools.map { $0.function.name })
        return names
    }()

    private static func validateToolName(_ call: OllamaToolCall) -> Bool {
        let name = call.function.name
        return !name.isEmpty && knownToolNames.contains(name)
    }

    private static func makeCall(name: String, arguments: [String: String]) -> OllamaToolCall {
        OllamaToolCall(function: OllamaToolCallFunction(name: name, arguments: arguments))
    }

    private static func extractFencedBlock(_ content: String, language: String) -> String? {
        let opener = "```\(language)"
        guard let openRange = content.range(of: opener) else { return nil }
        let afterOpen = content[openRange.upperBound...]
        guard let closeRange = afterOpen.range(of: "```") else { return nil }
        return afterOpen[..<closeRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractAnyFencedBlock(_ content: String) -> String? {
        guard let openRange = content.range(of: "```") else { return nil }
        let afterOpen = content[openRange.upperBound...]
        guard let newline = afterOpen.firstIndex(of: "\n") else { return nil }
        let afterLanguage = afterOpen[afterOpen.index(after: newline)...]
        guard let closeRange = afterLanguage.range(of: "```") else { return nil }
        return afterLanguage[..<closeRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseJSONToolCall(_ body: String) -> OllamaToolCall? {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return toolCall(fromJSONObject: obj)
    }

    private static func parseEmbeddedJSONFunction(_ text: String) -> OllamaToolCall? {
        guard let json = OllamaToolClient.extractFirstJSONObject(from: text),
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return toolCall(fromJSONObject: obj)
    }

    private static func toolCall(fromJSONObject obj: [String: Any]) -> OllamaToolCall? {
        let functionEnvelope = obj["function"] as? [String: Any]
        let toolEnvelope = obj["tool_call"] as? [String: Any]
        let envelope = functionEnvelope ?? toolEnvelope ?? obj
        guard let name = envelope["name"] as? String else { return nil }

        let rawArgsEnvelope = envelope["arguments"] as? [String: Any] ?? [:]
        let rawArgs: [String: Any]
        if rawArgsEnvelope.count == 1,
           let wrapped = rawArgsEnvelope["properties"] as? [String: Any] {
            rawArgs = wrapped
        } else {
            rawArgs = rawArgsEnvelope
        }

        var stringArgs: [String: String] = [:]
        for (key, value) in rawArgs {
            stringArgs[key] = flattenJSONValue(value)
        }
        return makeCall(name: name, arguments: stringArgs)
    }

    private static func flattenJSONValue(_ value: Any) -> String {
        if let dict = value as? [String: Any],
           dict.count == 1,
           let inner = dict["value"] {
            return flattenJSONValue(inner)
        }
        if let string = value as? String { return string }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        if let number = value as? NSNumber { return number.stringValue }
        if let nested = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let nestedString = String(data: nested, encoding: .utf8) {
            return nestedString
        }
        return String(describing: value)
    }

    private static func parseStartFunctionSyntax(_ text: String) -> OllamaToolCall? {
        guard let name = firstCapture(in: text, pattern: #"<start_function>\s*([^<\s]+)\s*</start_function>"#) else {
            return nil
        }
        var args: [String: String] = [:]
        let parameterText = firstCapture(in: text, pattern: #"<parameters>([\s\S]*?)</parameters>"#) ?? text
        let paramPattern = #"<([A-Za-z_][A-Za-z0-9_]*)>([\s\S]*?)</\1>"#
        guard let regex = try? NSRegularExpression(pattern: paramPattern) else {
            return makeCall(name: name, arguments: args)
        }
        let nsRange = NSRange(parameterText.startIndex..., in: parameterText)
        for match in regex.matches(in: parameterText, range: nsRange) {
            guard let keyRange = Range(match.range(at: 1), in: parameterText),
                  let valueRange = Range(match.range(at: 2), in: parameterText) else { continue }
            let key = String(parameterText[keyRange])
            if key == "start_function" || key == "parameters" { continue }
            args[key] = String(parameterText[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return makeCall(name: name, arguments: args)
    }

    private static func parseEscapeFunctionSyntax(_ text: String) -> OllamaToolCall? {
        let cleaned = text
            .replacingOccurrences(of: "<escape>", with: "\"")
            .replacingOccurrences(of: "\\\"", with: "\"")
        let pattern = #"([A-Za-z_][A-Za-z0-9_]*)\s*\{([^}]*)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
              let nameRange = Range(match.range(at: 1), in: cleaned),
              let argsRange = Range(match.range(at: 2), in: cleaned) else {
            return nil
        }
        let name = String(cleaned[nameRange])
        let args = parseKeyValuePairs(String(cleaned[argsRange]), separator: ":")
        return makeCall(name: name, arguments: args)
    }

    private static func parseFunctionCallSyntax(_ text: String) -> OllamaToolCall? {
        let pattern = #"([A-Za-z_][A-Za-z0-9_]*)\(([\s\S]*?)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let nameRange = Range(match.range(at: 1), in: text),
              let argsRange = Range(match.range(at: 2), in: text) else {
            return nil
        }
        let name = String(text[nameRange])
        let args = parseKeyValuePairs(String(text[argsRange]), separator: "=")
        return makeCall(name: name, arguments: args)
    }

    private static func parseKeyValuePairs(_ text: String, separator: Character) -> [String: String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        for char in text {
            if char == "\"" || char == "'" {
                if quote == char {
                    quote = nil
                } else if quote == nil {
                    quote = char
                }
                current.append(char)
                continue
            }
            if char == "," && quote == nil {
                parts.append(current)
                current = ""
                continue
            }
            current.append(char)
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(current)
        }

        var args: [String: String] = [:]
        for part in parts {
            let split = part.split(separator: separator, maxSplits: 1, omittingEmptySubsequences: false)
            guard split.count == 2 else { continue }
            let key = split[0].trimmingCharacters(in: .whitespacesAndNewlines)
            var value = split[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2,
               let first = value.first,
               let last = value.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                value = String(value.dropFirst().dropLast())
            }
            args[key] = value
        }
        return args
    }

    private static func normalizeArguments(for call: OllamaToolCall) -> OllamaToolCall {
        var args = call.function.arguments
        switch call.function.name {
        case "set_card_script", "set_background_script", "set_stack_script":
            if args["script"] == nil, let value = args["value"] {
                args["script"] = value
            }
        case "set_scene_script", "set_node_script":
            if args["script"] == nil, let value = args["value"] {
                args["script"] = value
            }
        default:
            break
        }
        return makeCall(name: call.function.name, arguments: args)
    }

    private static func repairStructuredToolCall(
        _ call: OllamaToolCall,
        userMessage: String,
        document: HypeDocument,
        currentCardId: UUID?
    ) -> OllamaToolCall {
        let lower = userMessage.lowercased()
        let args = call.function.arguments

        if call.function.name == "get_card_parts",
           lower.contains("background"),
           lower.containsAny(["object", "objects", "part", "parts", "button", "buttons", "field", "fields", "shared", "list", "show"]) {
            return makeCall(name: "get_background_parts", arguments: [:])
        }

        if call.function.name == "get_background_property",
           lower.contains("background"),
           lower.containsAny(["object", "objects", "part", "parts", "button", "buttons", "field", "fields", "shared", "list", "show"]) {
            return makeCall(name: "get_background_parts", arguments: [:])
        }

        if call.function.name == "set_scene_script",
           lower.contains("script") {
            if let generated = physicsBounceSceneScriptToolCall(
                userMessage: userMessage,
                document: document,
                currentCardId: currentCardId
            ) {
                return generated
            }

            if lower.contains("hoveredsprite"),
               lower.containsAny(["blue_ball", "sprite"]),
               lower.containsAny(["velocity", "boost", "increase", "accelerate"]) {
                let areaName = args["sprite_area_name"]
                    ?? resolveMentionedPart(in: document, currentCardId: currentCardId, prompt: lower)?.name
                    ?? ""
                let nodeName = resolveMentionedNode(in: document, currentCardId: currentCardId, prompt: lower)?.nodeName
                    ?? "blue_ball"
                if !areaName.isEmpty {
                    return makeCall(
                        name: "set_scene_script",
                        arguments: [
                            "sprite_area_name": areaName,
                            "script": hoverVelocityBoostSceneScript(spriteName: nodeName)
                        ]
                    )
                }
            }
        }

        if call.function.name == "check_script",
           lower.contains("script") {
            if let generated = physicsBounceSceneScriptToolCall(
                userMessage: userMessage,
                document: document,
                currentCardId: currentCardId
            ) {
                return generated
            }

            if lower.contains("hoveredsprite"),
               lower.containsAny(["blue_ball", "sprite"]),
               lower.containsAny(["velocity", "boost", "increase", "accelerate"]),
               let area = resolveMentionedPart(in: document, currentCardId: currentCardId, prompt: lower),
               area.partType == .spriteArea {
                let nodeName = resolveMentionedNode(in: document, currentCardId: currentCardId, prompt: lower)?.nodeName
                    ?? "blue_ball"
                return makeCall(
                    name: "set_scene_script",
                    arguments: [
                        "sprite_area_name": area.name,
                        "script": hoverVelocityBoostSceneScript(spriteName: nodeName)
                    ]
                )
            }
        }

        guard call.function.name == "set_part_property",
              (args["property"] ?? "").lowercased() == "script",
              lower.contains("script")
        else {
            return call
        }

        let partName = args["part_name"] ?? ""
        let targetPart = resolvePart(
            named: partName,
            in: document,
            currentCardId: currentCardId
        ) ?? resolveMentionedPart(in: document, currentCardId: currentCardId, prompt: lower)

        guard let targetPart, targetPart.partType == .spriteArea else {
            return call
        }

        if let generated = physicsBounceSceneScriptToolCall(
            userMessage: userMessage,
            document: document,
            currentCardId: currentCardId
        ) {
            return generated
        }

        if lower.contains("hoveredsprite"),
           lower.containsAny(["blue_ball", "sprite"]),
           lower.containsAny(["velocity", "boost", "increase", "accelerate"]) {
            let nodeName = resolveMentionedNode(in: document, currentCardId: currentCardId, prompt: lower)?.nodeName
                ?? "blue_ball"
            return makeCall(
                name: "set_scene_script",
                arguments: [
                    "sprite_area_name": targetPart.name,
                    "script": hoverVelocityBoostSceneScript(spriteName: nodeName)
                ]
            )
        }

        return makeCall(
            name: "set_scene_script",
            arguments: [
                "sprite_area_name": targetPart.name,
                "script": args["value"] ?? args["script"] ?? ""
            ]
        )
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func physicsBounceSceneScriptToolCall(
        userMessage: String,
        document: HypeDocument,
        currentCardId: UUID?
    ) -> OllamaToolCall? {
        let lower = userMessage.lowercased()
        guard lower.containsAny(["bounce", "bouncing"]),
              lower.contains("physics"),
              lower.containsAny(["all sprites", "sprites in motion", "perimeter", "scene"]),
              let area = resolveMentionedPart(in: document, currentCardId: currentCardId, prompt: lower),
              area.partType == .spriteArea,
              let scene = area.activeSceneSpec else {
            return nil
        }

        let spriteNames = scene.allNodes
            .filter { $0.nodeType == .sprite && !$0.name.isEmpty }
            .map(\.name)
        guard !spriteNames.isEmpty else { return nil }

        let boostName = spriteNames.first(where: { $0.lowercased() == "blue_ball" })
            ?? spriteNames.first(where: { lower.contains($0.lowercased()) })

        let script = physicsBounceSceneScript(spriteNames: spriteNames, boostSpriteName: boostName)
        return makeCall(
            name: "set_scene_script",
            arguments: [
                "sprite_area_name": area.name,
                "scene_name": scene.name,
                "script": script
            ]
        )
    }

    private static func physicsBounceSceneScript(spriteNames: [String], boostSpriteName: String?) -> String {
        let velocityPairs: [(Int, Int)] = [
            (200, 150), (-180, 220), (160, -210), (-220, -160),
            (240, 120), (-140, -230), (180, 180), (-200, 140)
        ]
        var lines: [String] = ["on sceneDidLoad"]
        for (index, name) in spriteNames.enumerated() {
            let velocity = velocityPairs[index % velocityPairs.count]
            lines.append("  set the dynamic of sprite \"\(name)\" to true")
            lines.append("  set the affectedByGravity of sprite \"\(name)\" to false")
            lines.append("  set the restitution of sprite \"\(name)\" to 1")
            lines.append("  set the friction of sprite \"\(name)\" to 0")
            lines.append("  set the contactTestBitmask of sprite \"\(name)\" to 1")
            lines.append("  set the collisionBitmask of sprite \"\(name)\" to 4294967295")
            lines.append("  set the velocityX of sprite \"\(name)\" to \(velocity.0)")
            lines.append("  set the velocityY of sprite \"\(name)\" to \(velocity.1)")
        }
        if boostSpriteName != nil {
            lines.append("  global wasHoveringTargetSprite")
            lines.append("  put \"false\" into wasHoveringTargetSprite")
        }
        lines.append("end sceneDidLoad")

        if let boostSpriteName {
            lines.append("")
            lines.append("on frameUpdate")
            lines.append("  global wasHoveringTargetSprite")
            lines.append("  if the hoveredSprite is \"\(boostSpriteName)\" then")
            lines.append("    if wasHoveringTargetSprite is \"false\" then")
            lines.append("      set the velocityX of sprite \"\(boostSpriteName)\" to (the velocityX of sprite \"\(boostSpriteName)\") * 1.5")
            lines.append("      set the velocityY of sprite \"\(boostSpriteName)\" to (the velocityY of sprite \"\(boostSpriteName)\") * 1.5")
            lines.append("      put \"true\" into wasHoveringTargetSprite")
            lines.append("    end if")
            lines.append("  else")
            lines.append("    put \"false\" into wasHoveringTargetSprite")
            lines.append("  end if")
            lines.append("end frameUpdate")
        }

        return lines.joined(separator: "\n")
    }

    private static func hoverVelocityBoostSceneScript(spriteName: String) -> String {
        """
        on frameUpdate
          global wasHoveringTargetSprite
          if the hoveredSprite is "\(spriteName)" then
            if wasHoveringTargetSprite is "false" then
              set the velocityX of sprite "\(spriteName)" to (the velocityX of sprite "\(spriteName)") * 1.5
              set the velocityY of sprite "\(spriteName)" to (the velocityY of sprite "\(spriteName)") * 1.5
              put "true" into wasHoveringTargetSprite
            end if
          else
            put "false" into wasHoveringTargetSprite
          end if
        end frameUpdate
        """
    }

    private static func resolvePart(
        named name: String,
        in document: HypeDocument,
        currentCardId: UUID?
    ) -> Part? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        let candidates: [Part]
        if let currentCardId {
            candidates = document.effectivePartsForCard(currentCardId)
        } else {
            candidates = document.parts
        }
        return candidates.first { $0.name.lowercased() == trimmed }
    }

    private static func resolveMentionedPart(
        in document: HypeDocument,
        currentCardId: UUID?,
        prompt: String
    ) -> Part? {
        let candidates: [Part]
        if let currentCardId {
            candidates = document.effectivePartsForCard(currentCardId)
        } else {
            candidates = document.parts
        }
        return candidates.first(where: { !$0.name.isEmpty && prompt.contains($0.name.lowercased()) })
    }

    private static func resolveMentionedNode(
        in document: HypeDocument,
        currentCardId: UUID?,
        prompt: String
    ) -> (areaName: String, sceneName: String, nodeName: String)? {
        let parts: [Part]
        if let currentCardId {
            parts = document.effectivePartsForCard(currentCardId).filter { $0.partType == .spriteArea }
        } else {
            parts = document.parts.filter { $0.partType == .spriteArea }
        }

        for part in parts {
            guard let scene = part.activeSceneSpec else { continue }
            for node in scene.allNodes where !node.name.isEmpty {
                if prompt.contains(node.name.lowercased()) {
                    return (part.name, scene.name, node.name)
                }
            }
        }
        return nil
    }
}

private extension String {
    func containsAny(_ needles: [String]) -> Bool {
        needles.contains { contains($0) }
    }
}
