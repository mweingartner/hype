import Foundation

/// Single source of truth for part-property dispatch across the
/// HypeTalk and AI script surfaces (`control-property-consistency`,
/// design.md Decision 1).
///
/// The registry **gates and resolves**; the hand-written GET/SET
/// switches in `Interpreter.swift` (and, in a later work package,
/// `HypeToolExecutor.swift`) **implement**. Every property access
/// runs one precomputed dictionary lookup on the already-lowercased
/// name; the result tells the caller whether to proceed (and with
/// which canonical case-label string), silently no-op, or throw a
/// specific, name-bearing error.
///
/// Two dispatch mechanisms live here, covering two different shapes
/// of property:
/// - **Regular properties** (`descriptors`) — one canonical name plus
///   a fixed alias list, restricted (or not) to a fixed set of part
///   types. The overwhelming majority of properties are this shape:
///   `fillColor`, `gaugeMin`, `mapCenterLat`, etc.
/// - **Polymorphic bare words** (`polymorphicResolution`) — a small,
///   hand-enumerated set of ambiguous short words (`value`, `min`,
///   `max`, `step`, `style`, `color`, `tint`, `loop`, `volume`,
///   `autoplay`, `duration`, `prompt`, `total`, `items`, `decimals`,
///   `background`, `on`) whose *meaning* depends on the target part's
///   type. These remap to a regular canonical per type (e.g. `min` on
///   a gauge means `gaugeMin`) or error when the type has no meaning
///   for that word. This mechanism is checked first — it is always
///   definitive when it matches (never falls through to `descriptors`,
///   even when the result is an error).
///
/// Immutable, `Sendable`, value types only — no closures capturing
/// `env`/`document`/`context`, no locks, no lazy mutable state
/// (Condition 9). Pure data plus pure functions.
public enum PartPropertyRegistry {

    // MARK: - Types

    /// Which part types (and, optionally, which style variant of that
    /// type) a property applies to.
    public struct Applicability: Sendable, Equatable {
        public let types: Set<PartType>
        /// Extra constraint applied only when `types` contains `.button`.
        /// Reserved for future finer-grained gating; no P1 descriptor
        /// populates this yet.
        public let buttonStyles: Set<ButtonStyle>?
        /// Extra constraint applied only when `types` contains `.field`.
        /// Reserved for future finer-grained gating; no P1 descriptor
        /// populates this yet (the bare `prompt` bare-word dispatch
        /// enforces its field-style constraint directly in
        /// `polymorphicResolution` instead, since that word's long-form
        /// alias `searchPrompt` deliberately stays style-unconstrained —
        /// "long names always work on their own type").
        public let fieldStyles: Set<FieldStyle>?

        public init(types: Set<PartType>, buttonStyles: Set<ButtonStyle>? = nil, fieldStyles: Set<FieldStyle>? = nil) {
            self.types = types
            self.buttonStyles = buttonStyles
            self.fieldStyles = fieldStyles
        }
    }

    public enum Mutability: Sendable, Equatable {
        /// Both GET and SET are meaningful (subject to applicability).
        case getSet
        /// GET reads a real value; SET always errors — `resolveSet`
        /// short-circuits to `.readOnly` regardless of applicability.
        case readOnly
        /// A declared no-op: GET returns its hardcoded classic answer
        /// (a real switch case, unaffected by this enum); SET silently
        /// succeeds without mutation — `resolveSet` short-circuits to
        /// `.noOp` regardless of applicability. Exists so the 11
        /// classic HyperCard field stubs + `scroll`/`scrollpos` never
        /// reach the unknown-property error (Condition 3).
        case noOpStub
    }

    /// Informational value-shape tag. `.color` is the one kind with
    /// real dispatch consequences in this work package — SET routes
    /// `.color` properties through `HexColor.normalized(_:)`.
    public enum ValueKind: Sendable, Equatable {
        case string, number, boolean, color, pair, enumeration, json
    }

    /// One property concept: a canonical dispatch name, its aliases,
    /// and the metadata that drives gating, docs, and
    /// `list_all_properties`.
    public struct Descriptor: Sendable {
        /// The lowercase key the GET/SET switches are keyed on.
        public let canonical: String
        /// Additional lowercase spellings that resolve to the same
        /// canonical. By construction the GET alias set and the SET
        /// alias set are identical (alias symmetry law) — mutability
        /// and applicability differences are expressed via the
        /// `Mutability` / `Applicability` fields, not by omitting an
        /// alias from one verb.
        public let aliases: [String]
        /// `nil` = universal (no restriction) for GET.
        public let getApplicability: Applicability?
        /// `nil` = universal (no restriction) for SET.
        public let setApplicability: Applicability?
        public let mutability: Mutability
        public let kind: ValueKind
        /// `false` for the small set of HypeTalk-only legacy
        /// properties not offered on the curated AI tool surface
        /// (`htmlContent`, the menu-item properties).
        public let aiExposed: Bool
        /// Listed under the "legacy / not scriptable" note in
        /// `list_all_properties` and the docs guide rather than the
        /// main table.
        public let legacy: Bool
        public let defaultDescription: String
        public let docSummary: String
        /// Security condition 1 (masking law): `true` for the complete
        /// set of field-body properties that must return `"(masked)"`
        /// instead of their real value when read from a `.field` part
        /// whose `fieldStyle == .secure` — `textContent`, `htmlContent`,
        /// `searchText`. Every alias of a `secureMasked` descriptor
        /// resolves through the SAME masked switch cell on both script
        /// surfaces; there is no per-alias opt-out.
        /// `searchPrompt`/`helpText` are deliberately excluded — they
        /// are author-facing chrome (a placeholder, a tooltip), never
        /// secret-bearing, so they stay plaintext.
        public let secureMasked: Bool

        public init(
            canonical: String,
            aliases: [String],
            getApplicability: Applicability?,
            setApplicability: Applicability?,
            mutability: Mutability,
            kind: ValueKind,
            aiExposed: Bool,
            legacy: Bool,
            defaultDescription: String,
            docSummary: String,
            secureMasked: Bool = false
        ) {
            self.canonical = canonical
            self.aliases = aliases
            self.getApplicability = getApplicability
            self.setApplicability = setApplicability
            self.mutability = mutability
            self.kind = kind
            self.aiExposed = aiExposed
            self.legacy = legacy
            self.defaultDescription = defaultDescription
            self.docSummary = docSummary
            self.secureMasked = secureMasked
        }
    }

