import Foundation

#if canImport(SwiftUI)
import SwiftUI
#endif

/// A complete theme spec — every design token a Hype view needs to
/// render itself: surface colors, part default colors, accents,
/// chrome, typography, and structural ratios (corners, spacing,
/// shadows, strokes). Themes are `Codable` so they round-trip into
/// `.hype` documents and can be exported as standalone JSON.
///
/// **Built-in vs user themes**
/// - The 6 themes in `BuiltInThemes.all` are read-only at runtime;
///   any UI editor must respect `isBuiltIn == true` and refuse
///   edits / deletion.
/// - User themes live on `HypeDocument.themes` and travel with the
///   `.hype` file.
///
/// **Cascade**
/// Effective theme for a given card:
///   `card.themeName ?? background.themeName ?? stack.themeName`
/// `Stack.themeName` is non-optional (`String`) and defaults to
/// `BuiltInThemes.fallbackName`, so the cascade always terminates.
public struct HypeTheme: Codable, Sendable, Identifiable, Equatable, Hashable {

    // MARK: Identity

    public var id: UUID
    public var name: String
    public var isBuiltIn: Bool
    public var basedOn: String?
    public var createdAt: Date
    public var modifiedAt: Date

    // MARK: Surface colors

    public var cardBackground: ColorRef
    public var cardForeground: ColorRef
    public var backgroundFill: ColorRef
    public var canvasMargin: ColorRef

    // MARK: Part default colors

    public var buttonBackground: ColorRef
    public var buttonForeground: ColorRef
    public var buttonBorder: ColorRef
    public var buttonHilite: ColorRef
    public var fieldBackground: ColorRef
    public var fieldForeground: ColorRef
    public var fieldBorder: ColorRef
    public var shapeFillDefault: ColorRef
    public var shapeStrokeDefault: ColorRef

    // MARK: Selection / accent

    public var accent: ColorRef
    public var selectionFill: ColorRef
    public var selectionStroke: ColorRef

    // MARK: Chrome (author mode only)

    public var toolbarBackground: ColorRef
    public var inspectorBackground: ColorRef
    public var panelDivider: ColorRef

    // MARK: Typography

    public var defaultFontFamily: String
    public var defaultFontSize: Double
    public var headingFontFamily: String
    public var headingFontSize: Double
    public var monospaceFontFamily: String
    public var labelFontSize: Double

    // MARK: Structure

    public var cornerRadiusSmall: Double
    public var cornerRadiusMedium: Double
    public var cornerRadiusLarge: Double
    public var spacingUnit: Double
    public var strokeWidthThin: Double
    public var strokeWidthMedium: Double
    public var shadowOpacity: Double
    public var shadowRadius: Double

    // MARK: Script-editor sub-theme
    //
    // Syntax-highlighting colors are conceptually a separate concern
    // (you might want a vivid IDE palette over a calm visual theme),
    // but keeping them on HypeTheme avoids a second cascade and lets
    // a user import/export "everything for the look of my stack" in
    // one file.
    public var scriptTheme: HypeScriptTheme

    // MARK: Init

