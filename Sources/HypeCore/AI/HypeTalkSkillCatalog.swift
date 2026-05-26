import Foundation

public enum HypeTalkSkillID: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case messageHierarchy = "message_hierarchy"
    case handlerPlacement = "handler_placement"
    case customHandlers = "custom_handlers"
    case targetMeItResult = "target_me_it_result"
    case loopsAndChunks = "loops_and_chunks"
    case layoutScripting = "layout_scripting"
    case spriteSceneScripting = "sprite_scene_scripting"
    case debuggingFlow = "debugging_flow"
    case styleReuseReadability = "style_reuse_readability"

    public var id: String { rawValue }
}

public struct HypeTalkSkillDescriptor: Codable, Sendable, Equatable, Identifiable {
    public var id: HypeTalkSkillID
    public var title: String
    public var summary: String
    public var triggers: [String]
    public var supportedScopes: [String]
    public var relatedTools: [String]
    public var sourceURL: String

    public init(
        id: HypeTalkSkillID,
        title: String,
        summary: String,
        triggers: [String],
        supportedScopes: [String],
        relatedTools: [String],
        sourceURL: String = HypeTalkSkillCatalog.jaedworksScriptingURL
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.triggers = triggers
        self.supportedScopes = supportedScopes
        self.relatedTools = relatedTools
        self.sourceURL = sourceURL
    }
}

public struct HypeTalkPattern: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var skillID: HypeTalkSkillID
    public var title: String
    public var summary: String
    public var script: String
    public var notes: [String]

    public init(
        id: String,
        skillID: HypeTalkSkillID,
        title: String,
        summary: String,
        script: String,
        notes: [String]
    ) {
        self.id = id
        self.skillID = skillID
        self.title = title
        self.summary = summary
        self.script = script
        self.notes = notes
    }
}

public struct HypeTalkSkillCatalog: Sendable {
    public static let jaedworksScriptingURL = "http://www.jaedworks.com/hypercard/HT-Masters/scripting.html"