    /// The outcome of resolving a (lowered) property name against a
    /// target part, for one verb (GET or SET).
    public enum Resolution: Sendable, Equatable {
        /// Proceed — dispatch the switch on `canonical`.
        case property(canonical: String)
        /// A declared no-op (SET only) — return without mutating.
        case noOp
        /// SET of a read-only property.
        case readOnly(canonical: String)
        /// The name is real but not meaningful for this part's type.
        /// `appliesTo` is a human-readable description of the types
        /// it IS meaningful for (e.g. "gauge" or "stepper, slider, or
        /// gauge") for use in the error copy.
        case notApplicable(name: String, appliesTo: String)
        /// No descriptor (nor polymorphic word) matches this name at
        /// all. `suggestion` is a Levenshtein-nearest candidate name
        /// (distance ≤ 2), filtered to names applicable to the
        /// target's part type, or `nil` when nothing is close enough.
        case unknown(suggestion: String?)
    }

    // MARK: - Error message construction
    //
    // Centralized here (not duplicated per script surface) so
    // HypeTalk (this work package) and the AI tool surface (P2) throw
    // byte-identical copy (Condition 11).

    /// `no such property "X" for <type> "<name>" — did you mean "Y"?`
    /// (the hint clause is omitted when `suggestion` is `nil`).
    public static func unknownPropertyMessage(rawName: String, part: Part, suggestion: String?) -> String {
        let capped = String(rawName.prefix(200))
        let typeWord = part.partType.rawValue
        if let suggestion {
            return "no such property \"\(capped)\" for \(typeWord) \"\(part.name)\" — did you mean \"\(suggestion)\"?"
        }
        return "no such property \"\(capped)\" for \(typeWord) \"\(part.name)\"."
    }

    /// `"X" does not apply to <type> "<name>" — it is a <Y> property.`
    public static func notApplicableMessage(rawName: String, part: Part, appliesTo: String) -> String {
        let capped = String(rawName.prefix(200))
        return "\"\(capped)\" does not apply to \(part.partType.rawValue) \"\(part.name)\" — it is a \(appliesTo) property."
    }

    /// `"X" of <type> "<name>" is read-only.`
    public static func readOnlyMessage(rawName: String, part: Part) -> String {
        let capped = String(rawName.prefix(200))
        return "\"\(capped)\" of \(part.partType.rawValue) \"\(part.name)\" is read-only."
    }

    // MARK: - Descriptor construction helpers

    private static func scoped(_ types: PartType...) -> Applicability {
        Applicability(types: Set(types))
    }

    private static func scoped(_ types: Set<PartType>) -> Applicability {
        Applicability(types: types)
    }

    private static func prop(
        _ canonical: String,
        _ aliases: [String] = [],
        get: Applicability? = nil,
        set: Applicability? = nil,
        mutability: Mutability = .getSet,
        kind: ValueKind = .string,
        aiExposed: Bool = true,
        legacy: Bool = false,
        defaultValue: String = "",
        summary: String = "",
        secureMasked: Bool = false
    ) -> Descriptor {
        Descriptor(
            canonical: canonical,
            aliases: aliases,
            getApplicability: get,
            setApplicability: set,
            mutability: mutability,
            kind: kind,
            aiExposed: aiExposed,
            legacy: legacy,
            defaultDescription: defaultValue,
            docSummary: summary,
            secureMasked: secureMasked
        )
    }

    /// The six AudioKit-driven "music family" part types share one
    /// prefix (`music*`) and one restricted-SET scope throughout the
    /// dispatch tables.
    static let musicFamily: Set<PartType> = [
        .musicPlayer, .pianoKeyboard, .stepSequencer, .musicMixer, .appleMusicBrowser, .musicQueue,
    ]

    // MARK: - Regular descriptors
    //
    // Transcribed 1:1 from the existing GET (`partPropertyValue`) and
    // SET (`applyPartPropertySet`) switch case labels, then the
    // Restricted-SET-applicability / Universal lists from design.md
    // are applied. Bare polymorphic words (value/on/min/max/step/
    // loop/volume/autoplay/duration/tint/prompt/total/items/decimals/
    // style/color/background) are NOT listed here — they're resolved
    // by `polymorphicResolution` before this list is ever consulted.