    public init(
        id: UUID = UUID(),
        name: String,
        isBuiltIn: Bool = false,
        basedOn: String? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        cardBackground: ColorRef,
        cardForeground: ColorRef,
        backgroundFill: ColorRef,
        canvasMargin: ColorRef,
        buttonBackground: ColorRef,
        buttonForeground: ColorRef,
        buttonBorder: ColorRef,
        buttonHilite: ColorRef,
        fieldBackground: ColorRef,
        fieldForeground: ColorRef,
        fieldBorder: ColorRef,
        shapeFillDefault: ColorRef,
        shapeStrokeDefault: ColorRef,
        accent: ColorRef,
        selectionFill: ColorRef,
        selectionStroke: ColorRef,
        toolbarBackground: ColorRef,
        inspectorBackground: ColorRef,
        panelDivider: ColorRef,
        defaultFontFamily: String,
        defaultFontSize: Double,
        headingFontFamily: String,
        headingFontSize: Double,
        monospaceFontFamily: String,
        labelFontSize: Double,
        cornerRadiusSmall: Double,
        cornerRadiusMedium: Double,
        cornerRadiusLarge: Double,
        spacingUnit: Double,
        strokeWidthThin: Double,
        strokeWidthMedium: Double,
        shadowOpacity: Double,
        shadowRadius: Double,
        scriptTheme: HypeScriptTheme
    ) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.basedOn = basedOn
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.cardBackground = cardBackground
        self.cardForeground = cardForeground
        self.backgroundFill = backgroundFill
        self.canvasMargin = canvasMargin
        self.buttonBackground = buttonBackground
        self.buttonForeground = buttonForeground
        self.buttonBorder = buttonBorder
        self.buttonHilite = buttonHilite
        self.fieldBackground = fieldBackground
        self.fieldForeground = fieldForeground
        self.fieldBorder = fieldBorder
        self.shapeFillDefault = shapeFillDefault
        self.shapeStrokeDefault = shapeStrokeDefault
        self.accent = accent
        self.selectionFill = selectionFill
        self.selectionStroke = selectionStroke
        self.toolbarBackground = toolbarBackground
        self.inspectorBackground = inspectorBackground
        self.panelDivider = panelDivider
        self.defaultFontFamily = defaultFontFamily
        self.defaultFontSize = defaultFontSize
        self.headingFontFamily = headingFontFamily
        self.headingFontSize = headingFontSize
        self.monospaceFontFamily = monospaceFontFamily
        self.labelFontSize = labelFontSize
        self.cornerRadiusSmall = cornerRadiusSmall
        self.cornerRadiusMedium = cornerRadiusMedium
        self.cornerRadiusLarge = cornerRadiusLarge
        self.spacingUnit = spacingUnit
        self.strokeWidthThin = strokeWidthThin
        self.strokeWidthMedium = strokeWidthMedium
        self.shadowOpacity = shadowOpacity
        self.shadowRadius = shadowRadius
        self.scriptTheme = scriptTheme
    }

    // MARK: Codable
    //
    // Tolerant decode so themes from older `.hype` files (before
    // some fields existed) and AI-authored themes (which may omit
    // fields they don't care about) load with sensible defaults.

    private enum CodingKeys: String, CodingKey {
        case id, name, isBuiltIn, basedOn, createdAt, modifiedAt
        case cardBackground, cardForeground, backgroundFill, canvasMargin
        case buttonBackground, buttonForeground, buttonBorder, buttonHilite
        case fieldBackground, fieldForeground, fieldBorder
        case shapeFillDefault, shapeStrokeDefault
        case accent, selectionFill, selectionStroke
        case toolbarBackground, inspectorBackground, panelDivider
        case defaultFontFamily, defaultFontSize, headingFontFamily, headingFontSize
        case monospaceFontFamily, labelFontSize
        case cornerRadiusSmall, cornerRadiusMedium, cornerRadiusLarge
        case spacingUnit, strokeWidthThin, strokeWidthMedium
        case shadowOpacity, shadowRadius
        case scriptTheme
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let blank = ColorRef.hex("#FFFFFF")
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.name = (try? c.decode(String.self, forKey: .name)) ?? "Untitled"
        self.isBuiltIn = (try? c.decode(Bool.self, forKey: .isBuiltIn)) ?? false
        self.basedOn = try? c.decode(String.self, forKey: .basedOn)
        self.createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        self.modifiedAt = (try? c.decode(Date.self, forKey: .modifiedAt)) ?? Date()

        self.cardBackground       = (try? c.decode(ColorRef.self, forKey: .cardBackground))       ?? blank
        self.cardForeground       = (try? c.decode(ColorRef.self, forKey: .cardForeground))       ?? .hex("#000000")
        self.backgroundFill       = (try? c.decode(ColorRef.self, forKey: .backgroundFill))       ?? blank
        self.canvasMargin         = (try? c.decode(ColorRef.self, forKey: .canvasMargin))         ?? .hex("#E0E0E0")
        self.buttonBackground     = (try? c.decode(ColorRef.self, forKey: .buttonBackground))     ?? blank
        self.buttonForeground     = (try? c.decode(ColorRef.self, forKey: .buttonForeground))     ?? .hex("#000000")
        self.buttonBorder         = (try? c.decode(ColorRef.self, forKey: .buttonBorder))         ?? .hex("#888888")
        self.buttonHilite         = (try? c.decode(ColorRef.self, forKey: .buttonHilite))         ?? .hex("#0A84FF")
        self.fieldBackground      = (try? c.decode(ColorRef.self, forKey: .fieldBackground))      ?? blank
        self.fieldForeground      = (try? c.decode(ColorRef.self, forKey: .fieldForeground))      ?? .hex("#000000")
        self.fieldBorder          = (try? c.decode(ColorRef.self, forKey: .fieldBorder))          ?? .hex("#888888")
        self.shapeFillDefault     = (try? c.decode(ColorRef.self, forKey: .shapeFillDefault))     ?? blank
        self.shapeStrokeDefault   = (try? c.decode(ColorRef.self, forKey: .shapeStrokeDefault))   ?? .hex("#000000")
        self.accent               = (try? c.decode(ColorRef.self, forKey: .accent))               ?? .hex("#0A84FF")
        self.selectionFill        = (try? c.decode(ColorRef.self, forKey: .selectionFill))        ?? .hex("#0A84FF40")
        self.selectionStroke      = (try? c.decode(ColorRef.self, forKey: .selectionStroke))      ?? .hex("#0A84FF")
        self.toolbarBackground    = (try? c.decode(ColorRef.self, forKey: .toolbarBackground))    ?? .systemKey("controlBackgroundColor")
        self.inspectorBackground  = (try? c.decode(ColorRef.self, forKey: .inspectorBackground))  ?? .systemKey("controlBackgroundColor")
        self.panelDivider         = (try? c.decode(ColorRef.self, forKey: .panelDivider))         ?? .systemKey("separatorColor")

        self.defaultFontFamily    = (try? c.decode(String.self, forKey: .defaultFontFamily)) ?? "Helvetica"
        self.defaultFontSize      = (try? c.decode(Double.self, forKey: .defaultFontSize))   ?? 14
        self.headingFontFamily    = (try? c.decode(String.self, forKey: .headingFontFamily)) ?? "Helvetica"
        self.headingFontSize      = (try? c.decode(Double.self, forKey: .headingFontSize))   ?? 18
        self.monospaceFontFamily  = (try? c.decode(String.self, forKey: .monospaceFontFamily)) ?? "Menlo"
        self.labelFontSize        = (try? c.decode(Double.self, forKey: .labelFontSize))     ?? 11

        self.cornerRadiusSmall    = (try? c.decode(Double.self, forKey: .cornerRadiusSmall))  ?? 2
        self.cornerRadiusMedium   = (try? c.decode(Double.self, forKey: .cornerRadiusMedium)) ?? 6
        self.cornerRadiusLarge    = (try? c.decode(Double.self, forKey: .cornerRadiusLarge))  ?? 12
        self.spacingUnit          = (try? c.decode(Double.self, forKey: .spacingUnit))        ?? 8
        self.strokeWidthThin      = (try? c.decode(Double.self, forKey: .strokeWidthThin))    ?? 1
        self.strokeWidthMedium    = (try? c.decode(Double.self, forKey: .strokeWidthMedium))  ?? 2
        self.shadowOpacity        = (try? c.decode(Double.self, forKey: .shadowOpacity))      ?? 0.15
        self.shadowRadius         = (try? c.decode(Double.self, forKey: .shadowRadius))       ?? 4

        self.scriptTheme          = (try? c.decode(HypeScriptTheme.self, forKey: .scriptTheme)) ?? HypeScriptTheme.defaultLight
    }

    // MARK: Convenience

    /// Produce a duplicate ready to be added to `HypeDocument.themes`:
    /// new id, isBuiltIn=false, basedOn = self.name, name = candidate
    /// (caller is responsible for ensuring uniqueness against existing
    /// themes in scope).
    public func duplicate(named candidate: String) -> HypeTheme {
        var copy = self
        copy.id = UUID()
        copy.isBuiltIn = false
        copy.basedOn = self.name
        copy.name = candidate
        copy.createdAt = Date()
        copy.modifiedAt = Date()
        return copy
    }
}