    public static let descriptors: [HypeTalkSkillDescriptor] = [
        HypeTalkSkillDescriptor(
            id: .messageHierarchy,
            title: "Message Hierarchy",
            summary: "Choose scripts and pass behavior using Hype's part -> card -> background -> stack -> app message path.",
            triggers: ["message path", "pass mouseUp", "event bubbling", "why did handler fire", "send to stack"],
            supportedScopes: ["part", "card", "background", "stack", "spriteArea", "scene", "node"],
            relatedTools: ["inspect_message_path", "get_card_script", "get_background_script", "get_stack_script", "check_script"]
        ),
        HypeTalkSkillDescriptor(
            id: .handlerPlacement,
            title: "Handler Placement",
            summary: "Decide whether behavior belongs on a control, card, background, stack, scene, or node.",
            triggers: ["where should script go", "button script", "card script", "background script", "shared behavior"],
            supportedScopes: ["part", "card", "background", "stack", "spriteArea", "scene", "node"],
            relatedTools: ["suggest_handler_location", "get_card_parts", "get_background_parts", "list_all_properties"]
        ),
        HypeTalkSkillDescriptor(
            id: .customHandlers,
            title: "Custom Handlers",
            summary: "Factor repeated behavior into named handlers and call them with send instead of duplicating scripts.",
            triggers: ["reuse", "many buttons", "shared action", "subroutine", "send custom handler"],
            supportedScopes: ["card", "background", "stack", "scene"],
            relatedTools: ["plan_hypetalk_script", "get_hypetalk_pattern", "set_stack_script", "check_script"]
        ),
        HypeTalkSkillDescriptor(
            id: .targetMeItResult,
            title: "me, target, it, and result",
            summary: "Use HypeTalk's context values correctly while avoiding ambiguous object references.",
            triggers: ["me", "target", "it", "result", "clicked object", "current object"],
            supportedScopes: ["part", "card", "background", "stack", "scene", "node"],
            relatedTools: ["inspect_message_path", "get_hypetalk_pattern", "review_hypetalk_script"]
        ),
        HypeTalkSkillDescriptor(
            id: .loopsAndChunks,
            title: "Loops and Chunks",
            summary: "Use repeat loops, lines, items, words, and chars for clear data and text manipulation.",
            triggers: ["repeat", "loop", "line", "item", "word", "chunk", "list data"],
            supportedScopes: ["part", "card", "background", "stack"],
            relatedTools: ["get_hypetalk_pattern", "check_script", "review_hypetalk_script"]
        ),
        HypeTalkSkillDescriptor(
            id: .layoutScripting,
            title: "Layout Scripting",
            summary: "Read and set stack/card/background/control properties with Hype tools before writing layout scripts.",
            triggers: ["layout", "position", "property", "resize", "align", "target platform"],
            supportedScopes: ["stack", "card", "background", "part"],
            relatedTools: ["get_card_parts", "list_all_properties", "preview_layout_profile", "set_part_property"]
        ),
        HypeTalkSkillDescriptor(
            id: .spriteSceneScripting,
            title: "Sprite Scene Scripting",
            summary: "Use scene/node tools and supported scene handlers instead of generic card-control scripts for SpriteKit behavior.",
            triggers: ["sprite", "scene", "physics", "collision", "keyDown", "frameUpdate", "beginContact"],
            supportedScopes: ["spriteArea", "scene", "node"],
            relatedTools: ["get_scene_spec", "list_scene_nodes", "get_node_property", "set_scene_script", "set_node_script"]
        ),
        HypeTalkSkillDescriptor(
            id: .debuggingFlow,
            title: "Debugging Flow",
            summary: "Narrow script problems with validation, state inspection, diagnostic messages, and small behavior tests.",
            triggers: ["debug", "error", "not firing", "does nothing", "runtime error", "script failed"],
            supportedScopes: ["part", "card", "background", "stack", "scene", "node"],
            relatedTools: ["check_script", "review_hypetalk_script", "get_part_property", "get_scene_diagnostics", "capture_card_image"]
        ),
        HypeTalkSkillDescriptor(
            id: .styleReuseReadability,
            title: "Style, Reuse, and Readability",
            summary: "Prefer readable names, reusable handlers, comments for non-obvious logic, and no duplicated object scripts.",
            triggers: ["clean up script", "refactor", "readability", "maintainable", "duplicate"],
            supportedScopes: ["part", "card", "background", "stack", "scene"],
            relatedTools: ["review_hypetalk_script", "get_hypetalk_pattern", "check_script"]
        ),
    ]

    public static let patterns: [HypeTalkPattern] = [
        HypeTalkPattern(
            id: "button_delegates_to_stack",
            skillID: .customHandlers,
            title: "Button delegates to a stack handler",
            summary: "Keep the button tiny and put reusable behavior in the stack script.",
            script: """
            on mouseUp
              send "doPrimaryAction" to this stack
            end mouseUp
            """,
            notes: ["Attach this to the button.", "Add `on doPrimaryAction ... end doPrimaryAction` to the stack script."]
        ),
        HypeTalkPattern(
            id: "shared_stack_handler",
            skillID: .customHandlers,
            title: "Reusable stack-level handler",
            summary: "One central handler can serve many buttons or cards.",
            script: """
            on doPrimaryAction
              answer "Ready."
            end doPrimaryAction
            """,
            notes: ["Store this on the stack when many controls should share the same action."]
        ),
        HypeTalkPattern(
            id: "pass_mouse_up",
            skillID: .messageHierarchy,
            title: "Handle locally, then pass upward",
            summary: "Do local work while allowing card/background/stack behavior to continue.",
            script: """
            on mouseUp
              answer "Handled locally."
              pass mouseUp
            end mouseUp
            """,
            notes: ["Use `pass <message>` when higher-level handlers should still run."]
        ),
        HypeTalkPattern(
            id: "card_open_setup",
            skillID: .handlerPlacement,
            title: "Card setup on openCard",
            summary: "Initialize visible card state when the user enters a card.",
            script: """
            on openCard
              put empty into field "Status"
              pass openCard
            end openCard
            """,
            notes: ["Attach to the card script.", "Ensure the field exists before storing this script."]
        ),
        HypeTalkPattern(
            id: "form_validation_button",
            skillID: .debuggingFlow,
            title: "Validate required field before saving",
            summary: "Exit early only for the exceptional path, then continue normal work.",
            script: """
            on mouseUp
              if field "Name" is empty then
                answer "Enter a name."
                exit mouseUp
              end if
              put "Saved" into field "Status"
            end mouseUp
            """,
            notes: ["Attach to a Save button.", "Create fields named `Name` and `Status` first."]
        ),
        HypeTalkPattern(
            id: "debug_trace",
            skillID: .debuggingFlow,
            title: "Trace a handler path",
            summary: "Use a visible diagnostic while narrowing whether a handler fires.",
            script: """
            on mouseUp
              answer "mouseUp reached"
            end mouseUp
            """,
            notes: ["Remove or replace diagnostics after confirming the route."]
        ),
    ]