    public static let descriptors: [Descriptor] = [
        // MARK: Identity / geometry (universal)
        prop("name", summary: "Scripting identity of the part."),
        prop("id", mutability: .readOnly, summary: "The part's stable UUID."),
        prop("shortname", ["short name", "abbrevname", "abbrev name", "abbreviatedname", "abbreviated name"],
             mutability: .readOnly, summary: "Same as name (classic short/long-name form)."),
        prop("longname", ["long name"], mutability: .readOnly,
             summary: "Full descriptive path, e.g. card button \"OK\" of card \"Intro\"."),
        prop("left", ["left_pos"], kind: .number, summary: "Left edge, in points."),
        prop("top", ["top_pos"], kind: .number, summary: "Top edge, in points."),
        prop("width", kind: .number, summary: "Width, in points."),
        prop("height", kind: .number, summary: "Height, in points."),
        prop("right", kind: .number, summary: "Right edge (left + width), in points."),
        prop("bottom", kind: .number, summary: "Bottom edge (top + height), in points."),
        prop("loc", ["location"], kind: .pair, summary: "Geometric center as \"x,y\" (map parts overload `location` for the geocoded place name when set)."),
        prop("rect", ["rectangle"], kind: .pair, summary: "Bounding rectangle as \"left,top,right,bottom\"."),
        prop("topleft", kind: .pair, summary: "Top-left corner as \"x,y\"."),
        prop("bottomright", kind: .pair, summary: "Bottom-right corner as \"x,y\"."),
        prop("rotation", kind: .number, summary: "Rotation in degrees, clockwise (shape/image renderers only)."),
        prop("visible", kind: .boolean, summary: "Whether the part is shown."),
        prop("enabled", kind: .boolean, summary: "Whether the part accepts interaction."),
        prop("number", ["partnumber"], mutability: .readOnly, kind: .number, summary: "1-based position among this card's parts."),
        prop("owner", mutability: .readOnly, summary: "The owning card or background, described."),
        prop("family", kind: .number, legacy: true, summary: "Deprecated grouping number; no renderer consults it."),
        prop("script", summary: "The part's HypeTalk script source."),
        prop("helptext", ["help_text", "tooltip", "tool_tip", "help"], summary: "Hover help bubble text; empty disables it."),
        prop("url", summary: "Web page part's URL, or a button/field's link target."),
        prop("textfont", ["font"], summary: "Font family name."),
        prop("textsize", kind: .number, summary: "Text point size."),
        prop("textstyle", ["text_style"], kind: .enumeration, summary: "Comma-separated style flags, e.g. \"bold, italic\"."),
        prop("textalign", kind: .enumeration, summary: "\"left\", \"center\", or \"right\"."),
        prop("fontcolor", ["font_color", "textcolor", "text_color"], kind: .color,
             summary: "Foreground text color; empty means auto contrast-aware color."),
        prop("textheight", kind: .number, summary: "Line height (derived from textSize)."),
        prop("centered", kind: .boolean, summary: "Whether textAlign is center."),
        prop("filled", mutability: .readOnly, kind: .boolean, summary: "Whether a shape currently has a non-transparent fill."),
        prop("linesize", kind: .number, summary: "Stroke width (alias view of strokeWidth)."),
        prop("textcontent", ["text", "contents"], kind: .string,
             summary: "The part's text — masked to \"(masked)\" when reading a .secure field.",
             secureMasked: true),
        prop("animating", mutability: .readOnly, kind: .boolean, summary: "Whether a GIF or tween is currently animating this part."),
        prop("htmlcontent", ["html_content"], aiExposed: false, legacy: true,
             summary: "Dormant; no renderer consumes this field. Masked to \"(masked)\" when reading a .secure field, same as textContent.",
             secureMasked: true),
        prop("size", kind: .pair, summary: "Geometry pair \"width,height\" — distinct from textSize."),
        prop("type", mutability: .readOnly, kind: .enumeration, summary: "The part's type, as its stable rawValue (e.g. \"gauge\")."),
        prop("marked", summary: "Card property only — always errors when targeting a part (H4)."),

        // MARK: Style / shape (mostly universal; field/button/image flags restricted below)
        prop("shapetype", ["shape_type"], kind: .enumeration, summary: "Shape variant: rectangle, roundRect, oval, line, freeform."),
        prop("fillcolor", ["fill_color"], kind: .color, summary: "Interior fill color of a drawn shape."),
        prop("strokecolor", ["stroke_color"], kind: .color, summary: "Outline color of a drawn shape."),
        prop("strokewidth", ["stroke_width"], kind: .number, summary: "Outline thickness, in points."),
        prop("cornerradius", ["corner_radius"], kind: .number, summary: "Rounded-rect corner radius, in points."),
        prop("richtext", ["rich_text"], get: nil, set: scoped(.field), kind: .boolean, summary: "Whether the field renders rich text."),
        prop("enterkeyenabled", get: nil, set: scoped(.field), kind: .boolean, summary: "Whether Return/Enter sends the enterKey message."),
        prop("locktext", get: nil, set: scoped(.field), kind: .boolean, summary: "Whether the field's text is locked against editing."),
        prop("dontwrap", get: nil, set: scoped(.field), kind: .boolean, summary: "Whether text wrapping is disabled."),
        prop("widemargins", get: nil, set: scoped(.field), kind: .boolean, summary: "Whether the field uses wide text margins."),
        prop("hilite", get: nil, set: scoped(.button, .toggle), kind: .boolean, summary: "The checked/on visual state."),
        prop("autohilite", get: nil, set: scoped(.button, .toggle), kind: .boolean, summary: "Whether the button auto-highlights while pressed."),
        prop("showname", get: nil, set: scoped(.button, .toggle), kind: .boolean, summary: "Whether the part's Name is drawn as its face text."),
        prop("invertonclick", get: nil, set: scoped(.image), kind: .boolean, summary: "Whether the image inverts colors while clicked."),
        prop("animated", ["animation", "animate"], get: nil, set: scoped(.image), kind: .boolean, summary: "Whether an animated GIF plays automatically."),
        prop("transparentbackground", ["transparent_background", "transparent", "transparentbg", "alpha"],
             get: nil, set: scoped(.image, .spriteArea), kind: .boolean, summary: "Chroma-keys the corner-pixel color to transparent."),
        prop("imagefilter", ["filter"], get: nil, set: scoped(.image), summary: "Named CoreImage filter, or empty for none."),
        prop("imagefilterintensity", ["filter_intensity"], get: nil, set: scoped(.image), kind: .number, summary: "0…1 filter intensity."),

        // MARK: Icon (button only)
        prop("icon", get: nil, set: scoped(.button), summary: "Bound icon asset UUID; empty when no icon is set."),

        // MARK: Chart (title/xAxisLabel/etc. are intercepted earlier by chartLevelProperty; chartData is the raw JSON blob)
        prop("chartdata", ["chart_data"], get: nil, set: scoped(.chart), kind: .json, summary: "Raw JSON-encoded ChartConfig."),

        // MARK: Calendar
        prop("selecteddate", ["selected_date"], get: nil, set: scoped(.calendar), summary: "Selected date, ISO 8601 (yyyy-MM-dd)."),
        prop("selectedtime", ["selected_time"], get: nil, set: scoped(.calendar), summary: "Selected time, HH:mm:ss."),
        prop("displaymonth", ["display_month"], get: nil, set: scoped(.calendar), summary: "Visible month, yyyy-MM-01."),
        prop("mindate", ["min_date"], get: nil, set: scoped(.calendar), summary: "Earliest selectable date; empty = no minimum."),
        prop("maxdate", ["max_date"], get: nil, set: scoped(.calendar), summary: "Latest selectable date; empty = no maximum."),
        prop("calendarstyle", ["calendar_style"], get: nil, set: scoped(.calendar), kind: .enumeration, summary: "\"graphical\", \"textual\", or \"clockAndCalendar\"."),

        // MARK: PDF
        prop("pdfurl", ["pdf_url"], get: nil, set: scoped(.pdf), summary: "File path or URL of the displayed PDF."),
        prop("currentpage", ["current_page"], get: nil, set: scoped(.pdf), kind: .number, summary: "1-based current page index."),
        prop("displaymode", ["display_mode"], get: nil, set: scoped(.pdf), kind: .enumeration, summary: "\"single\", \"continuous\", or \"twoUp\"."),
        prop("autoscales", ["auto_scales"], get: nil, set: scoped(.pdf), kind: .boolean, summary: "Whether pages auto-scale to fit."),
        prop("pagecount", ["page_count"], mutability: .readOnly, kind: .number, summary: "Model-layer page count (always \"0\" until a live PDFView reports otherwise)."),

        // MARK: Map
        prop("centerlat", ["center_lat"], get: nil, set: scoped(.map), kind: .number, summary: "Map center latitude, decimal degrees."),
        prop("centerlon", ["center_lon"], get: nil, set: scoped(.map), kind: .number, summary: "Map center longitude, decimal degrees."),
        prop("span", get: nil, set: scoped(.map), kind: .number, summary: "Zoom span, in degrees (smaller = more zoomed in)."),
        prop("maptype", ["map_type"], get: nil, set: scoped(.map), kind: .enumeration, summary: "\"standard\", \"satellite\", \"hybrid\", or \"mutedStandard\"."),
        prop("annotations", get: nil, set: scoped(.map), kind: .json, summary: "JSON array of {lat, lon, title} map annotations."),
        prop("maplocation", ["map_location"], get: nil, set: scoped(.map), summary: "Human-entered place name/address geocoded to lat/lon."),
        prop("showsuserlocation", ["shows_user_location"], get: nil, set: scoped(.map), kind: .boolean, summary: "Whether the live map shows the device's location."),

        // MARK: ColorWell
        prop("colorwellhex", ["colorhex", "color_hex"], get: nil, set: scoped(.colorWell), kind: .color, summary: "The well's bound color."),
        prop("interactive", get: nil, set: scoped(.colorWell), kind: .boolean, summary: "Whether clicking opens the system color picker."),

        // MARK: Form controls (stepper/slider/segmented long names; `value`/`on`/`min`/`max`/`step` bare words are polymorphic)
        prop("segments", ["segmentitems"], get: nil, set: scoped(.segmented), summary: "Pipe-separated segment labels."),
        prop("selectedsegment", ["selected_segment"], get: nil, set: scoped(.segmented), kind: .number, summary: "0-based selected segment index."),

        // MARK: AudioRecorder
        prop("recording", get: nil, set: scoped(.audioRecorder), kind: .boolean, summary: "Start/stop recording."),
        prop("playing", get: nil, set: scoped(.audioRecorder), kind: .boolean, summary: "Start/stop playback of the recorded file."),
        prop("outputpath", ["output_path", "filepath", "file_path"], get: nil, set: scoped(.audioRecorder), summary: "Absolute output path; empty = a temp file."),
        prop("format", get: nil, set: scoped(.audioRecorder), kind: .enumeration, summary: "\"m4a\" or \"caf\"."),
        prop("saveinstack", ["save_in_stack", "embedinstack", "embed_in_stack", "embedded", "audioembedded"],
             get: nil, set: scoped(.audioRecorder), kind: .boolean, summary: "Whether the recording embeds into the .hype document."),
        prop("audiosize", ["audio_size", "audiodatasize", "audio_data_size"], mutability: .readOnly, kind: .number, summary: "Embedded audio byte count."),
        prop("audioduration", ["audio_duration"], mutability: .readOnly, kind: .number, summary: "Recorder's last-known duration, in seconds."),

        // MARK: Video
        prop("videourl", ["video_url"], get: nil, set: scoped(.video), summary: "File path or URL of the video."),
        prop("currenttime", ["current_time"], get: nil, set: scoped(.video), kind: .number, summary: "Current playback position, in seconds."),
        prop("playrate", ["play_rate", "rate"], get: nil, set: scoped(.video), kind: .number, summary: "Playback rate (1 = normal speed; negative = reverse)."),
        prop("videoloop", ["video_loop"], get: nil, set: scoped(.video), kind: .boolean, summary: "Whether playback loops."),
        prop("videoautoplay", ["video_autoplay"], get: nil, set: scoped(.video), kind: .boolean, summary: "Whether playback starts automatically."),
        prop("videovolume", ["video_volume"], get: nil, set: scoped(.video), kind: .number, summary: "Playback volume, 0…1."),
        prop("videoduration", ["video_duration"], mutability: .readOnly, kind: .number, summary: "Video duration, in seconds (derived from the asset)."),

        // MARK: AudioKit music controls (music family)
        prop("musicpattern", ["music_pattern", "patternname", "pattern_name"], get: nil, set: scoped(musicFamily), summary: "Name of the current AudioKit pattern."),
        prop("musicinstrument", ["music_instrument", "instrument"], get: nil, set: scoped(musicFamily), summary: "Name of the selected instrument voice."),
        prop("musictempo", ["music_tempo", "tempo", "bpm"], get: nil, set: scoped(musicFamily), kind: .number, summary: "Tempo, in BPM."),
        prop("musickeycount", ["music_key_count", "keycount", "key_count", "keys", "keyboardkeys", "keyboard_keys"],
             get: nil, set: scoped(.pianoKeyboard), kind: .number, summary: "Number of piano keys shown."),
        prop("showcontroltype", ["show_control_type", "showtype", "show_type"], get: nil, set: scoped(musicFamily), kind: .boolean, summary: "Whether the control-type row is shown."),
        prop("showmusicpattern", ["show_music_pattern", "showpattern", "show_pattern"], get: nil, set: scoped(musicFamily), kind: .boolean, summary: "Whether the pattern-name row is shown."),
        prop("showmusicinstrument", ["show_music_instrument", "showinstrument", "show_instrument", "showinstrumentpopup", "show_instrument_popup"],
             get: nil, set: scoped(musicFamily), kind: .boolean, summary: "Whether the instrument popup is shown."),
        prop("showmusictempo", ["show_music_tempo", "showtempo", "show_tempo"], get: nil, set: scoped(musicFamily), kind: .boolean, summary: "Whether the tempo row is shown."),
        prop("musicloop", ["music_loop"], get: nil, set: scoped(musicFamily), kind: .boolean, summary: "Whether the pattern loops."),
        prop("musicvolume", ["music_volume"], get: nil, set: scoped(musicFamily), kind: .number, summary: "Playback volume, 0…1."),
        prop("musictracks", ["music_tracks", "trackdata", "track_data"], get: nil, set: scoped(musicFamily), kind: .json, summary: "Raw sequencer/mixer track JSON."),
        prop("musicsource", ["music_source"], get: nil, set: scoped(musicFamily), summary: "Combined source descriptor; writes route to a pattern or an Apple Music catalog item."),
        prop("musicsourcekind", ["music_source_kind", "sourcekind", "source_kind"], get: nil, set: scoped(musicFamily), kind: .enumeration, summary: "\"hypePattern\" or an Apple Music source kind."),
        prop("applemusicid", ["apple_music_id", "musicid", "music_id"], get: nil, set: scoped(musicFamily), summary: "Apple Music catalog item ID."),
        prop("applemusictype", ["apple_music_type", "musictype", "music_type"], get: nil, set: scoped(musicFamily), kind: .enumeration, summary: "Apple Music item kind (song, album, playlist, …)."),
        prop("applemusictitle", ["apple_music_title", "musictitle", "music_title"], get: nil, set: scoped(musicFamily), summary: "Snapshot title of the bound catalog item."),
        prop("applemusicartist", ["apple_music_artist", "musicartist", "music_artist"], get: nil, set: scoped(musicFamily), summary: "Snapshot artist of the bound catalog item."),
        prop("applemusicalbum", ["apple_music_album", "musicalbum", "music_album"], get: nil, set: scoped(musicFamily), summary: "Snapshot album of the bound catalog item."),
        prop("artwork", ["artworkurl", "artwork_url", "musicartwork", "music_artwork"], get: nil, set: scoped(musicFamily), summary: "Snapshot artwork URL of the bound catalog item."),
        prop("musicposition", ["music_position", "positionseconds", "position_seconds"], get: nil, set: scoped(musicFamily), kind: .number, summary: "Playback position, in seconds."),
        prop("musicduration", ["music_duration", "durationseconds", "duration_seconds"], get: nil, set: scoped(musicFamily), kind: .number, summary: "Catalog item (or fallback audio) duration, in seconds."),
        prop("musicqueue", ["music_queue", "queuedata", "queue_data"], get: nil, set: scoped(musicFamily), kind: .json, summary: "Raw music-queue JSON."),
        prop("musicsearchterm", ["music_search_term", "searchterm", "search_term"], get: nil, set: scoped(musicFamily), summary: "Apple Music search text."),
        prop("musicsearchscope", ["music_search_scope", "searchscope", "search_scope"], get: nil, set: scoped(musicFamily), kind: .enumeration, summary: "Apple Music search scope."),

        // MARK: Gauge
        prop("gaugevalue", ["gauge_value"], get: nil, set: scoped(.gauge), kind: .number, summary: "Current gauge reading."),
        prop("gaugemin", ["gauge_min"], get: nil, set: scoped(.gauge), kind: .number, summary: "Gauge range minimum."),
        prop("gaugemax", ["gauge_max"], get: nil, set: scoped(.gauge), kind: .number, summary: "Gauge range maximum (kept greater than gaugeMin)."),
        prop("gaugestyle", ["gauge_style"], get: nil, set: scoped(.gauge), kind: .enumeration, summary: "Gauge visual style."),
        prop("gaugetint", ["gauge_tint"], get: nil, set: scoped(.gauge), kind: .color, summary: "Accent color of the gauge."),
        prop("gaugelabel", ["gauge_label"], get: nil, set: scoped(.gauge), summary: "Caption text under the gauge."),
        prop("gaugeminlabel", ["gauge_min_label"], get: nil, set: scoped(.gauge), summary: "Label drawn at the minimum end."),
        prop("gaugemaxlabel", ["gauge_max_label"], get: nil, set: scoped(.gauge), summary: "Label drawn at the maximum end."),
        prop("gaugedecimals", ["gauge_decimals"], get: nil, set: scoped(.gauge), kind: .number, summary: "Decimal places shown (0 = full precision)."),

        // MARK: ProgressView
        prop("progressvalue", ["progress_value"], get: nil, set: scoped(.progressView), kind: .number, summary: "Current progress."),
        prop("progresstotal", ["progress_total", "total"], get: nil, set: scoped(.progressView), kind: .number, summary: "Progress range maximum (0 is the fixed minimum)."),
        prop("progressmin", get: nil, set: scoped(.progressView), kind: .number, summary: "Always \"0\" — progress views always start at 0; set the max instead."),
        prop("progresscircular", ["progress_circular", "circular", "iscircular"], get: nil, set: scoped(.progressView), kind: .boolean, summary: "Whether the spinner is circular rather than a bar."),
        prop("progressindeterminate", ["progress_indeterminate", "indeterminate"], get: nil, set: scoped(.progressView), kind: .boolean, summary: "Whether the spinner shows indeterminate motion."),
        prop("progresslabel", ["progress_label"], get: nil, set: scoped(.progressView), summary: "Caption text under the progress view."),
        prop("progresstint", ["progress_tint"], get: nil, set: scoped(.progressView), kind: .color, summary: "Accent color of the progress view."),
        prop("progressdecimals", ["progress_decimals"], get: nil, set: scoped(.progressView), kind: .number, summary: "Decimal places shown (0 = integral steps)."),

        // MARK: Menu / Popup
        prop("popupitems", ["popup_items"], get: nil, set: scoped(.button), summary: "Newline-separated popup item list; first item is selected."),
        prop("menuitems", ["menu_items"], get: nil, set: scoped(.menu, .button), aiExposed: false, legacy: true,
             summary: "Newline-separated menu items, `label||inline script` per line."),
        prop("menutitle", ["menu_title"], get: nil, set: scoped(.menu, .button), aiExposed: false, legacy: true, summary: "Menu title text."),

        // MARK: SearchField
        prop("searchtext", ["search_text"], get: nil, set: scoped(.field, .searchField),
             summary: "Current search box text — masked to \"(masked)\" when reading a .secure field.",
             secureMasked: true),
        prop("searchprompt", ["search_prompt"], get: nil, set: scoped(.field, .searchField), summary: "Placeholder shown when the search box is empty."),
        prop("searchsendsimmediately", ["search_sends_immediately", "immediate"], get: nil, set: scoped(.field, .searchField), kind: .boolean, summary: "Whether searchChanged fires on every keystroke."),

        // MARK: Divider
        prop("dividerorientation", ["divider_orientation", "orientation"], get: nil, set: scoped(.divider), kind: .enumeration, summary: "\"horizontal\" or \"vertical\"."),
        prop("dividerthickness", ["divider_thickness", "thickness"], get: nil, set: scoped(.divider), kind: .number, summary: "Line thickness, in points."),
        prop("dividercolor", ["divider_color"], get: nil, set: scoped(.divider), kind: .color, summary: "Line color."),

        // MARK: SpriteArea
        prop("scalemode", ["scale_mode"], get: nil, set: scoped(.spriteArea), kind: .enumeration, summary: "Scene content scaling mode."),
        prop("showsphysics", ["shows_physics"], get: nil, set: scoped(.spriteArea), kind: .boolean, summary: "Whether physics outlines are drawn in Browse mode."),
        prop("showsfps", ["shows_fps"], get: nil, set: scoped(.spriteArea), kind: .boolean, summary: "Whether the frame-rate counter is drawn."),
        prop("showsnodecount", ["shows_node_count"], get: nil, set: scoped(.spriteArea), kind: .boolean, summary: "Whether the live node count is drawn."),
        prop("scenename", ["scene_name", "activescene", "active_scene"], mutability: .readOnly, summary: "Name of the active scene."),
        prop("scenecount", ["scene_count"], mutability: .readOnly, kind: .number, summary: "Number of scenes defined in this sprite area."),

        // MARK: Scene3D
        //
        // `modelAsset`/`assetName` deliberately do NOT get their own
        // descriptor entry: SET groups them with `object` (an alias,
        // below); GET diverges (H6) via the bespoke intercept at the
        // top of `resolveGet`, which returns `.property("modelasset")`
        // directly — never consulting this list — so there is no
        // canonical/alias collision despite the two verbs disagreeing
        // on what these four spellings mean.
        prop("object", ["model", "modelasset", "model_asset", "assetname", "asset_name"], get: nil, set: scoped(.scene3D),
             summary: "Bound 3D asset or repository object; accepts an asset name, repository object id, or STL/USDZ path."),
        prop("modelurl", ["model_url", "sceneurl", "scene_url"], get: nil, set: scoped(.scene3D), summary: "Legacy authored-path alias of `object`."),
        prop("allowscameracontrol", ["allows_camera_control", "cameracontrol"], get: nil, set: scoped(.scene3D), kind: .boolean, summary: "Whether the user can orbit/zoom the camera."),
        prop("autolighting", ["auto_lighting", "defaultlighting"], get: nil, set: scoped(.scene3D), kind: .boolean, summary: "Whether SceneKit's automatic lighting rig is used."),
        prop("antialiasing", ["anti_aliasing"], get: nil, set: scoped(.scene3D), kind: .enumeration, summary: "Antialiasing quality name."),
        prop("background3d", ["background_3d", "scenebackground"], get: nil, set: scoped(.scene3D), kind: .color, summary: "Scene background color."),

        // MARK: No-op stubs — classic HyperCard field properties with no model backing.
        // GET keeps its hardcoded classic answer (real switch cases, unaffected);
        // SET is an explicit accepted no-op so imported classic stacks never error (Condition 3).
        prop("scroll", ["scrollpos"], mutability: .noOpStub, kind: .number, legacy: true, summary: "Classic scroll offset — always \"0\"; SET is a no-op."),
        prop("sharedtext", mutability: .noOpStub, kind: .boolean, legacy: true, summary: "Classic field flag — always \"false\"; SET is a no-op."),
        prop("sharedhilite", mutability: .noOpStub, kind: .boolean, legacy: true, summary: "Classic field flag — always \"false\"; SET is a no-op."),
        prop("showlines", mutability: .noOpStub, kind: .boolean, legacy: true, summary: "Classic field flag — always \"false\"; SET is a no-op."),
        prop("showpict", mutability: .noOpStub, kind: .boolean, legacy: true, summary: "Classic field flag — always \"true\"; SET is a no-op."),
        prop("fixedlineheight", mutability: .noOpStub, kind: .boolean, legacy: true, summary: "Classic field flag — always \"false\"; SET is a no-op."),
        prop("multiplelines", mutability: .noOpStub, kind: .boolean, legacy: true, summary: "Classic field flag — always \"true\"; SET is a no-op."),
        prop("dontsearch", mutability: .noOpStub, kind: .boolean, legacy: true, summary: "Classic field flag — always \"false\"; SET is a no-op."),
        prop("autoselect", mutability: .noOpStub, kind: .boolean, legacy: true, summary: "Classic field flag — always \"false\"; SET is a no-op."),
        prop("autotab", mutability: .noOpStub, kind: .boolean, legacy: true, summary: "Classic field flag — always \"false\"; SET is a no-op."),
        prop("cantdelete", mutability: .noOpStub, kind: .boolean, legacy: true, summary: "Classic field flag — always \"false\"; SET is a no-op."),
        prop("cantmodify", mutability: .noOpStub, kind: .boolean, legacy: true, summary: "Classic field flag — always \"false\"; SET is a no-op."),
    ]

