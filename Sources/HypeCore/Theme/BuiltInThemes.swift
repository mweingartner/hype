import Foundation

/// The application's built-in theme catalog. Read-only at runtime —
/// the Theme Designer must reject edits and deletions when
/// `theme.isBuiltIn == true`. Users wanting to customize start by
/// duplicating one of these.
public enum BuiltInThemes {

    /// The absolute fallback. New stacks have `stack.themeName ==
    /// fallbackName`, and the cascade resolver returns this theme
    /// when every level of the cascade is missing or unresolved.
    /// Following the system appearance is the right behavior for
    /// most users until they opt into a stylized look.
    public static let fallbackName = "System"

    public static let all: [HypeTheme] = [
        system,
        classicHyperCard,
        modernLight,
        modernDark,
        sunset,
        neon,
        liquidGlass,
    ]

    /// Look up a built-in theme by case-insensitive name. Returns
    /// nil for unknown names; callers should then look at user
    /// themes on the document.
    public static func find(named: String) -> HypeTheme? {
        all.first { $0.name.lowercased() == named.lowercased() }
    }

    // MARK: - 1. System (follows macOS appearance)

    public static let system = HypeTheme(
        id: stableID("builtin.system"),
        name: "System",
        isBuiltIn: true,
        cardBackground:       .systemKey("textBackgroundColor"),
        cardForeground:       .systemKey("textColor"),
        backgroundFill:       .systemKey("controlBackgroundColor"),
        canvasMargin:         .systemKey("windowBackgroundColor"),
        buttonBackground:     .systemKey("controlColor"),
        buttonForeground:     .systemKey("controlTextColor"),
        buttonBorder:         .systemKey("separatorColor"),
        buttonHilite:         .systemKey("selectedContentBackgroundColor"),
        fieldBackground:      .systemKey("textBackgroundColor"),
        fieldForeground:      .systemKey("textColor"),
        fieldBorder:          .systemKey("separatorColor"),
        shapeFillDefault:     .hex("#FFFFFF"),
        shapeStrokeDefault:   .systemKey("labelColor"),
        accent:               .systemKey("accentColor"),
        selectionFill:        .hex("#0A84FF40"),
        selectionStroke:      .systemKey("accentColor"),
        toolbarBackground:    .systemKey("controlBackgroundColor"),
        inspectorBackground:  .systemKey("controlBackgroundColor"),
        panelDivider:         .systemKey("separatorColor"),
        defaultFontFamily:    "Helvetica",
        defaultFontSize:      14,
        headingFontFamily:    "Helvetica",
        headingFontSize:      18,
        monospaceFontFamily:  "Menlo",
        labelFontSize:        11,
        cornerRadiusSmall:    3,
        cornerRadiusMedium:   6,
        cornerRadiusLarge:    10,
        spacingUnit:          8,
        strokeWidthThin:      1,
        strokeWidthMedium:    2,
        shadowOpacity:        0.10,
        shadowRadius:         3,
        scriptTheme: HypeScriptTheme.defaultLight
    )

    // MARK: - 2. Classic HyperCard

