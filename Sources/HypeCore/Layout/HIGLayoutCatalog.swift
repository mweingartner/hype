import Foundation

public struct HIGLayoutMetrics: Codable, Sendable, Equatable {
    public var profile: HypeDeviceProfile
    public var minimumHitWidth: Double
    public var minimumHitHeight: Double
    public var minimumTextSize: Double
    public var edgeMargin: Double
    public var defaultSpacing: Double
    public var unbezeledSpacing: Double
    public var gridUnit: Double
    public var prefersFocusSafeSpacing: Bool

    public init(
        profile: HypeDeviceProfile,
        minimumHitWidth: Double,
        minimumHitHeight: Double,
        minimumTextSize: Double,
        edgeMargin: Double,
        defaultSpacing: Double,
        unbezeledSpacing: Double,
        gridUnit: Double = 8,
        prefersFocusSafeSpacing: Bool = false
    ) {
        self.profile = profile
        self.minimumHitWidth = minimumHitWidth
        self.minimumHitHeight = minimumHitHeight
        self.minimumTextSize = minimumTextSize
        self.edgeMargin = edgeMargin
        self.defaultSpacing = defaultSpacing
        self.unbezeledSpacing = unbezeledSpacing
        self.gridUnit = gridUnit
        self.prefersFocusSafeSpacing = prefersFocusSafeSpacing
    }
}

public struct HIGLayoutIssue: Codable, Sendable, Equatable {
    public enum Severity: String, Codable, Sendable {
        case error
        case warning
    }

    public var severity: Severity
    public var profileId: String
    public var partName: String
    public var partType: PartType
    public var message: String

    public init(
        severity: Severity,
        profileId: String,
        partName: String,
        partType: PartType,
        message: String
    ) {
        self.severity = severity
        self.profileId = profileId
        self.partName = partName
        self.partType = partType
        self.message = message
    }
}

public enum HIGLayoutCatalog {
    public static let sourceReferences: [String] = [
        "https://developer.apple.com/design/human-interface-guidelines/layout",
        "https://developer.apple.com/documentation/uikit/positioning-content-relative-to-the-safe-area",
        "https://developer.apple.com/documentation/uikit/uiview/safearealayoutguide",
        "https://developer.apple.com/documentation/appkit/nsview/safearealayoutguide",
        "https://developer.apple.com/design/human-interface-guidelines/accessibility",
        "https://developer.apple.com/design/human-interface-guidelines/buttons",
        "https://developer.apple.com/design/human-interface-guidelines/focus-and-selection",
    ]

    public static func metrics(for profile: HypeDeviceProfile) -> HIGLayoutMetrics {
        switch profile.platform {
        case .macOS:
            return HIGLayoutMetrics(
                profile: profile,
                minimumHitWidth: 28,
                minimumHitHeight: 28,
                minimumTextSize: 13,
                edgeMargin: 20,
                defaultSpacing: 12,
                unbezeledSpacing: 24
            )
        case .iPhone, .iPad:
            return HIGLayoutMetrics(
                profile: profile,
                minimumHitWidth: 44,
                minimumHitHeight: 44,
                minimumTextSize: 17,
                edgeMargin: 20,
                defaultSpacing: 12,
                unbezeledSpacing: 24
            )
        case .tvOS:
            return HIGLayoutMetrics(
                profile: profile,
                minimumHitWidth: 66,
                minimumHitHeight: 66,
                minimumTextSize: 29,
                edgeMargin: 90,
                defaultSpacing: 24,
                unbezeledSpacing: 32,
                prefersFocusSafeSpacing: true
            )
        }
    }