    /// The complete, registry-driven field-body masking set (Security
    /// condition 1): every descriptor whose GET must return
    /// `"(masked)"` — across every one of its aliases — when reading a
    /// `.field` part with `fieldStyle == .secure`. Consumed by
    /// `SecurityRegressionTests`'s masking-law test so a future masked
    /// field is caught by test *structure*, not a hand-maintained list.
    public static var secureMaskedDescriptors: [Descriptor] {
        descriptors.filter(\.secureMasked)
    }

    /// Precomputed alias→descriptor lookup, built once. Every
    /// canonical name and every alias of every descriptor must be
    /// unique across the whole registry — enforced by `assert` here
    /// (crashes a debug/test build immediately on a collision) and by
    /// `PartPropertyRegistryConformanceTests`'s alias-uniqueness test.
    private static let aliasLookup: [String: Descriptor] = {
        var map: [String: Descriptor] = [:]
        for descriptor in descriptors {
            for key in [descriptor.canonical] + descriptor.aliases {
                assert(map[key] == nil, "PartPropertyRegistry: duplicate alias '\(key)' — also used by '\(map[key]?.canonical ?? "")' and '\(descriptor.canonical)'")
                map[key] = descriptor
            }
        }
        return map
    }()

    // MARK: - Polymorphic bare-word dispatch