    /// Tribute to the original. Black-and-white, sharp corners, no
    /// shadows, Geneva-ish pixel-aware feel. Honored references:
    /// Apple's HyperCard 2.x manual, Decker, the World Wide Web of
    /// HyperCard fan stacks.
    public static let classicHyperCard = HypeTheme(
        id: stableID("builtin.classichypercard"),
        name: "Classic HyperCard",
        isBuiltIn: true,
        cardBackground:       .hex("#FFFFFF"),
        cardForeground:       .hex("#000000"),
        backgroundFill:       .hex("#FFFFFF"),
        canvasMargin:         .hex("#DDDDDD"),
        buttonBackground:     .hex("#FFFFFF"),
        buttonForeground:     .hex("#000000"),
        buttonBorder:         .hex("#000000"),
        buttonHilite:         .hex("#000000"),
        fieldBackground:      .hex("#FFFFFF"),
        fieldForeground:      .hex("#000000"),
        fieldBorder:          .hex("#000000"),
        shapeFillDefault:     .hex("#FFFFFF"),
        shapeStrokeDefault:   .hex("#000000"),
        accent:               .hex("#000000"),
        selectionFill:        .hex("#00000022"),
        selectionStroke:      .hex("#000000"),
        toolbarBackground:    .hex("#DDDDDD"),
        inspectorBackground:  .hex("#EEEEEE"),
        panelDivider:         .hex("#000000"),
        defaultFontFamily:    "Geneva",
        defaultFontSize:      12,
        headingFontFamily:    "Geneva",
        headingFontSize:      14,
        monospaceFontFamily:  "Monaco",
        labelFontSize:        10,
        cornerRadiusSmall:    0,
        cornerRadiusMedium:   0,
        cornerRadiusLarge:    0,
        spacingUnit:          6,
        strokeWidthThin:      1,
        strokeWidthMedium:    2,
        shadowOpacity:        0,
        shadowRadius:         0,
        scriptTheme: HypeScriptTheme(
            background:    .hex("#FFFFFF"),
            foreground:    .hex("#000000"),
            keyword:       .hex("#000000"),
            command:       .hex("#000000"),
            stringLiteral: .hex("#000000"),
            numberLiteral: .hex("#000000"),
            comment:       .hex("#666666"),
            identifier:    .hex("#000000"),
            property:      .hex("#000000"),
            operatorSymbol: .hex("#000000"),
            bracket:       .hex("#000000"),
            error:         .hex("#FF0000"),
            selection:     .hex("#00000033"),
            lineNumber:    .hex("#888888"),
            currentLine:   .hex("#F0F0F0"),
            fontSize:      12,
            lineSpacing:   1.20
        )
    )

    // MARK: - 3. Modern Light

    public static let modernLight = HypeTheme(
        id: stableID("builtin.modernlight"),
        name: "Modern Light",
        isBuiltIn: true,
        cardBackground:       .hex("#FAFAFB"),
        cardForeground:       .hex("#1A1A22"),
        backgroundFill:       .hex("#FFFFFF"),
        canvasMargin:         .hex("#EFEFF3"),
        buttonBackground:     .hex("#FFFFFF"),
        buttonForeground:     .hex("#1A1A22"),
        buttonBorder:         .hex("#D8D8E0"),
        buttonHilite:         .hex("#0A84FF"),
        fieldBackground:      .hex("#FFFFFF"),
        fieldForeground:      .hex("#1A1A22"),
        fieldBorder:          .hex("#D8D8E0"),
        shapeFillDefault:     .hex("#FFFFFF"),
        shapeStrokeDefault:   .hex("#1A1A22"),
        accent:               .hex("#0A84FF"),
        selectionFill:        .hex("#0A84FF22"),
        selectionStroke:      .hex("#0A84FF"),
        toolbarBackground:    .hex("#F4F4F8"),
        inspectorBackground:  .hex("#F8F8FB"),
        panelDivider:         .hex("#E2E2E8"),
        defaultFontFamily:    "Helvetica Neue",
        defaultFontSize:      14,
        headingFontFamily:    "Helvetica Neue",
        headingFontSize:      18,
        monospaceFontFamily:  "Menlo",
        labelFontSize:        11,
        cornerRadiusSmall:    4,
        cornerRadiusMedium:   8,
        cornerRadiusLarge:    14,
        spacingUnit:          8,
        strokeWidthThin:      1,
        strokeWidthMedium:    2,
        shadowOpacity:        0.12,
        shadowRadius:         5,
        scriptTheme: HypeScriptTheme.defaultLight
    )

    // MARK: - 4. Modern Dark