    public init() {}

    public static func descriptor(for rawID: String) -> HypeTalkSkillDescriptor? {
        let normalized = normalize(rawID)
        return descriptors.first { descriptor in
            normalize(descriptor.id.rawValue) == normalized
                || normalize(descriptor.title) == normalized
                || descriptor.triggers.contains { normalize($0) == normalized }
        }
    }

    public static func pattern(for rawID: String) -> HypeTalkPattern? {
        let normalized = normalize(rawID)
        return patterns.first { normalize($0.id) == normalized || normalize($0.title) == normalized }
    }

    public static func descriptors(matching query: String?) -> [HypeTalkSkillDescriptor] {
        guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return descriptors
        }
        let terms = normalize(query).split(separator: " ").map(String.init)
        return descriptors.filter { descriptor in
            let haystack = normalize([
                descriptor.id.rawValue,
                descriptor.title,
                descriptor.summary,
                descriptor.triggers.joined(separator: " "),
                descriptor.supportedScopes.joined(separator: " "),
            ].joined(separator: " "))
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    public static func compactSkillList(query: String? = nil) -> String {
        descriptors(matching: query).map { descriptor in
            "- \(descriptor.id.rawValue): \(descriptor.summary) Triggers: \(descriptor.triggers.prefix(4).joined(separator: ", "))."
        }.joined(separator: "\n")
    }

    public static func guide(for rawID: String, detailLevel: String = "summary", intent: String = "") -> String {
        guard let descriptor = descriptor(for: rawID) else {
            return "Unknown HypeTalk skill '\(rawID)'. Use list_hypetalk_skills to discover valid skill_id values."
        }
        let level = normalize(detailLevel)
        var lines: [String] = [
            "\(descriptor.title) (\(descriptor.id.rawValue))",
            "Source basis: \(descriptor.sourceURL)",
            "Hype compatibility: this is curated guidance adapted to HypeTalk and must be checked with Hype tools, not copied as raw HyperCard behavior.",
            "Use when: \(descriptor.triggers.joined(separator: ", ")).",
            "Related tools: \(descriptor.relatedTools.joined(separator: ", ")).",
        ]
        if !intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Current intent: \(intent)")
        }
        lines.append(contentsOf: guidanceBullets(for: descriptor.id))
        if level.contains("pattern") || level.contains("full") || level.contains("example") {
            let matching = patterns.filter { $0.skillID == descriptor.id }
            if !matching.isEmpty {
                lines.append("Patterns:")
                lines.append(contentsOf: matching.map { "- \($0.id): \($0.summary)" })
            }
        }
        if level.contains("check") || level.contains("full") || level.contains("review") {
            lines.append("Checklist: introspect live state first; choose the lowest reusable script scope; validate with check_script; review with review_hypetalk_script; attach only after validation passes; re-read the stored script.")
        }
        return lines.joined(separator: "\n")
    }