    /// Resolves a bare word whose meaning depends on the target
    /// part's type (design.md §3.1/§3.3 normative dispatch tables).
    /// Returns `nil` when `loweredName` isn't one of these words at
    /// all — the caller falls through to the regular descriptor
    /// lookup. A non-`nil` result is always definitive (including
    /// error results): these words never fall through, even when the
    /// part's type has no meaning for them.
    private static func polymorphicResolution(_ loweredName: String, part: Part, isSet: Bool) -> Resolution? {
        switch loweredName {
        case "value":
            switch part.partType {
            case .field: return .property(canonical: "textcontent")
            case .gauge: return .property(canonical: "gaugevalue")
            case .progressView: return .property(canonical: "progressvalue")
            case .segmented: return .property(canonical: "selectedsegment")
            case .toggle, .stepper, .slider: return .property(canonical: "value")
            default:
                // Documented GET carve-out (mock §3.1): GET keeps the
                // old permissive controlValue read for every other
                // type; only SET becomes strict here.
                return isSet
                    ? .notApplicable(name: loweredName, appliesTo: "stepper, slider, gauge, progress view, toggle, segmented, or field")
                    : .property(canonical: "value")
            }
        case "on":
            if part.partType == .toggle { return .property(canonical: "on") }
            return .notApplicable(name: loweredName, appliesTo: "toggle")
        case "min", "minvalue", "min_value":
            switch part.partType {
            case .stepper, .slider: return .property(canonical: "min")
            case .gauge: return .property(canonical: "gaugemin")
            case .calendar: return .property(canonical: "mindate")
            case .progressView: return .property(canonical: "progressmin")
            default: return .notApplicable(name: loweredName, appliesTo: "stepper, slider, gauge, calendar, or progress view")
            }
        case "max", "maxvalue", "max_value":
            switch part.partType {
            case .stepper, .slider: return .property(canonical: "max")
            case .gauge: return .property(canonical: "gaugemax")
            case .calendar: return .property(canonical: "maxdate")
            case .progressView: return .property(canonical: "progresstotal")
            default: return .notApplicable(name: loweredName, appliesTo: "stepper, slider, gauge, calendar, or progress view")
            }
        case "step", "increment":
            switch part.partType {
            case .stepper, .slider: return .property(canonical: "step")
            default: return .notApplicable(name: loweredName, appliesTo: "stepper or slider")
            }
        case "loop", "looping":
            if part.partType == .video { return .property(canonical: "videoloop") }
            if musicFamily.contains(part.partType) { return .property(canonical: "musicloop") }
            return .notApplicable(name: loweredName, appliesTo: "video or a music control")
        case "volume":
            if part.partType == .video { return .property(canonical: "videovolume") }
            if musicFamily.contains(part.partType) { return .property(canonical: "musicvolume") }
            return .notApplicable(name: loweredName, appliesTo: "video or a music control")
        case "autoplay":
            if part.partType == .video { return .property(canonical: "videoautoplay") }
            return .notApplicable(name: loweredName, appliesTo: "video")
        case "duration":
            // video/audioRecorder remap to read-only canonicals — SET
            // must surface `.readOnly` itself here, since a
            // polymorphic-word match is definitive and never falls
            // through to the flat descriptor lookup that would
            // otherwise catch their `mutability == .readOnly`.
            if part.partType == .video {
                return isSet ? .readOnly(canonical: "videoduration") : .property(canonical: "videoduration")
            }
            if part.partType == .audioRecorder {
                return isSet ? .readOnly(canonical: "audioduration") : .property(canonical: "audioduration")
            }
            if musicFamily.contains(part.partType) { return .property(canonical: "musicduration") }
            return .notApplicable(name: loweredName, appliesTo: "video, a music control, or the audio recorder")
        case "tint":
            switch part.partType {
            case .gauge: return .property(canonical: "gaugetint")
            case .progressView: return .property(canonical: "progresstint")
            default: return .notApplicable(name: loweredName, appliesTo: "gauge or progress view")
            }
        case "prompt":
            if part.partType == .searchField { return .property(canonical: "searchprompt") }
            if part.partType == .field, part.fieldStyle == .search { return .property(canonical: "searchprompt") }
            return .notApplicable(name: loweredName, appliesTo: "a search-style field")
        case "total":
            if part.partType == .progressView { return .property(canonical: "progresstotal") }
            return .notApplicable(name: loweredName, appliesTo: "progress view")
        case "items":
            switch part.partType {
            case .button: return .property(canonical: "popupitems")
            case .menu: return .property(canonical: "menuitems")
            default: return .notApplicable(name: loweredName, appliesTo: "button or menu")
            }
        case "decimals":
            switch part.partType {
            case .gauge: return .property(canonical: "gaugedecimals")
            case .progressView: return .property(canonical: "progressdecimals")
            default: return .notApplicable(name: loweredName, appliesTo: "gauge or progress view")
            }
        case "style":
            switch part.partType {
            case .button, .field, .shape: return .property(canonical: "style")
            default: return .notApplicable(name: loweredName, appliesTo: "button, field, or shape")
            }
        case "color":
            switch part.partType {
            case .colorWell: return .property(canonical: "colorwellhex")
            case .divider: return .property(canonical: "dividercolor")
            default: return .notApplicable(name: loweredName, appliesTo: "color well or divider")
            }
        case "background":
            if part.partType == .scene3D { return .property(canonical: "background3d") }
            return .notApplicable(name: loweredName, appliesTo: "3D scene")
        default:
            return nil
        }
    }