    public static let modernDark = HypeTheme(
        id: stableID("builtin.moderndark"),
        name: "Modern Dark",
        isBuiltIn: true,
        cardBackground:       .hex("#22222B"),
        cardForeground:       .hex("#E8E8EC"),
        backgroundFill:       .hex("#1B1B22"),
        canvasMargin:         .hex("#13131A"),
        buttonBackground:     .hex("#2E2E38"),
        buttonForeground:     .hex("#E8E8EC"),
        buttonBorder:         .hex("#404048"),
        buttonHilite:         .hex("#0A84FF"),
        fieldBackground:      .hex("#1A1A22"),
        fieldForeground:      .hex("#E8E8EC"),
        fieldBorder:          .hex("#404048"),
        shapeFillDefault:     .hex("#2E2E38"),
        shapeStrokeDefault:   .hex("#E8E8EC"),
        accent:               .hex("#0A84FF"),
        selectionFill:        .hex("#0A84FF44"),
        selectionStroke:      .hex("#0A84FF"),
        toolbarBackground:    .hex("#1B1B22"),
        inspectorBackground:  .hex("#1F1F28"),
        panelDivider:         .hex("#33333D"),
        defaultFontFamily:    "Helvetica Neue",
        defaultFontSize:      14,
        headingFontFamily:    "Helvetica Neue",
        headingFontSize:      18,
        monospaceFontFamily:  "Menlo",
        labelFontSize:        11,
        cornerRadiusSmall:    4,
        cornerRadiusMedium:   8,
        cornerRadiusLarge:    14,
        spacingUnit:          8,
        strokeWidthThin:      1,
        strokeWidthMedium:    2,
        shadowOpacity:        0.30,
        shadowRadius:         6,
        scriptTheme: HypeScriptTheme.defaultDark
    )

    // MARK: - 5. Sunset

    public static let sunset = HypeTheme(
        id: stableID("builtin.sunset"),
        name: "Sunset",
        isBuiltIn: true,
        cardBackground:       .hex("#FFF1E0"),
        cardForeground:       .hex("#3D1F1A"),
        backgroundFill:       .hex("#FFE2C0"),
        canvasMargin:         .hex("#F8D2A8"),
        buttonBackground:     .hex("#FFB880"),
        buttonForeground:     .hex("#3D1F1A"),
        buttonBorder:         .hex("#C46A2E"),
        buttonHilite:         .hex("#E0501C"),
        fieldBackground:      .hex("#FFFAF0"),
        fieldForeground:      .hex("#3D1F1A"),
        fieldBorder:          .hex("#C46A2E"),
        shapeFillDefault:     .hex("#FFC59A"),
        shapeStrokeDefault:   .hex("#7A331B"),
        accent:               .hex("#E0501C"),
        selectionFill:        .hex("#E0501C2A"),
        selectionStroke:      .hex("#A33214"),
        toolbarBackground:    .hex("#F8D2A8"),
        inspectorBackground:  .hex("#FFE7CB"),
        panelDivider:         .hex("#C46A2E"),
        defaultFontFamily:    "Avenir Next",
        defaultFontSize:      14,
        headingFontFamily:    "Avenir Next",
        headingFontSize:      20,
        monospaceFontFamily:  "Menlo",
        labelFontSize:        11,
        cornerRadiusSmall:    6,
        cornerRadiusMedium:   12,
        cornerRadiusLarge:    20,
        spacingUnit:          10,
        strokeWidthThin:      1,
        strokeWidthMedium:    2,
        shadowOpacity:        0.20,
        shadowRadius:         8,
        scriptTheme: HypeScriptTheme(
            background:    .hex("#FFF7EC"),
            foreground:    .hex("#3D1F1A"),
            keyword:       .hex("#A33214"),
            command:       .hex("#AB5D28"),  // darkened from #C46A2E for AA on cream
            stringLiteral: .hex("#7A331B"),
            numberLiteral: .hex("#3F7A2C"),
            comment:       .hex("#876B52"),  // darkened from #9A7A5E for AA
            identifier:    .hex("#3D1F1A"),
            property:      .hex("#A33214"),
            operatorSymbol: .hex("#3D1F1A"),
            bracket:       .hex("#7A331B"),
            error:         .hex("#D02020"),
            selection:     .hex("#E0501C30"),
            lineNumber:    .hex("#AC8768"),  // darkened from #B59478 for 3:1 gutter
            currentLine:   .hex("#FFEBD0")
        )
    )

