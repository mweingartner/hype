import Foundation

public struct ClassicMenuResource: Sendable, Equatable {
    public var resourceId: Int
    public var menuId: Int
    public var procId: Int
    public var enabledFlags: UInt32
    public var enabled: Bool
    public var title: String
    public var items: [ClassicMenuItem]

    public init(
        resourceId: Int,
        menuId: Int,
        procId: Int = 0,
        enabledFlags: UInt32 = 0,
        enabled: Bool = true,
        title: String,
        items: [ClassicMenuItem]
    ) {
        self.resourceId = resourceId
        self.menuId = menuId
        self.procId = procId
        self.enabledFlags = enabledFlags
        self.enabled = enabled
        self.title = title
        self.items = items
    }
}

public struct ClassicMenuItem: Sendable, Equatable {
    public var name: String
    public var iconNumber: Int
    public var keyEquivalent: Int
    public var markCharacter: Int
    public var styleFlags: Int
    public var enabled: Bool

    public init(
        name: String,
        iconNumber: Int = 0,
        keyEquivalent: Int = 0,
        markCharacter: Int = 0,
        styleFlags: Int = 0,
        enabled: Bool = true
    ) {
        self.name = name
        self.iconNumber = iconNumber
        self.keyEquivalent = keyEquivalent
        self.markCharacter = markCharacter
        self.styleFlags = styleFlags
        self.enabled = enabled
    }

    public var isSeparator: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "-" || trimmed == "-1"
    }
}

public struct ClassicMenuSelection: Sendable, Equatable {
    public var menu: ClassicMenuResource
    public var item: ClassicMenuItem
}

public enum ClassicMenuCommand: Sendable, Equatable {
    case createCard
    case goFirstCard
    case goPreviousCard
    case goNextCard
    case goLastCard
    case quitApp
    case unsupported
}

public enum ClassicMenuCommandMapper {
    public static func menus(in document: HypeDocument) -> [ClassicMenuResource] {
        document.assetRepository.assets.compactMap(ClassicMenuResource.init(asset:))
            .sorted { lhs, rhs in
                if lhs.resourceId != rhs.resourceId { return lhs.resourceId < rhs.resourceId }
                return lhs.menuId < rhs.menuId
            }
    }

    public static func findSelection(named itemName: String, in document: HypeDocument) -> ClassicMenuSelection? {
        let wanted = normalized(itemName)
        guard !wanted.isEmpty else { return nil }
        for menu in menus(in: document) where menu.enabled {
            if let item = menu.items.first(where: { !$0.isSeparator && normalized($0.name) == wanted }) {
                return ClassicMenuSelection(menu: menu, item: item)
            }
        }
        return nil
    }

    public static func command(for selection: ClassicMenuSelection) -> ClassicMenuCommand {
        command(menuTitle: selection.menu.title, itemName: selection.item.name)
    }

    public static func command(menuTitle: String, itemName: String) -> ClassicMenuCommand {
        let menu = normalized(menuTitle)
        let item = normalized(itemName)
        switch (menu, item) {
        case (_, "new card"), ("file", "new card"):
            return .createCard
        case ("go", "first"), ("go", "first card"), ("go", "home"), (_, "go first"), (_, "go first card"), (_, "go home"):
            return .goFirstCard
        case ("go", "prev"), ("go", "previous"), ("go", "previous card"), ("go", "back"), (_, "go prev"), (_, "go previous"), (_, "go previous card"):
            return .goPreviousCard
        case ("go", "next"), ("go", "next card"), (_, "go next"), (_, "go next card"):
            return .goNextCard
        case ("go", "last"), ("go", "last card"), (_, "go last"), (_, "go last card"):
            return .goLastCard
        case (_, "quit"), (_, "quit hypercard"), ("file", "quit"), ("file", "quit hypercard"):
            return .quitApp
        default:
            return .unsupported
        }
    }

    public static func normalized(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutEllipsis = trimmed.replacingOccurrences(of: "...", with: "")
        return withoutEllipsis
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }
}

public extension ClassicMenuResource {
    init?(asset: Asset) {
        guard asset.kind == .placeholderAsset else { return nil }
        let resourceType = asset.metadata.first { $0.key == "resource_type" }?.value
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard resourceType == "MENU" else { return nil }

        guard let data = Self.menuJSONData(from: asset) else { return nil }
        guard let decoded = try? JSONDecoder().decode(ImportedMenuPayload.self, from: data) else { return nil }

        let resourceId = Int(asset.metadata.first { $0.key == "resource_id" }?.value ?? "") ?? decoded.menuId
        self.init(
            resourceId: resourceId,
            menuId: decoded.menuId,
            procId: decoded.procId,
            enabledFlags: decoded.enabledFlags,
            enabled: decoded.enabled,
            title: decoded.title,
            items: decoded.items.map {
                ClassicMenuItem(
                    name: $0.name,
                    iconNumber: $0.iconNumber,
                    keyEquivalent: $0.keyEquivalent,
                    markCharacter: $0.markCharacter,
                    styleFlags: $0.styleFlags,
                    enabled: $0.enabled
                )
            }
        )
    }

    private static func menuJSONData(from asset: Asset) -> Data? {
        if !asset.data.isEmpty,
           let decoded = String(data: asset.data, encoding: .utf8),
           decoded.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            return asset.data
        }
        if let entry = asset.metadata.first(where: { $0.key.hasPrefix("MENU_") && $0.key.hasSuffix(".json") }) {
            return entry.value.data(using: .utf8)
        }
        return asset.metadata.first(where: { $0.mimeType == "application/json" && $0.value.contains("\"items\"") })?.value.data(using: .utf8)
    }
}

private struct ImportedMenuPayload: Decodable {
    var menuId: Int
    var procId: Int
    var enabledFlags: UInt32
    var enabled: Bool
    var title: String
    var items: [ImportedMenuItemPayload]
}

private struct ImportedMenuItemPayload: Decodable {
    var name: String
    var iconNumber: Int
    var keyEquivalent: Int
    var markCharacter: Int
    var styleFlags: Int
    var enabled: Bool
}