    /// Approximate per-type applicability for the same bare words,
    /// used only to seed `nearestName` typo-suggestion candidates
    /// (ignores the field-style nuance of `prompt` — a suggestion is
    /// a hint, not a dispatch decision).
    private struct PolymorphicWordGroup {
        let names: [String]
        let types: Set<PartType>
    }

    private static let polymorphicWordGroups: [PolymorphicWordGroup] = [
        .init(names: ["value"], types: [.field, .gauge, .progressView, .segmented, .toggle, .stepper, .slider]),
        .init(names: ["on"], types: [.toggle]),
        .init(names: ["min", "minvalue", "min_value"], types: [.stepper, .slider, .gauge, .calendar, .progressView]),
        .init(names: ["max", "maxvalue", "max_value"], types: [.stepper, .slider, .gauge, .calendar, .progressView]),
        .init(names: ["step", "increment"], types: [.stepper, .slider]),
        .init(names: ["loop", "looping"], types: musicFamily.union([.video])),
        .init(names: ["volume"], types: musicFamily.union([.video])),
        .init(names: ["autoplay"], types: [.video]),
        .init(names: ["duration"], types: musicFamily.union([.video, .audioRecorder])),
        .init(names: ["tint"], types: [.gauge, .progressView]),
        .init(names: ["prompt"], types: [.field, .searchField]),
        .init(names: ["total"], types: [.progressView]),
        .init(names: ["items"], types: [.button, .menu]),
        .init(names: ["decimals"], types: [.gauge, .progressView]),
        .init(names: ["style"], types: [.button, .field, .shape]),
        .init(names: ["color"], types: [.colorWell, .divider]),
        .init(names: ["background"], types: [.scene3D]),
    ]