// MARK: - HypeScriptTheme

/// Syntax-highlighting palette for the HypeTalk script editor and
/// any other code-display surface (Modelfile preview, JSON viewer,
/// etc.). Keeping this nested inside `HypeTheme` means a single
/// theme drives both the visual surface AND the editor look so
/// stacks present a coherent identity.
public struct HypeScriptTheme: Codable, Sendable, Equatable, Hashable {
    public var background: ColorRef
    public var foreground: ColorRef
    public var keyword: ColorRef           // on, end, if, then, repeat, etc.
    public var command: ColorRef           // go, put, set, ask, answer, etc.
    public var stringLiteral: ColorRef     // "hello"
    public var numberLiteral: ColorRef     // 42, 3.14
    public var comment: ColorRef           // -- this is a comment
    public var identifier: ColorRef        // variable / field / button names
    public var property: ColorRef          // .text, .visible, restitution
    public var operatorSymbol: ColorRef    // = + - * / & < > and or not
    public var bracket: ColorRef           // ( ) [ ] { }
    public var error: ColorRef             // squiggle / underline color
    public var selection: ColorRef         // selected-text background
    public var lineNumber: ColorRef        // gutter
    public var currentLine: ColorRef       // active-line subtle highlight
    public var fontSize: Double
    public var lineSpacing: Double         // multiplier (1.0 = no extra)