    // MARK: - 6. Neon

    public static let neon = HypeTheme(
        id: stableID("builtin.neon"),
        name: "Neon",
        isBuiltIn: true,
        cardBackground:       .hex("#0F0F1A"),
        cardForeground:       .hex("#F0F0FF"),
        backgroundFill:       .hex("#0A0A12"),
        canvasMargin:         .hex("#000008"),
        buttonBackground:     .hex("#1F1B33"),
        buttonForeground:     .hex("#FF36C7"),
        buttonBorder:         .hex("#FF36C7"),
        buttonHilite:         .hex("#36F2FF"),
        fieldBackground:      .hex("#15131F"),
        fieldForeground:      .hex("#36F2FF"),
        fieldBorder:          .hex("#36F2FF"),
        shapeFillDefault:     .hex("#1F1B33"),
        shapeStrokeDefault:   .hex("#FF36C7"),
        accent:               .hex("#FF36C7"),
        selectionFill:        .hex("#36F2FF40"),
        selectionStroke:      .hex("#36F2FF"),
        toolbarBackground:    .hex("#0A0A12"),
        inspectorBackground:  .hex("#13131F"),
        panelDivider:         .hex("#FF36C766"),
        defaultFontFamily:    "Menlo",
        defaultFontSize:      14,
        headingFontFamily:    "Menlo",
        headingFontSize:      18,
        monospaceFontFamily:  "Menlo",
        labelFontSize:        11,
        cornerRadiusSmall:    2,
        cornerRadiusMedium:   4,
        cornerRadiusLarge:    8,
        spacingUnit:          8,
        strokeWidthThin:      1,
        strokeWidthMedium:    2,
        shadowOpacity:        0.50,
        shadowRadius:         12,
        scriptTheme: HypeScriptTheme(
            background:    .hex("#0F0F1A"),
            foreground:    .hex("#F0F0FF"),
            keyword:       .hex("#FF36C7"),
            command:       .hex("#36F2FF"),
            stringLiteral: .hex("#A8FF60"),
            numberLiteral: .hex("#FFD700"),
            comment:       .hex("#7A7A9D"),  // lightened from #5A5A7A for AA on near-black
            identifier:    .hex("#F0F0FF"),
            property:      .hex("#36F2FF"),
            operatorSymbol: .hex("#FF36C7"),
            bracket:       .hex("#A8FF60"),
            error:         .hex("#FF5050"),
            selection:     .hex("#36F2FF44"),
            lineNumber:    .hex("#5C5C91"),  // lightened from #3A3A5C for 3:1 gutter
            currentLine:   .hex("#1A1828")
        )
    )