    // MARK: - Resolution entry points

    /// Resolves a GET of `loweredName` against `part`.
    ///
    /// GET is deliberately lenient (design.md Decision 3): it errors
    /// only where a polymorphic bare word declares an error cell for
    /// this part's type. A fully unknown name (no descriptor and no
    /// polymorphic word matches at all) resolves to `.unknown`, but
    /// the caller (the GET switch's `default: return ""`) keeps the
    /// existing documented posture of returning an empty string for
    /// that case rather than throwing — GET only throws for
    /// `.notApplicable`.
    public static func resolveGet(_ loweredName: String, for part: Part) -> Resolution {
        // scene3D's `modelAsset`/`assetName` diverge from `object`'s
        // grouping only on GET (H6) — read the asset ref's own name
        // rather than the resolved display-model string. Intercepted
        // before the shared alias lookup so SET (which still groups
        // these spellings with `object`) is unaffected.
        if loweredName == "modelasset" || loweredName == "model_asset"
            || loweredName == "assetname" || loweredName == "asset_name" {
            return .property(canonical: "modelasset")
        }
        if let resolution = polymorphicResolution(loweredName, part: part, isSet: false) {
            return resolution
        }
        guard let descriptor = aliasLookup[loweredName] else {
            return .unknown(suggestion: nearestName(to: loweredName, for: part.partType))
        }
        if let applicability = descriptor.getApplicability, !applicability.types.contains(part.partType) {
            return .notApplicable(name: loweredName, appliesTo: joinTypeWords(applicability.types))
        }
        return .property(canonical: descriptor.canonical)
    }