    public init(
        background: ColorRef,
        foreground: ColorRef,
        keyword: ColorRef,
        command: ColorRef,
        stringLiteral: ColorRef,
        numberLiteral: ColorRef,
        comment: ColorRef,
        identifier: ColorRef,
        property: ColorRef,
        operatorSymbol: ColorRef,
        bracket: ColorRef,
        error: ColorRef,
        selection: ColorRef,
        lineNumber: ColorRef,
        currentLine: ColorRef,
        fontSize: Double = 13,
        lineSpacing: Double = 1.15
    ) {
        self.background = background
        self.foreground = foreground
        self.keyword = keyword
        self.command = command
        self.stringLiteral = stringLiteral
        self.numberLiteral = numberLiteral
        self.comment = comment
        self.identifier = identifier
        self.property = property
        self.operatorSymbol = operatorSymbol
        self.bracket = bracket
        self.error = error
        self.selection = selection
        self.lineNumber = lineNumber
        self.currentLine = currentLine
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
    }

    private enum CodingKeys: String, CodingKey {
        case background, foreground, keyword, command, stringLiteral, numberLiteral
        case comment, identifier, property, operatorSymbol, bracket, error
        case selection, lineNumber, currentLine, fontSize, lineSpacing
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.background      = (try? c.decode(ColorRef.self, forKey: .background)) ?? .hex("#FFFFFF")
        self.foreground      = (try? c.decode(ColorRef.self, forKey: .foreground)) ?? .hex("#1A1A1A")
        self.keyword         = (try? c.decode(ColorRef.self, forKey: .keyword)) ?? .hex("#7E1FFA")
        self.command         = (try? c.decode(ColorRef.self, forKey: .command)) ?? .hex("#0A66E0")
        self.stringLiteral   = (try? c.decode(ColorRef.self, forKey: .stringLiteral)) ?? .hex("#A3174F")
        self.numberLiteral   = (try? c.decode(ColorRef.self, forKey: .numberLiteral)) ?? .hex("#1F8F4F")
        self.comment         = (try? c.decode(ColorRef.self, forKey: .comment)) ?? .hex("#727272")
        self.identifier      = (try? c.decode(ColorRef.self, forKey: .identifier)) ?? .hex("#1A1A1A")
        self.property        = (try? c.decode(ColorRef.self, forKey: .property)) ?? .hex("#0E5A99")
        self.operatorSymbol  = (try? c.decode(ColorRef.self, forKey: .operatorSymbol)) ?? .hex("#1A1A1A")
        self.bracket         = (try? c.decode(ColorRef.self, forKey: .bracket)) ?? .hex("#555555")
        self.error           = (try? c.decode(ColorRef.self, forKey: .error)) ?? .hex("#D32F2F")
        self.selection       = (try? c.decode(ColorRef.self, forKey: .selection)) ?? .hex("#0A84FF40")
        self.lineNumber      = (try? c.decode(ColorRef.self, forKey: .lineNumber)) ?? .hex("#999999")
        self.currentLine     = (try? c.decode(ColorRef.self, forKey: .currentLine)) ?? .hex("#F0F0F4")
        self.fontSize        = (try? c.decode(Double.self, forKey: .fontSize)) ?? 13
        self.lineSpacing     = (try? c.decode(Double.self, forKey: .lineSpacing)) ?? 1.15
    }