    // MARK: - 7. Liquid Glass
    //
    // Apple's macOS Tahoe / iOS 26 design language: translucent
    // surfaces with vibrancy, generous corner radii (16pt), specular
    // highlights along the top edge of every control to read as a
    // glass bevel, and an accent palette that adapts to the system
    // tint. CG renderers can't run a live blur — that's
    // NSVisualEffectView's job — but the theme's
    // `usesGlassMaterial = true` flag tells the renderers to paint
    // a low-alpha fill plus the highlight gradient that approximates
    // the look. SwiftUI chrome that already wraps the canvas (the
    // inspector, panels) gets actual material treatment via
    // `.background(.regularMaterial)` keyed off the same flag.
    //
    // Color values are deliberately tuned to read on top of any
    // backdrop the user sets: the card surface is a slightly-warm
    // semi-translucent off-white (`#F8F8FAB8` — 72% alpha) so a
    // colorful background fills shows through. The accent matches
    // Apple's default-tint blue so action buttons feel native. Text
    // colors are the contrast-aware equivalents of the underlying
    // tinted surfaces.
    public static let liquidGlass = HypeTheme(
        id: stableID("builtin.liquidglass"),
        name: "Liquid Glass",
        isBuiltIn: true,
        cardBackground:       .hex("#F8F8FAB8"),    // 72% off-white
        cardForeground:       .hex("#1C1C1E"),      // near-black ink
        backgroundFill:       .hex("#EFEFF4D9"),    // 85% pale gray
        canvasMargin:         .systemKey("windowBackgroundColor"),
        buttonBackground:     .hex("#FFFFFFA6"),    // 65% white — glass pill
        buttonForeground:     .hex("#1C1C1E"),
        buttonBorder:         .hex("#FFFFFF66"),    // 40% white sheen ring
        buttonHilite:         .hex("#0A84FF"),      // Apple system blue
        fieldBackground:      .hex("#FFFFFFCC"),    // 80% white frosted
        fieldForeground:      .hex("#1C1C1E"),
        fieldBorder:          .hex("#0000001A"),    // 10% black hairline
        shapeFillDefault:     .hex("#FFFFFFA6"),
        shapeStrokeDefault:   .hex("#0000001F"),    // 12% black
        accent:               .hex("#0A84FF"),
        selectionFill:        .hex("#0A84FF33"),    // 20% accent
        selectionStroke:      .hex("#0A84FF"),
        toolbarBackground:    .systemKey("controlBackgroundColor"),
        inspectorBackground:  .systemKey("controlBackgroundColor"),
        panelDivider:         .hex("#0000001A"),    // 10% black
        defaultFontFamily:    "SF Pro Text",
        defaultFontSize:      14,
        headingFontFamily:    "SF Pro Display",
        headingFontSize:      18,
        monospaceFontFamily:  "SF Mono",
        labelFontSize:        11,
        cornerRadiusSmall:    8,
        cornerRadiusMedium:   12,
        cornerRadiusLarge:    18,                   // matches Tahoe / iOS 26
        spacingUnit:          8,
        strokeWidthThin:      0.5,                  // hairline, not 1pt
        strokeWidthMedium:    1,
        shadowOpacity:        0.18,
        shadowRadius:         12,
        usesGlassMaterial:    true,
        scriptTheme: HypeScriptTheme.defaultLight
    )

    // MARK: - Stable IDs

    /// Built-in themes need stable UUIDs so they round-trip through
    /// JSON consistently across app launches and so user references
    /// to them (by id, not just name) survive renames in future
    /// versions of the catalog. We derive a deterministic UUID from
    /// a string seed.
    private static func stableID(_ seed: String) -> UUID {
        // FNV-1a hash truncated/expanded into a UUID byte array.
        // Not cryptographic; just a deterministic mapping.
        let bytes = Array(seed.utf8)
        var hash: UInt64 = 0xcbf29ce484222325
        for b in bytes {
            hash ^= UInt64(b)
            hash &*= 0x100000001b3
        }
        var uuidBytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 {
            uuidBytes[i] = UInt8((hash >> (8 * (i % 8))) & 0xFF)
            // Also mix in the seed character to avoid collapsing
            // similar seeds to the same UUID.
            uuidBytes[i] ^= bytes.indices.contains(i) ? bytes[i] : 0
        }
        // Set UUID variant + version bits per RFC 4122 v4.
        uuidBytes[6] = (uuidBytes[6] & 0x0F) | 0x40
        uuidBytes[8] = (uuidBytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            uuidBytes[0],  uuidBytes[1],  uuidBytes[2],  uuidBytes[3],
            uuidBytes[4],  uuidBytes[5],  uuidBytes[6],  uuidBytes[7],
            uuidBytes[8],  uuidBytes[9],  uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
    }
}