    public static func guide(profile: HypeDeviceProfile, includeSources: Bool = true) -> String {
        let m = metrics(for: profile)
        var lines: [String] = [
            "HIG layout guide for \(profile.displayName) (\(profile.id))",
            "Platform: \(profile.platform.displayName), input=\(profile.inputModel.rawValue), canvas=\(profile.width)x\(profile.height), safeArea=\(format(profile.safeArea.top)),\(format(profile.safeArea.left)),\(format(profile.safeArea.bottom)),\(format(profile.safeArea.right))",
            "Minimum interactive hit target: \(format(m.minimumHitWidth))x\(format(m.minimumHitHeight)) pt.",
            "Minimum body text size: \(format(m.minimumTextSize)) pt.",
            "Default edge margin: \(format(m.edgeMargin)) pt. Default bezeled-control spacing: \(format(m.defaultSpacing)) pt. Unbezeled/focus spacing: \(format(m.unbezeledSpacing)) pt.",
            "Use safe-area layout, not raw screen edges, for ordinary controls. Full-bleed SpriteKit/game/media regions are allowed when intentional.",
            "For multi-target stacks, prefer layoutPolicy=scaleToFit plus explicit safe-area constraints, then validate every selected profile.",
        ]
        if profile.platform == .tvOS {
            lines.append("tvOS note: preserve larger focus targets, overscan-safe margins, and enough spacing for focus parallax.")
        }
        if includeSources {
            lines.append("Source basis: \(sourceReferences.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    public static func listConstraints(document: HypeDocument, currentCardId: UUID, partNames: [String] = []) -> String {
        let ids = Set(resolvePartIndices(document: document, currentCardId: currentCardId, partNames: partNames).map { document.parts[$0].id })
        let effectiveIds = Set(document.effectivePartsForCard(currentCardId).map(\.id))
        let constraints = document.constraints.filter { constraint in
            let inScope = effectiveIds.contains(constraint.sourcePartId)
            guard partNames.isEmpty else { return ids.contains(constraint.sourcePartId) }
            return inScope
        }
        guard !constraints.isEmpty else { return "No layout constraints on the requested current-card parts." }

        return constraints.map { c in
            let source = document.part(byId: c.sourcePartId)?.name ?? c.sourcePartId.uuidString
            let target: String
            if c.targetType == .canvas {
                target = "safe-area canvas"
            } else if let targetPartId = c.targetPartId {
                target = "part \"\(document.part(byId: targetPartId)?.name ?? targetPartId.uuidString)\""
            } else {
                target = "missing target"
            }
            return "- \(c.id.uuidString): \(source).\(c.sourceEdge.rawValue) -> \(target).\(c.targetEdge.rawValue), distance=\(format(c.distance))"
        }.joined(separator: "\n")
    }

    public static func validate(
        document: HypeDocument,
        currentCardId: UUID,
        profileIds: [String] = [],
        includeAllSelected: Bool = true,
        allowFullBleed: Bool = false
    ) -> String {
        let profiles = profilesForValidation(
            document: document,
            explicitProfileIds: profileIds,
            includeAllSelected: includeAllSelected
        )
        guard !profiles.isEmpty else { return "No target profiles matched. Call list_target_profiles first." }

        let parts = document.effectivePartsForCard(currentCardId).sorted { $0.sortKey < $1.sortKey }
        guard !parts.isEmpty else {
            return "OK: current card has no parts to validate. Profiles checked: \(profiles.map(\.id).joined(separator: ", "))."
        }

        var issues: [HIGLayoutIssue] = []
        for profile in profiles {
            issues.append(contentsOf: validate(parts: parts, document: document, currentCardId: currentCardId, profile: profile, allowFullBleed: allowFullBleed))
        }
        if issues.isEmpty {
            return "OK: HIG layout validation passed for \(profiles.map(\.id).joined(separator: ", ")). Checked safe areas, target availability, hit sizes, text sizes, and spacing."
        }

        let errors = issues.filter { $0.severity == .error }.count
        let warnings = issues.count - errors
        let body = issues.map { issue in
            "- \(issue.severity.rawValue.uppercased()) [\(issue.profileId)] \(issue.partType.rawValue) \"\(issue.partName)\": \(issue.message)"
        }.joined(separator: "\n")
        let status = errors > 0 ? "FAIL" : "WARN"
        return "\(status): HIG layout validation found \(errors) error(s) and \(warnings) warning(s).\n\(body)"
    }

    public static func addConstraint(
        document: inout HypeDocument,
        currentCardId: UUID,
        sourcePartName: String,
        sourceEdge: String,
        targetPartName: String?,
        targetEdge: String,
        distance: Double,
        replaceExisting: Bool
    ) -> String {
        guard let sourceIndex = resolvePartIndex(document: document, currentCardId: currentCardId, name: sourcePartName) else {
            return "Part '\(sourcePartName)' not found on the current card/background."
        }
        guard let source = ConstraintEdge(rawValue: sourceEdge) else {
            return "Invalid source_edge '\(sourceEdge)'. Valid: \(ConstraintEdge.allCases.map(\.rawValue).joined(separator: ", "))."
        }
        guard let target = ConstraintEdge(rawValue: targetEdge) else {
            return "Invalid target_edge '\(targetEdge)'. Valid: \(ConstraintEdge.allCases.map(\.rawValue).joined(separator: ", "))."
        }

        let trimmedTargetName = targetPartName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let targetType: ConstraintTargetType
        let targetPartId: UUID?
        if trimmedTargetName.isEmpty || trimmedTargetName.lowercased() == "canvas" || trimmedTargetName.lowercased() == "safe area" {
            targetType = .canvas
            targetPartId = nil
        } else {
            guard let targetIndex = resolvePartIndex(document: document, currentCardId: currentCardId, name: trimmedTargetName) else {
                return "Target part '\(trimmedTargetName)' not found on the current card/background."
            }
            targetType = .part
            targetPartId = document.parts[targetIndex].id
        }

        let sourcePartId = document.parts[sourceIndex].id
        if replaceExisting {
            document.constraints.removeAll {
                $0.sourcePartId == sourcePartId
                    && $0.sourceEdge == source
                    && $0.targetType == targetType
                    && $0.targetEdge == target
                    && $0.targetPartId == targetPartId
            }
        }
        let constraint = LayoutConstraint(
            sourcePartId: sourcePartId,
            sourceEdge: source,
            targetType: targetType,
            targetPartId: targetPartId,
            targetEdge: target,
            distance: distance
        )
        document.addConstraint(constraint)
        return "Added layout constraint \(document.parts[sourceIndex].name).\(source.rawValue) -> \(targetType == .canvas ? "safe-area canvas" : "part").\(target.rawValue), distance=\(format(distance))."
    }

    public static func pinPartToSafeArea(
        document: inout HypeDocument,
        currentCardId: UUID,
        partName: String,
        edges: [String],
        margin: Double?,
        replaceExisting: Bool
    ) -> String {
        guard let index = resolvePartIndex(document: document, currentCardId: currentCardId, name: partName) else {
            return "Part '\(partName)' not found on the current card/background."
        }
        let profile = document.stack.deploymentTargets.primaryProfile
        let metrics = metrics(for: profile)
        let resolvedMargin = margin ?? metrics.edgeMargin
        let requested = edges.isEmpty ? ["left", "top"] : edges
        let validEdges = Set(ConstraintEdge.allCases.map(\.rawValue))
        let invalid = requested.filter { !validEdges.contains($0) }
        guard invalid.isEmpty else {
            return "Invalid edge(s): \(invalid.joined(separator: ", ")). Valid: \(validEdges.sorted().joined(separator: ", "))."
        }

        let sourcePartId = document.parts[index].id
        if replaceExisting {
            let edgeSet = Set(requested.compactMap(ConstraintEdge.init(rawValue:)))
            document.constraints.removeAll {
                $0.sourcePartId == sourcePartId
                    && $0.targetType == .canvas
                    && (edgeSet.contains($0.sourceEdge) || shouldRemoveOppositePin(existing: $0.sourceEdge, requested: edgeSet))
            }
        }

        var added: [String] = []
        for edgeName in requested {
            guard let edge = ConstraintEdge(rawValue: edgeName) else { continue }
            let distance: Double
            switch edge {
            case .left, .top:
                distance = resolvedMargin
            case .right, .bottom:
                distance = -resolvedMargin
            case .centerX, .centerY:
                distance = 0
            }
            document.addConstraint(LayoutConstraint(
                sourcePartId: sourcePartId,
                sourceEdge: edge,
                targetType: .canvas,
                targetEdge: edge,
                distance: distance
            ))
            added.append("\(edge.rawValue)=\(format(distance))")
        }

        return "Pinned part \"\(document.parts[index].name)\" to safe-area canvas with \(added.joined(separator: ", "))."
    }

    public static func applyLayout(
        document: inout HypeDocument,
        currentCardId: UUID,
        layoutType: String,
        partNames: [String],
        profileId: String?,
        columns: Int?,
        spacing: Double?,
        margin: Double?,
        fillWidth: Bool,
        replaceConstraints: Bool,
        layoutPolicy: String?
    ) -> String {
        let profile = profileId
            .flatMap { HypeDeviceProfileCatalog.profile(id: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            ?? document.stack.deploymentTargets.primaryProfile
        let type = normalizedLayoutType(layoutType)
        var indices = resolvePartIndices(document: document, currentCardId: currentCardId, partNames: partNames)
        guard !indices.isEmpty else { return "No matching parts found on the current card/background." }
        indices.sort { document.parts[$0].sortKey < document.parts[$1].sortKey }

        if let layoutPolicy, !layoutPolicy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let parsed = TargetLayoutPolicy.parse(layoutPolicy) else {
                return "Invalid layout_policy '\(layoutPolicy)'. Valid: fixed, scaleToFit, stretchToFill."
            }
            document.stack.deploymentTargets.layoutPolicy = parsed
        } else if document.stack.deploymentTargets.selectedPlatforms.count > 1,
                  document.stack.deploymentTargets.layoutPolicy == .fixed {
            document.stack.deploymentTargets.layoutPolicy = .scaleToFit
        }

        let sourceWidth = Double(document.stack.width)
        let sourceHeight = Double(document.stack.height)
        let metrics = combinedAuthoringMetrics(
            primaryProfile: profile,
            selectedProfiles: document.stack.deploymentTargets.selectedProfiles,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            policy: document.stack.deploymentTargets.layoutPolicy
        )
        let resolvedSpacing = max(0, spacing ?? metrics.defaultSpacing)
        let resolvedMargin = max(0, margin ?? metrics.edgeMargin)

        if replaceConstraints {
            let ids = Set(indices.map { document.parts[$0].id })
            document.constraints.removeAll { ids.contains($0.sourcePartId) }
        }
        for index in indices where isTextBearing(document.parts[index].partType) {
            document.parts[index].textSize = max(document.parts[index].textSize, metrics.minimumTextSize)
        }

        let safeRect = sourceSafeRect(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            profile: profile,
            margin: resolvedMargin
        )
        switch type {
        case "vertical_stack":
            applyVerticalStack(indices: indices, document: &document, safeRect: safeRect, metrics: metrics, spacing: resolvedSpacing, fillWidth: fillWidth)
        case "horizontal_row", "toolbar":
            applyHorizontalRow(indices: indices, document: &document, safeRect: safeRect, metrics: metrics, spacing: resolvedSpacing)
        case "grid":
            applyGrid(indices: indices, document: &document, safeRect: safeRect, metrics: metrics, spacing: resolvedSpacing, columns: columns)
        case "form":
            applyForm(indices: indices, document: &document, safeRect: safeRect, metrics: metrics, spacing: resolvedSpacing, profile: profile)
        case "full_bleed":
            applyFullBleed(indices: indices, document: &document, sourceWidth: sourceWidth, sourceHeight: sourceHeight)
        default:
            return "Invalid layout_type '\(layoutType)'. Valid: vertical_stack, horizontal_row, grid, form, toolbar, full_bleed."
        }

        if replaceConstraints && type != "full_bleed" {
            addCanvasConstraints(for: indices, document: &document, safeRect: safeRect, fillWidth: fillWidth || type == "form")
        }

        let validation = validate(
            document: document,
            currentCardId: currentCardId,
            profileIds: [profile.id],
            includeAllSelected: true,
            allowFullBleed: type == "full_bleed"
        )
        return [
            "Applied HIG \(type) layout to \(indices.count) part(s) using profile \(profile.id), margin=\(format(resolvedMargin)), spacing=\(format(resolvedSpacing)), layoutPolicy=\(document.stack.deploymentTargets.layoutPolicy.rawValue).",
            validation,
        ].joined(separator: "\n")
    }

    public static func resolvedPartNames(_ raw: String) -> [String] {
        raw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func validate(
        parts: [Part],
        document: HypeDocument,
        currentCardId: UUID,
        profile: HypeDeviceProfile,
        allowFullBleed: Bool
    ) -> [HIGLayoutIssue] {
        let metrics = metrics(for: profile)
        let resolution = LayoutResolver().resolve(document: document, profile: profile, cardId: currentCardId)
        var issues: [HIGLayoutIssue] = []
        let safeMinX = resolution.safeContentLeft
        let safeMinY = resolution.safeContentTop
        let safeMaxX = resolution.safeContentLeft + resolution.safeContentWidth
        let safeMaxY = resolution.safeContentTop + resolution.safeContentHeight

        for part in parts {
            guard let geometry = resolution.geometries[part.id] else { continue }
            let support = PartAvailabilityCatalog.support(for: part.partType, on: profile.platform)
            if !support.availability.isUsable {
                issues.append(HIGLayoutIssue(
                    severity: .error,
                    profileId: profile.id,
                    partName: part.name,
                    partType: part.partType,
                    message: "unsupported on \(profile.platform.displayName): \(support.reason)"
                ))
            }

            let isFullBleedAllowed = allowFullBleed && canBeFullBleed(part.partType)
            if !isFullBleedAllowed {
                if geometry.left < safeMinX - 0.5
                    || geometry.top < safeMinY - 0.5
                    || geometry.left + geometry.width > safeMaxX + 0.5
                    || geometry.top + geometry.height > safeMaxY + 0.5 {
                    issues.append(HIGLayoutIssue(
                        severity: .error,
                        profileId: profile.id,
                        partName: part.name,
                        partType: part.partType,
                        message: "resolved frame \(rectDescription(geometry)) is outside safe content \(format(safeMinX)),\(format(safeMinY)) \(format(safeMaxX - safeMinX))x\(format(safeMaxY - safeMinY))"
                    ))
                }
            }

            if isInteractive(part.partType) {
                if geometry.width < metrics.minimumHitWidth - 0.5 || geometry.height < metrics.minimumHitHeight - 0.5 {
                    issues.append(HIGLayoutIssue(
                        severity: .error,
                        profileId: profile.id,
                        partName: part.name,
                        partType: part.partType,
                        message: "interactive hit area \(format(geometry.width))x\(format(geometry.height)) is below \(format(metrics.minimumHitWidth))x\(format(metrics.minimumHitHeight)) pt"
                    ))
                }
            }

            if isTextBearing(part.partType), part.textSize > 0, part.textSize < metrics.minimumTextSize - 0.5 {
                issues.append(HIGLayoutIssue(
                    severity: .warning,
                    profileId: profile.id,
                    partName: part.name,
                    partType: part.partType,
                    message: "text size \(format(part.textSize)) is below platform body-text guidance \(format(metrics.minimumTextSize)) pt"
                ))
            }
        }

        let interactiveParts = parts.filter { isInteractive($0.partType) }
        for i in 0..<interactiveParts.count {
            for j in (i + 1)..<interactiveParts.count {
                let a = interactiveParts[i]
                let b = interactiveParts[j]
                guard let ag = resolution.geometries[a.id], let bg = resolution.geometries[b.id] else { continue }
                let distance = rectDistance(ag, bg)
                if distance < metrics.defaultSpacing - 0.5 {
                    issues.append(HIGLayoutIssue(
                        severity: .warning,
                        profileId: profile.id,
                        partName: "\(a.name) / \(b.name)",
                        partType: a.partType,
                        message: "interactive controls are \(format(distance)) pt apart; target \(format(metrics.defaultSpacing)) pt or more"
                    ))
                }
            }
        }
        return issues
    }

    private static func profilesForValidation(
        document: HypeDocument,
        explicitProfileIds: [String],
        includeAllSelected: Bool
    ) -> [HypeDeviceProfile] {
        let explicit = explicitProfileIds.compactMap { HypeDeviceProfileCatalog.profile(id: $0) }
        if !explicit.isEmpty { return explicit }
        if includeAllSelected {
            return document.stack.deploymentTargets.selectedProfiles
        }
        return [document.stack.deploymentTargets.primaryProfile]
    }

    private static func combinedAuthoringMetrics(
        primaryProfile: HypeDeviceProfile,
        selectedProfiles: [HypeDeviceProfile],
        sourceWidth: Double,
        sourceHeight: Double,
        policy: TargetLayoutPolicy
    ) -> HIGLayoutMetrics {
        var result = metrics(for: primaryProfile)
        for profile in selectedProfiles {
            var candidate = metrics(for: profile)
            let scale = projectionScale(
                profile: profile,
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                policy: policy
            )
            candidate.minimumHitWidth = candidate.minimumHitWidth / max(0.001, scale.x)
            candidate.minimumHitHeight = candidate.minimumHitHeight / max(0.001, scale.y)
            result.minimumHitWidth = max(result.minimumHitWidth, candidate.minimumHitWidth)
            result.minimumHitHeight = max(result.minimumHitHeight, candidate.minimumHitHeight)
            result.minimumTextSize = max(result.minimumTextSize, candidate.minimumTextSize)
            result.edgeMargin = max(result.edgeMargin, candidate.edgeMargin)
            result.defaultSpacing = max(result.defaultSpacing, candidate.defaultSpacing)
            result.unbezeledSpacing = max(result.unbezeledSpacing, candidate.unbezeledSpacing)
            result.prefersFocusSafeSpacing = result.prefersFocusSafeSpacing || candidate.prefersFocusSafeSpacing
        }
        return result
    }

    private static func projectionScale(
        profile: HypeDeviceProfile,
        sourceWidth: Double,
        sourceHeight: Double,
        policy: TargetLayoutPolicy
    ) -> (x: Double, y: Double) {
        let safeWidth = max(1, Double(profile.width) - profile.safeArea.left - profile.safeArea.right)
        let safeHeight = max(1, Double(profile.height) - profile.safeArea.top - profile.safeArea.bottom)
        switch policy {
        case .fixed:
            return (1, 1)
        case .scaleToFit:
            let scale = min(safeWidth / max(1, sourceWidth), safeHeight / max(1, sourceHeight))
            return (scale, scale)
        case .stretchToFill:
            return (safeWidth / max(1, sourceWidth), safeHeight / max(1, sourceHeight))
        }
    }

    private static func sourceSafeRect(
        sourceWidth: Double,
        sourceHeight: Double,
        profile: HypeDeviceProfile,
        margin: Double
    ) -> (left: Double, top: Double, width: Double, height: Double) {
        let horizontalScale = sourceWidth / max(1, Double(profile.width))
        let verticalScale = sourceHeight / max(1, Double(profile.height))
        let left = max(margin, profile.safeArea.left * horizontalScale + margin)
        let top = max(margin, profile.safeArea.top * verticalScale + margin)
        let right = max(margin, profile.safeArea.right * horizontalScale + margin)
        let bottom = max(margin, profile.safeArea.bottom * verticalScale + margin)
        return (
            left,
            top,
            max(1, sourceWidth - left - right),
            max(1, sourceHeight - top - bottom)
        )
    }

    private static func applyVerticalStack(
        indices: [Int],
        document: inout HypeDocument,
        safeRect: (left: Double, top: Double, width: Double, height: Double),
        metrics: HIGLayoutMetrics,
        spacing: Double,
        fillWidth: Bool
    ) {
        var y = safeRect.top
        for index in indices {
            var part = document.parts[index]
            let size = recommendedSize(for: part, metrics: metrics, availableWidth: safeRect.width, fillWidth: fillWidth)
            part.left = roundToGrid(safeRect.left, unit: metrics.gridUnit)
            part.top = roundToGrid(y, unit: metrics.gridUnit)
            part.width = ceilToGrid(min(size.width, safeRect.left + safeRect.width - part.left), unit: metrics.gridUnit)
            part.height = ceilToGrid(size.height, unit: metrics.gridUnit)
            y = part.top + part.height + spacing
            document.parts[index] = part
        }
    }

    private static func applyHorizontalRow(
        indices: [Int],
        document: inout HypeDocument,
        safeRect: (left: Double, top: Double, width: Double, height: Double),
        metrics: HIGLayoutMetrics,
        spacing: Double
    ) {
        var x = safeRect.left
        for index in indices {
            var part = document.parts[index]
            let size = recommendedSize(for: part, metrics: metrics, availableWidth: safeRect.width, fillWidth: false)
            part.left = roundToGrid(x, unit: metrics.gridUnit)
            part.top = roundToGrid(safeRect.top, unit: metrics.gridUnit)
            part.width = ceilToGrid(min(size.width, safeRect.left + safeRect.width - part.left), unit: metrics.gridUnit)
            part.height = ceilToGrid(size.height, unit: metrics.gridUnit)
            x = part.left + part.width + spacing
            document.parts[index] = part
        }
    }

    private static func applyGrid(
        indices: [Int],
        document: inout HypeDocument,
        safeRect: (left: Double, top: Double, width: Double, height: Double),
        metrics: HIGLayoutMetrics,
        spacing: Double,
        columns: Int?
    ) {
        let count = max(1, columns ?? defaultColumnCount(for: safeRect.width, metrics: metrics))
        let cellWidth = max(metrics.minimumHitWidth, (safeRect.width - spacing * Double(count - 1)) / Double(count))
        for (offset, index) in indices.enumerated() {
            var part = document.parts[index]
            let row = offset / count
            let column = offset % count
            let size = recommendedSize(for: part, metrics: metrics, availableWidth: cellWidth, fillWidth: true)
            part.left = roundToGrid(safeRect.left + Double(column) * (cellWidth + spacing), unit: metrics.gridUnit)
            part.top = roundToGrid(safeRect.top + Double(row) * (size.height + spacing), unit: metrics.gridUnit)
            part.width = ceilToGrid(min(cellWidth, size.width), unit: metrics.gridUnit)
            part.height = ceilToGrid(size.height, unit: metrics.gridUnit)
            document.parts[index] = part
        }
    }

    private static func applyForm(
        indices: [Int],
        document: inout HypeDocument,
        safeRect: (left: Double, top: Double, width: Double, height: Double),
        metrics: HIGLayoutMetrics,
        spacing: Double,
        profile: HypeDeviceProfile
    ) {
        var y = safeRect.top
        let compact = profile.platform == .iPhone || safeRect.width < 520
        let labelWidth = compact ? safeRect.width : max(120, min(240, safeRect.width * 0.32))
        let controlLeft = compact ? safeRect.left : safeRect.left + labelWidth + spacing
        let controlWidth = compact ? safeRect.width : safeRect.width - labelWidth - spacing

        for index in indices {
            var part = document.parts[index]
            let isLabel = isLikelyLabel(part)
            let availableWidth = isLabel ? labelWidth : controlWidth
            let size = recommendedSize(for: part, metrics: metrics, availableWidth: availableWidth, fillWidth: !isLabel)
            part.left = roundToGrid(isLabel || compact ? safeRect.left : controlLeft, unit: metrics.gridUnit)
            part.top = roundToGrid(y, unit: metrics.gridUnit)
            part.width = ceilToGrid(min(availableWidth, size.width), unit: metrics.gridUnit)
            part.height = ceilToGrid(size.height, unit: metrics.gridUnit)
            document.parts[index] = part
            y = part.top + part.height + (isLabel && compact ? metrics.defaultSpacing / 2 : spacing)
        }
    }

    private static func applyFullBleed(indices: [Int], document: inout HypeDocument, sourceWidth: Double, sourceHeight: Double) {
        for index in indices {
            document.parts[index].left = 0
            document.parts[index].top = 0
            document.parts[index].width = sourceWidth
            document.parts[index].height = sourceHeight
        }
    }

    private static func addCanvasConstraints(
        for indices: [Int],
        document: inout HypeDocument,
        safeRect: (left: Double, top: Double, width: Double, height: Double),
        fillWidth: Bool
    ) {
        for index in indices {
            let part = document.parts[index]
            document.addConstraint(LayoutConstraint(sourcePartId: part.id, sourceEdge: .left, targetType: .canvas, targetEdge: .left, distance: part.left))
            document.addConstraint(LayoutConstraint(sourcePartId: part.id, sourceEdge: .top, targetType: .canvas, targetEdge: .top, distance: part.top))
            if fillWidth {
                let rightGap = max(0, safeRect.left + safeRect.width - part.left - part.width)
                document.addConstraint(LayoutConstraint(sourcePartId: part.id, sourceEdge: .right, targetType: .canvas, targetEdge: .right, distance: -rightGap))
            }
        }
    }

    private static func recommendedSize(
        for part: Part,
        metrics: HIGLayoutMetrics,
        availableWidth: Double,
        fillWidth: Bool
    ) -> (width: Double, height: Double) {
        let minimum = minimumSize(for: part.partType, metrics: metrics)
        let width: Double
        if fillWidth || prefersFilledWidth(part.partType) {
            width = max(minimum.width, availableWidth)
        } else {
            width = min(max(part.width, minimum.width), availableWidth)
        }
        let height = max(part.height, minimum.height)
        return (width, height)
    }

    private static func minimumSize(for type: PartType, metrics: HIGLayoutMetrics) -> (width: Double, height: Double) {
        switch type {
        case .button, .toggle, .link, .menu:
            return (max(metrics.minimumHitWidth, 88), metrics.minimumHitHeight)
        case .field, .searchField:
            return (max(metrics.minimumHitWidth * 3, 120), metrics.minimumHitHeight)
        case .slider, .segmented, .stepper:
            return (max(metrics.minimumHitWidth * 2, 120), metrics.minimumHitHeight)
        case .progressView:
            return (max(metrics.minimumHitWidth * 2, 120), max(14, metrics.minimumHitHeight / 2))
        case .gauge, .colorWell:
            return (metrics.minimumHitWidth, metrics.minimumHitHeight)
        case .spriteArea, .scene3D, .video, .webpage, .map, .pdf, .chart:
            return (max(240, metrics.minimumHitWidth * 4), max(180, metrics.minimumHitHeight * 4))
        case .calendar:
            return (max(280, metrics.minimumHitWidth * 4), max(240, metrics.minimumHitHeight * 4))
        case .pianoKeyboard, .stepSequencer, .musicMixer:
            return (max(320, metrics.minimumHitWidth * 5), max(140, metrics.minimumHitHeight * 2))
        default:
            return (metrics.minimumHitWidth, metrics.minimumHitHeight)
        }
    }

    private static func resolvePartIndices(document: HypeDocument, currentCardId: UUID, partNames: [String]) -> [Int] {
        let names = partNames.map { $0.lowercased() }
        let effective = document.effectivePartsForCard(currentCardId)
        if names.isEmpty {
            return effective.compactMap { part in document.partIndex(byId: part.id) }
        }
        return names.compactMap { name in
            effective.first { $0.name.lowercased() == name }.flatMap { document.partIndex(byId: $0.id) }
        }
    }

    private static func resolvePartIndex(document: HypeDocument, currentCardId: UUID, name: String) -> Int? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        return document.effectivePartsForCard(currentCardId)
            .first { $0.name.lowercased() == trimmed }
            .flatMap { document.partIndex(byId: $0.id) }
    }

    private static func normalizedLayoutType(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func defaultColumnCount(for width: Double, metrics: HIGLayoutMetrics) -> Int {
        if metrics.profile.platform == .iPhone { return 1 }
        if width >= 900 { return 3 }
        return 2
    }

    private static func prefersFilledWidth(_ type: PartType) -> Bool {
        switch type {
        case .field, .searchField, .webpage, .map, .pdf, .chart, .spriteArea, .video, .scene3D, .progressView:
            return true
        default:
            return false
        }
    }

    private static func isInteractive(_ type: PartType) -> Bool {
        switch type {
        case .button, .field, .webpage, .video, .calendar, .pdf, .map, .colorWell,
             .stepper, .slider, .toggle, .segmented, .audioRecorder, .scene3D,
             .musicPlayer, .pianoKeyboard, .stepSequencer, .musicMixer, .appleMusicBrowser,
             .link, .menu, .searchField, .spriteArea:
            return true
        default:
            return false
        }
    }

    private static func isTextBearing(_ type: PartType) -> Bool {
        switch type {
        case .button, .field, .toggle, .segmented, .link, .menu, .searchField:
            return true
        default:
            return false
        }
    }

    private static func canBeFullBleed(_ type: PartType) -> Bool {
        switch type {
        case .spriteArea, .image, .video, .webpage, .map, .scene3D:
            return true
        default:
            return false
        }
    }

    private static func isLikelyLabel(_ part: Part) -> Bool {
        part.partType == .field && (part.lockText || part.name.lowercased().contains("label"))
    }

    private static func rectDistance(_ a: PartResolvedGeometry, _ b: PartResolvedGeometry) -> Double {
        let ax2 = a.left + a.width
        let ay2 = a.top + a.height
        let bx2 = b.left + b.width
        let by2 = b.top + b.height
        let dx = max(0, max(b.left - ax2, a.left - bx2))
        let dy = max(0, max(b.top - ay2, a.top - by2))
        if dx == 0 { return dy }
        if dy == 0 { return dx }
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func rectDescription(_ geometry: PartResolvedGeometry) -> String {
        "\(format(geometry.left)),\(format(geometry.top)) \(format(geometry.width))x\(format(geometry.height))"
    }

    private static func roundToGrid(_ value: Double, unit: Double) -> Double {
        guard unit > 0 else { return value }
        return (value / unit).rounded() * unit
    }

    private static func ceilToGrid(_ value: Double, unit: Double) -> Double {
        guard unit > 0 else { return value }
        return (value / unit).rounded(.up) * unit
    }

    private static func shouldRemoveOppositePin(existing: ConstraintEdge, requested: Set<ConstraintEdge>) -> Bool {
        if requested.contains(.left) && (existing == .right || existing == .centerX) { return true }
        if requested.contains(.right) && (existing == .left || existing == .centerX) { return true }
        if requested.contains(.centerX) && (existing == .left || existing == .right) { return true }
        if requested.contains(.top) && (existing == .bottom || existing == .centerY) { return true }
        if requested.contains(.bottom) && (existing == .top || existing == .centerY) { return true }
        if requested.contains(.centerY) && (existing == .top || existing == .bottom) { return true }
        return false
    }

    private static func format(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.2f", value)
    }
}