    /// Light-mode default — what the script editor used before
    /// theming existed. Kept as a public static so other code can
    /// reach it without going through BuiltInThemes.
    ///
    /// All token/background pairs meet WCAG AA (4.5:1 for normal
    /// text, 3:1 for line-number gutter punctuation). Verified by
    /// `ThemeContrastAuditTests`.
    public static let defaultLight = HypeScriptTheme(
        background:    .hex("#FFFFFF"),
        foreground:    .hex("#1A1A1A"),
        keyword:       .hex("#7E1FFA"),
        command:       .hex("#0A66E0"),
        stringLiteral: .hex("#A3174F"),
        numberLiteral: .hex("#1D874A"),  // darkened from #1F8F4F to pass AA on white
        comment:       .hex("#727272"),
        identifier:    .hex("#1A1A1A"),
        property:      .hex("#0E5A99"),
        operatorSymbol: .hex("#1A1A1A"),
        bracket:       .hex("#555555"),
        error:         .hex("#D32F2F"),
        selection:     .hex("#0A84FF40"),
        lineNumber:    .hex("#949494"),  // darkened from #999999 to pass 3:1 on white
        currentLine:   .hex("#F0F0F4")
    )

    public static let defaultDark = HypeScriptTheme(
        background:    .hex("#1E1E22"),
        foreground:    .hex("#E8E8EC"),
        keyword:       .hex("#C792EA"),
        command:       .hex("#82AAFF"),
        stringLiteral: .hex("#F78C6C"),
        numberLiteral: .hex("#A5E844"),
        comment:       .hex("#848491"),  // lightened from #7C7C8A to pass AA on dark bg
        identifier:    .hex("#E8E8EC"),
        property:      .hex("#89DDFF"),
        operatorSymbol: .hex("#E8E8EC"),
        bracket:       .hex("#A0A0B0"),
        error:         .hex("#FF6B6B"),
        selection:     .hex("#0A84FF55"),
        lineNumber:    .hex("#686876"),  // lightened from #5A5A66 to pass 3:1
        currentLine:   .hex("#26262E")
    )
}

// MARK: - SwiftUI shortcuts

#if canImport(SwiftUI)
public extension HypeTheme {
    var bodyFont: Font {
        .custom(defaultFontFamily, size: defaultFontSize)
    }
    var headingFont: Font {
        .custom(headingFontFamily, size: headingFontSize)
    }
    var labelFont: Font {
        .custom(defaultFontFamily, size: labelFontSize)
    }
    var monoFont: Font {
        .custom(monospaceFontFamily, size: defaultFontSize)
    }

    /// The `ColorScheme` that should govern any subtree painted on
    /// this theme's chrome surfaces (inspector, toolbar, panels).
    ///
    /// **Why this exists**: SwiftUI's `Color.primary` /
    /// `NSColor.labelColor` resolve based on the active
    /// `colorScheme`. By default, the scheme reflects the macOS
    /// appearance — but when we paint a theme-supplied LIGHT
    /// background (e.g. Sunset's `#FFE7CB` cream) while macOS is
    /// in dark mode, the labels stay near-white and become
    /// illegible. Forcing the subtree's colorScheme based on the
    /// theme's inspector-background luminance keeps text readable
    /// regardless of OS appearance.
    ///
    /// Light theme bg → `.light` scheme → near-black labels.
    /// Dark theme bg → `.dark` scheme → near-white labels.
    var chromeColorScheme: ColorScheme {
        colorSchemeForBackground(inspectorBackground)
    }

    /// Same idea but for the canvas surround (toolbar / status
    /// strip / AI chat header). Computed from `toolbarBackground`
    /// because those panels are tinted with that token.
    var toolbarColorScheme: ColorScheme {
        colorSchemeForBackground(toolbarBackground)
    }

    /// Pick a `ColorScheme` whose default text color contrasts
    /// well with `bg`. System-key backgrounds are passed through
    /// to the OS — return `.light` as a stable default since the
    /// system color resolves dynamically anyway.
    func colorSchemeForBackground(_ bg: ColorRef) -> ColorScheme {
        guard case .hex(let hex) = bg,
              let rgb = ColorContrast.parseHex(hex)
        else { return .light }
        let lum = ColorContrast.relativeLuminance(r: rgb.r, g: rgb.g, b: rgb.b)
        // Threshold 0.5 maps brightness to scheme. Tuned against
        // the built-in palette: Sunset (0.85) → light, Modern Dark
        // (0.07) → dark, Neon (0.005) → dark.
        return lum > 0.5 ? .light : .dark
    }
}
#endif