    /// Resolves a SET of `loweredName` against `part`. SET is strict
    /// (mock §3.7): every case other than `.property` and `.noOp`
    /// must produce a runtime error at the call site.
    public static func resolveSet(_ loweredName: String, for part: Part) -> Resolution {
        if let resolution = polymorphicResolution(loweredName, part: part, isSet: true) {
            return resolution
        }
        guard let descriptor = aliasLookup[loweredName] else {
            return .unknown(suggestion: nearestName(to: loweredName, for: part.partType))
        }
        if descriptor.mutability == .readOnly {
            return .readOnly(canonical: descriptor.canonical)
        }
        if descriptor.mutability == .noOpStub {
            return .noOp
        }
        if let applicability = descriptor.setApplicability, !applicability.types.contains(part.partType) {
            return .notApplicable(name: loweredName, appliesTo: joinTypeWords(applicability.types))
        }
        return .property(canonical: descriptor.canonical)
    }

    // MARK: - Typo suggestion

    /// Nearest known property name to `loweredName` that is
    /// meaningful for `type`, within Levenshtein distance 2. `nil`
    /// when nothing is close enough. Candidates are drawn only from
    /// names applicable to `type` (Condition 11) — never from every
    /// property in the registry.
    public static func nearestName(to loweredName: String, for type: PartType) -> String? {
        var best: String?
        var bestDistance = 3 // one past the maximum accepted distance (2)
        for candidate in candidateNames(for: type) where candidate != loweredName {
            let distance = levenshtein(loweredName, candidate)
            guard distance <= 2 else { continue }
            if distance < bestDistance || (distance == bestDistance && (best == nil || candidate < best!)) {
                bestDistance = distance
                best = candidate
            }
        }
        return best
    }

    private static func candidateNames(for type: PartType) -> [String] {
        var names: [String] = []
        for descriptor in descriptors {
            let getApplies = descriptor.getApplicability.map { $0.types.contains(type) } ?? true
            let setApplies = descriptor.setApplicability.map { $0.types.contains(type) } ?? true
            guard getApplies || setApplies else { continue }
            names.append(descriptor.canonical)
            names.append(contentsOf: descriptor.aliases)
        }
        for group in polymorphicWordGroups where group.types.contains(type) {
            names.append(contentsOf: group.names)
        }
        return names
    }

    private static func joinTypeWords(_ types: Set<PartType>) -> String {
        let words = types.map(\.rawValue).sorted()
        switch words.count {
        case 0: return ""
        case 1: return words[0]
        case 2: return "\(words[0]) or \(words[1])"
        default: return words.dropLast().joined(separator: ", ") + ", or " + words[words.count - 1]
        }
    }

    /// Classic iterative-DP Levenshtein edit distance.
    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        let (m, n) = (a.count, b.count)
        if m == 0 { return n }
        if n == 0 { return m }
        var previousRow = Array(0...n)
        var currentRow = [Int](repeating: 0, count: n + 1)
        for i in 1...m {
            currentRow[0] = i
            for j in 1...n {
                let substitutionCost = a[i - 1] == b[j - 1] ? 0 : 1
                currentRow[j] = Swift.min(
                    previousRow[j] + 1,
                    currentRow[j - 1] + 1,
                    previousRow[j - 1] + substitutionCost
                )
            }
            previousRow = currentRow
        }
        return previousRow[n]
    }
}

/// Thrown by the registry-gated property dispatch in
/// `Interpreter.swift` (and, in a later work package,
/// `HypeToolExecutor.swift`). `LocalizedError` conformance means the
/// interpreter's existing top-level `catch { ScriptError(message:
/// error.localizedDescription, ...) }` wraps this correctly without
/// any changes to that catch site.
public struct PartPropertyError: Error, Sendable, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) {
        self.message = message
    }
}