    public static func patternGuide(patternID: String?, skillID: String?) -> String {
        if let patternID, !patternID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let pattern = pattern(for: patternID) else {
                return "Unknown HypeTalk pattern '\(patternID)'. Call get_hypetalk_pattern with a skill_id to list available patterns."
            }
            return format(pattern)
        }
        let matching: [HypeTalkPattern]
        if let skillID, !skillID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let descriptor = descriptor(for: skillID) {
            matching = patterns.filter { $0.skillID == descriptor.id }
        } else {
            matching = patterns
        }
        guard !matching.isEmpty else { return "No HypeTalk patterns matched the requested skill." }
        return matching.map { "- \($0.id): \($0.title) — \($0.summary)" }.joined(separator: "\n")
    }

    public static func planningGuide(intent: String, targetScope: String, targetName: String, eventName: String) -> String {
        let lowerIntent = intent.lowercased()
        let scope = targetScope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "part" : targetScope
        let event = eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? inferredEvent(for: lowerIntent) : eventName
        let skillIDs = recommendedSkills(for: lowerIntent, scope: scope)
        var lines: [String] = [
            "HypeTalk script plan",
            "Intent: \(intent.isEmpty ? "(not supplied)" : intent)",
            "Recommended target scope: \(suggestedScope(intent: lowerIntent, suppliedScope: scope))",
            "Target name: \(targetName.isEmpty ? "(use current target)" : targetName)",
            "Primary event/handler: \(event)",
            "Skills to consult: \(skillIDs.map(\.rawValue).joined(separator: ", "))",
            "Tool sequence:",
            "1. Inspect current objects/scripts with get_card_parts, get_background_parts, list_all_properties, and get_*_script as needed.",
            "2. Call get_hypetalk_skill_guide for the most relevant skill before drafting.",
            "3. Generate full handler blocks with supported HypeTalk syntax.",
            "4. Call check_script until it returns OK.",
            "5. Call review_hypetalk_script with the original intent and expected target scope.",
            "6. Store the script with set_part_property, set_card_script, set_background_script, set_stack_script, set_scene_script, or set_node_script.",
        ]
        if lowerIntent.contains("many") || lowerIntent.contains("shared") || lowerIntent.contains("reuse") {
            lines.append("Placement note: factor common behavior into a card/background/stack handler and keep individual control scripts as small send/pass delegates.")
        }
        if lowerIntent.contains("sprite") || lowerIntent.contains("scene") || lowerIntent.contains("physics") {
            lines.append("Scene note: use scene/node tools and supported scene handlers; do not implement SpriteKit behavior through ordinary card controls.")
        }
        return lines.joined(separator: "\n")
    }

    public static func handlerLocationGuide(intent: String, currentScope: String, targetName: String) -> String {
        let lowerIntent = intent.lowercased()
        let supplied = currentScope.trimmingCharacters(in: .whitespacesAndNewlines)
        let scope = suggestedScope(intent: lowerIntent, suppliedScope: supplied.isEmpty ? "part" : supplied)
        var reasons: [String] = []
        if lowerIntent.contains("every card") || lowerIntent.contains("whole stack") || lowerIntent.contains("shared") {
            reasons.append("shared behavior should live at stack or background scope instead of being duplicated on each control")
        }
        if lowerIntent.contains("enter") || lowerIntent.contains("open card") || lowerIntent.contains("when card") {
            reasons.append("card lifecycle behavior belongs on the card or shared background")
        }
        if lowerIntent.contains("click") || lowerIntent.contains("button") {
            reasons.append("control-specific click behavior can live on the part, but reusable work should be delegated")
        }
        if lowerIntent.contains("sprite") || lowerIntent.contains("physics") || lowerIntent.contains("collision") {
            reasons.append("SpriteKit behavior belongs on the scene or node script")
        }
        if reasons.isEmpty {
            reasons.append("choose the lowest scope that owns the behavior, then pass upward if higher-level behavior should continue")
        }
        return [
            "Suggested handler location: \(scope)",
            "Target: \(targetName.isEmpty ? "(current target)" : targetName)",
            "Reason: \(reasons.joined(separator: "; ")).",
            "Next tools: inspect_message_path, get_hypetalk_skill_guide(skill_id=handler_placement), check_script, review_hypetalk_script.",
        ].joined(separator: "\n")
    }

    public static func review(
        script: String,
        intent: String,
        targetScope: String,
        eventName: String,
        checkScriptResponse: String,
        passExpected: Bool
    ) -> String {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "FAIL: script is empty." }
        var warnings: [String] = []
        var suggestions: [String] = []
        if checkScriptResponse.hasPrefix("FAIL:") || checkScriptResponse.hasPrefix("EMPTY:") {
            return "FAIL: check_script did not pass.\n\(checkScriptResponse)"
        }
        let handlers = handlerNames(in: script)
        if handlers.isEmpty {
            warnings.append("No explicit handler block was found; storage tools may auto-wrap some one-liners, but full scripts should be explicit.")
        }
        let duplicateHandlers = Dictionary(grouping: handlers, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        if !duplicateHandlers.isEmpty {
            warnings.append("Duplicate handler name(s): \(duplicateHandlers.joined(separator: ", ")).")
        }
        let lowerScript = script.lowercased()
        let lowerIntent = intent.lowercased()
        let lowerScope = targetScope.lowercased()
        if passExpected && !lowerScript.contains("pass ") {
            warnings.append("passExpected=true but the script never passes the message upward.")
        }
        if lowerScript.contains("on domenu") && !lowerScript.contains("pass domenu") {
            warnings.append("A doMenu handler without pass doMenu can block normal menu behavior.")
        }
        if (lowerIntent.contains("shared") || lowerIntent.contains("many") || lowerIntent.contains("reuse")) && lowerScope == "part" {
            suggestions.append("Consider storing reusable work on the stack/background and using a tiny part script that sends the custom handler.")
        }
        if lowerIntent.contains("sprite") && !(lowerScope.contains("scene") || lowerScope.contains("node") || lowerScope.contains("sprite")) {
            warnings.append("Sprite-related intent is being reviewed for a non-scene scope; verify this should not use set_scene_script or set_node_script.")
        }
        if !eventName.isEmpty, !handlers.isEmpty, !handlers.contains(eventName.lowercased()) {
            warnings.append("Expected handler '\(eventName)' was not found. Found: \(handlers.joined(separator: ", ")).")
        }
        if lowerScript.contains("answer ") && lowerIntent.contains("silent") {
            warnings.append("The script uses answer dialogs even though the intent mentions silent/background behavior.")
        }
        suggestions.append("After storing, re-read the target script and use live interaction or capture_card_image when visual outcome matters.")
        let status = warnings.isEmpty ? "OK" : "WARN"
        return ([ "\(status): HypeTalk script review complete.", "check_script: \(checkScriptResponse)" ]
            + warnings.map { "Warning: \($0)" }
            + suggestions.map { "Suggestion: \($0)" }).joined(separator: "\n")
    }

    public static func handlerNames(in script: String) -> [String] {
        script
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                let lower = trimmed.lowercased()
                if lower.hasPrefix("on ") || lower.hasPrefix("function ") {
                    return lower.split(separator: " ").dropFirst().first.map(String.init)
                }
                return nil
            }
    }

    private static func format(_ pattern: HypeTalkPattern) -> String {
        """
        \(pattern.title) (\(pattern.id))
        Skill: \(pattern.skillID.rawValue)
        Summary: \(pattern.summary)
        Script:
        \(pattern.script)
        Notes:
        \(pattern.notes.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    private static func guidanceBullets(for id: HypeTalkSkillID) -> [String] {
        switch id {
        case .messageHierarchy:
            return [
                "Hype sends events through the owning object and then upward; use pass when higher-level behavior should still run.",
                "Use inspect_message_path before deciding whether a handler belongs on a part, card, background, or stack.",
            ]
        case .handlerPlacement:
            return [
                "Put behavior at the lowest scope that owns it; move shared behavior upward.",
                "Card lifecycle setup belongs in card/background scripts; reusable app-like behavior belongs in stack scripts.",
            ]
        case .customHandlers:
            return [
                "Use small object scripts that send named custom handlers to a central owner.",
                "Name handlers for intent, not UI labels, so they survive layout and object-name changes.",
            ]
        case .targetMeItResult:
            return [
                "`me` is the script owner; `the target` is the original receiver of the message.",
                "`it` is overwritten by commands such as answer/get; store it immediately if you need it later.",
            ]
        case .loopsAndChunks:
            return [
                "Use repeat loops for repeated fields, lines, items, or controls instead of duplicating commands.",
                "Chunks are best for text/list data; validate parser support before storing complex chunk manipulation.",
            ]
        case .layoutScripting:
            return [
                "Use tools for geometry/property reads and writes when possible; scripts should handle runtime behavior.",
                "Call preview_layout_profile before target-sensitive positioning or sizing decisions.",
            ]
        case .spriteSceneScripting:
            return [
                "Use SceneSpec-backed tools and scene/node scripts for SpriteKit behavior.",
                "Use supported handlers such as sceneDidLoad, keyDown, keyUp, frameUpdate, beginContact, and endContact.",
            ]
        case .debuggingFlow:
            return [
                "Validate syntax first, then inspect live state, then add temporary diagnostics only where needed.",
                "A script that parses can still fail at runtime if it references missing objects or the wrong scope.",
            ]
        case .styleReuseReadability:
            return [
                "Use readable names, short handlers, and comments for non-obvious logic.",
                "Avoid duplicated object scripts; extract repeated behavior into a custom handler.",
            ]
        }
    }

    private static func recommendedSkills(for lowerIntent: String, scope: String) -> [HypeTalkSkillID] {
        var result: [HypeTalkSkillID] = [.handlerPlacement, .messageHierarchy]
        if lowerIntent.contains("reuse") || lowerIntent.contains("shared") || lowerIntent.contains("many") {
            result.append(.customHandlers)
        }
        if lowerIntent.contains("sprite") || lowerIntent.contains("scene") || lowerIntent.contains("physics") {
            result.append(.spriteSceneScripting)
        }
        if lowerIntent.contains("layout") || lowerIntent.contains("position") || lowerIntent.contains("property") {
            result.append(.layoutScripting)
        }
        if lowerIntent.contains("debug") || lowerIntent.contains("error") || lowerIntent.contains("not ") {
            result.append(.debuggingFlow)
        }
        if scope.lowercased().contains("stack") {
            result.append(.styleReuseReadability)
        }
        var seen: Set<HypeTalkSkillID> = []
        return result.filter { seen.insert($0).inserted }
    }

    private static func suggestedScope(intent lowerIntent: String, suppliedScope: String) -> String {
        if lowerIntent.contains("sprite") || lowerIntent.contains("scene") || lowerIntent.contains("physics") || lowerIntent.contains("collision") {
            return lowerIntent.contains("node") ? "node" : "scene"
        }
        if lowerIntent.contains("every card") || lowerIntent.contains("whole stack") || lowerIntent.contains("global") || lowerIntent.contains("many buttons") {
            return "stack"
        }
        if lowerIntent.contains("all cards with this background") || lowerIntent.contains("shared background") {
            return "background"
        }
        if lowerIntent.contains("open card") || lowerIntent.contains("enter card") || lowerIntent.contains("when card") {
            return "card"
        }
        return suppliedScope
    }

    private static func inferredEvent(for lowerIntent: String) -> String {
        if lowerIntent.contains("open card") || lowerIntent.contains("enter card") { return "openCard" }
        if lowerIntent.contains("close card") || lowerIntent.contains("leave card") { return "closeCard" }
        if lowerIntent.contains("key") || lowerIntent.contains("wasd") { return "keyDown" }
        if lowerIntent.contains("collision") || lowerIntent.contains("contact") { return "beginContact" }
        if lowerIntent.contains("listen") || lowerIntent.contains("speech") { return "listen" }
        if lowerIntent.contains("idle") || lowerIntent.contains("every frame") { return "idle" }
        return "mouseUp"
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }
}
