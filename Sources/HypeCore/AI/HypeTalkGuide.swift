import Foundation

/// Guidance text silently provided to the local Ollama model as part of
/// every chat request.
///
/// Lives next to `HypeTools` and `OllamaToolClient` so the HypeTalk
/// language surface that the AI sees is a single source of truth that
/// can be unit-tested without instantiating a SwiftUI view. Any other AI
/// entry point that needs to coach a model on writing HypeTalk should
/// import `HypeTalkGuide.llmContext` rather than hand-rolling its own
/// prompt fragment — the language evolves in one place.
///
/// The guide trades narrative prose for structured headings and
/// compact examples that a model can grep by keyword. The complete,
/// verbose reference lives in `HypeTalk-LLM-Context.md` /
/// `HyperTalk_Reference.md` in the repo root — this constant is the
/// curated subset we ship to the model. Roughly ~33 KB / ~8000 tokens
/// after the 2026 grammar-coverage expansion; kept that size on
/// purpose so the model has the operator table, constants list,
/// stub-command list, and full hallucination catalogue inline rather
/// than relying on guesswork.
public enum HypeTalkGuide {

    /// The HypeTalk authoring guide embedded on every Ollama chat turn.
    ///
    /// Sections:
    ///
    /// 1. Language essentials (character, comments, values, line continuation)
    /// 2. Constants (empty, quote, return, tab, pi, …)
    /// 3. Message routing, handler syntax, common events
    /// 4. Variables, scoping, the `it` variable, `global`
    /// 5. Object references (parts and sprite-scene nodes)
    /// 6. Property get/set surface for parts and sprite nodes
    /// 7. Operators and precedence (arithmetic, comparison, membership,
    ///    type test, existence, boolean, concatenation)
    /// 8. Chunk expressions (text slicing — read-only)
    /// 9. Control flow (if/else, repeat, exit, pass)
    /// 10. Built-in functions (full enumeration)
    /// 11. Navigation, visual effects, dialogs
    /// 12. Sound, animation, sprite scenes, tile maps, networking
    /// 13. Stub commands (recognized but no-op — do not rely on these)
    /// 14. Canonical handler patterns
    /// 15. Common AI hallucinations to AVOID
    /// 16. Generation rules and validation contract
    public static let llmContext: String = """
        # HypeTalk scripting guide

        HypeTalk is a HyperCard-inspired, case-insensitive, English-like scripting language used inside Hype. Scripts attach to parts (buttons, fields, shapes, images, videos, web views, charts, sprite areas), cards, backgrounds, stacks, and nodes inside sprite scenes, and run in response to events. All values are strings; arithmetic coerces them to numbers when needed. Line comments start with `--`.

        ## Language essentials
        - **Comments:** `-- to end of line`. There is no block-comment syntax.
        - **Case:** keywords, identifiers, and string equality (`is`, `=`, `contains`, `is in`) are all CASE-INSENSITIVE. So `if X is "yes" then` matches "Yes", "YES", "yes" alike. Names of parts are looked up case-insensitively but their original case is preserved on display.
        - **String literals:** double-quoted: `"hello"`. Curly/smart quotes (`"…"`) are also accepted at the lexer level — pasted user text won't break parsing. There are no backslash escapes inside a string; to embed a quote, use the `quote` constant: `"He said " & quote & "hi" & quote`.
        - **Line continuation:** end a line with `\\` (a single backslash) immediately before the newline to fold the next line onto it. Useful for very long URLs or JSON bodies.
        - **Truthiness:** only `"true"` (case-insensitive) and any non-zero number are truthy. `"false"`, `""` (empty), and `"0"` are falsy. Strings like `"yes"`, `"on"`, `"1.5"` are NOT special — `"1.5"` is truthy because it's a non-zero number; `"yes"` is FALSY because it's neither `"true"` nor numeric. When you need a boolean from a non-canonical source, compare explicitly: `if x is "yes" then`.
        - **Numeric coercion:** `value(s)` and arithmetic coerce strings to numbers. Empty strings and non-numeric strings become `0` silently — no error is raised. `n / 0` and `n mod 0` return `0`; the older `divide x by 0` form returns `"INF"`. Always range-check inputs before dividing.

        ## Message routing
        When an event fires, Hype looks for a matching handler in order and stops at the first match. Use `pass <message>` to let it continue up the chain explicitly.
            scene node -> parent group(s) -> scene -> sprite area part -> card -> background -> stack -> Hype (app)

        ## Handler syntax
            on mouseUp
              -- body
            end mouseUp

            on openCard
              put "Welcome" into field "title"
            end openCard

        Exit a handler early with `exit <name>` (e.g. `exit mouseUp`). Return a value with `return <expr>`. Inside loops: `exit repeat` breaks, `next repeat` continues.

        ## Common events
        mouseUp, mouseDown, mouseDragged, mouseWithin, mouseEnter, mouseLeave,
        openCard, closeCard, openBackground, closeBackground, openStack, closeStack,
        openField, closeField, enterKey (alias: enter), keyDown, keyUp, idle,
        openScene, closeScene, sceneDidLoad, frameUpdate,
        beginContact, endContact, actionFinished.

        ## Variables and data
            put "hello" into myVar        -- assign
            put 42 into score
            global score                  -- declare a shared global in THIS handler
            add 5 to score                -- arithmetic mutators: add, subtract, multiply, divide
            put a & b into result         -- string concatenation (tight)
            put a && b into result        -- concatenation with a single space
            put "X: " before field "log"  -- prepend to a field's text
            put " done" after field "log" -- append to a field's text
            get the name of me            -- shorthand: equivalent to `put the name of me into it`
            get the loc of me into pt     -- variant: also writes to a named target

        **`it` lifecycle.** `it` is set by `ask`, `answer`, `get`, every async request (the request UUID), most built-in queries, and the synchronous `ollama(...)` function. `it` is a per-handler local — it persists across statements WITHIN a handler but does NOT carry over from one handler to another. Globals carry; `it` does not.

        **`global` scoping.** You MUST redeclare `global <name>` inside every handler that reads or writes the global. A `global x` in handler A does not register `x` as global in handler B — without the declaration, handler B's `put 5 into x` writes to a local that disappears when the handler returns. Globals persist for the life of the stack session (across idle ticks, navigation, and handler calls).

        **`me` returns a UUID, not a name.** `me` is the script-owning object's UUID string. The property accessor resolves UUIDs back to parts, so `the loc of me`, `set the rotation of me to 45`, `the name of me` all work. But `if me is "OK" then` will NEVER match a part name — compare with `the name of me` instead. `this card`, `this background`, `this stack` refer to the current navigation context.

        ## Constants
        Bare identifiers that evaluate to fixed string/number values. They cannot be assigned to.

            empty             -- the empty string ""
            quote             -- a single double-quote character "
            space             -- " "
            tab               -- a single tab character
            return / cr       -- carriage return "\r"  (use to join multi-line text)
            linefeed / lf     -- newline "\n"
            comma             -- ","
            colon             -- ":"
            pi                -- 3.14159265358979
            zero one two three four five six seven eight nine ten   -- 0..10
            up                -- "up"   (used by shiftKey/optionKey/commandKey)
            down              -- "down"

        Examples:
            put "Item 1" & return & "Item 2" & return & "Item 3" into field "list"
            if the shiftKey is down then ...
            if x is empty then put "(unset)" into x
            put quote & "hi" & quote into greeting     -- becomes:  "hi"

        ## Object references
            button "OK"        field "input"       card "home"          card 3
            background "Main"  stack               spritearea "game"
            sprite "player"    label "score"       shape "wall"
            camera "cam"       emitter "fire"      tilemap "map"
            audio "music"      video "intro"       chart "sales"
            calendar "due"     pdf "manual"        map "store"
            colorWell "fill"   stepper "qty"       slider "volume"
            segmented "tabs"   recorder "memo"     scene3d "model"
            progressView "bar" gauge "rpm"         divider "sep"
            -- (toggle / link / menu / searchField were collapsed into
            --  button styles `.toggle / .link / .popup` and field
            --  style `.search` — see `set the style of button "X"`).
        Use double-quoted names; bare words are only valid for short keywords.

        ## Properties — get and set
            put the name of button "OK" into n
            set the text of field "input" to "hello"
            put the text of field "input" into s         -- read field text
            put the value of field "input" into s        -- alias for the above
            set the value of field "input" to "world"    -- alias setter
            set the visible of field "info" to false       -- hide a field
            set the visible of image "logo" to true        -- show an image
            set the visible of button "OK" to false        -- hide a button
            set the visible of image "logo" to not the visible of image "logo"   -- toggle (boolean negation)
            set the loc of sprite "player" to "200,300"      -- points are "x,y" strings
            set the location of map "store" to "97537"       -- map: location is overloaded — non-coords routes to mapLocation (geocode)
            set the location of button "play" to "100,200"   -- non-map: location = geometric center (same as loc)

        Discoverability: when you don't remember a property name, call the
        `list_all_properties(part_name)` tool — it returns every property
        (current + default) for that part using exactly the names this
        syntax accepts.

        **Part properties:** name, id, left, top, width, height, right, bottom, loc, rect, visible, enabled, hilite, style, script, textFont, textSize, textAlign, textStyle, fontColor (alias textColor / color), textContent, fillColor, strokeColor, strokeWidth, cornerRadius, showName, autoHilite, lockText, url.
        **Sprite-node properties:** loc, size, width, height, rotation, alpha, xScale, yScale, zPosition, hidden, text, fontName, fontSize, fontColor, textStyle, fillColor, strokeColor, lineWidth, velocity, angularVelocity, density, friction, restitution, damping, dynamic, affectedByGravity, birthRate, particleLifetime, particleSpeed, particleColor, particleScale, emissionAngle, volume, loop, autoplay, target, zoom.

        **Text styling.** Any part or label node that draws text supports two related properties:
          - **fontColor** (parts: aliases `textColor`, `color`) — hex string (`"#FF0000"`) for text foreground. Empty string means "auto / contrast-aware against fill" (the renderer picks a readable color from the part's fill luminance — fixes dark-mode "white text on white fill" automatically). Set `the fontColor of cd btn 1 to ""` to revert to auto.
          - **textStyle** (parts and label nodes) — comma-separated subset of `plain`, `bold`, `italic`, `underline`, `strikethrough`. Examples: `"plain"`, `"bold"`, `"bold, italic"`, `"underline, strikethrough"`. Aliases accepted on input: `"strike"` / `"strikeout"` → strikethrough, `"underlined"` → underline. Stored canonically as `"plain"` or comma+space joined (`"bold, italic"`). Setters normalize, so `set the textStyle of cd btn 1 to "BOLD,italic"` round-trips to `"bold, italic"`.

        Examples:
          ```
          set the fontColor of cd btn "Title" to "#FF0000"   -- explicit red
          set the textColor of cd btn "Title" to ""           -- back to auto
          set the textStyle of cd btn "Title" to "bold,italic"
          if the textStyle of cd btn "Title" contains "bold" then beep
          set the textStyle of node "Score" of card sprite area "scene" to "bold"
          ```
        **Framework control properties** (used as `the <prop> of <kind> "name"`):
          - **calendar:** selectedDate, displayMonth, minDate, maxDate, calendarStyle (graphical | textual | clockAndCalendar)
          - **pdf:** pdfurl, currentPage, displayMode (single | continuous | twoUp), autoScales
          - **map:** centerLat, centerLon, span, mapType (standard | satellite | hybrid | mutedStandard), annotations, location (alias: maplocation / map_location — geocoded place name, address, or US ZIP; resolves async)
          - **colorWell:** color (hex like "#FF5500"), interactive
          - **stepper / slider:** value, min, max, step
          - **button (style=toggle / checkBox):** hilite (true/false — backs the on/off state of toggle / checkbox styles); the `on` of <kind> "X" is also accepted as an alias for hilite on these styles. (`style=switch` is a deprecated alias that resolves to `toggle`.)
          - **segmented:** segments, selectedSegment
          - **recorder:** recording, playing, duration, outputPath, format (m4a | caf)
          - **scene3d:** object (source path — preferred), modelURL (resolved path, legacy alias), allowsCameraControl, autoLighting, antialiasing, background3d
          - **image:** imageFilter, imageFilterIntensity (along with the standard part properties)
          - **progressView:** value (0..total), progressTotal (default 100), progressIsCircular (true/false), progressIsIndeterminate (true/false), progressLabel, progressTint (hex), progressDecimals (alias `decimals` — 0 default, integral steps; raise for fractional precision; same contract as gauge)
          - **gauge:** value (gaugeMin..gaugeMax), gaugeMin (default 0), gaugeMax (default 100), gaugeStyle (circular | linear), gaugeTint (hex), gaugeLabel, gaugeMinLabel, gaugeMaxLabel, gaugeDecimals (alias `decimals` — 0 default, integral steps; raise for fractional precision)
          - **button (style=link):** url (target — http / https / mailto only; other schemes are refused at click time), textContent (visible link text; defaults to url if empty)
          - **button (style=popup):** popupItems (newline-separated labels), textContent (currently-selected label)
          - **field (style=search):** textContent (current search text — use `the text of field "search"`); fields with this style fire `searchChanged` on debounced keystroke and `searchSubmitted` on Return.
          - **divider:** dividerOrientation (horizontal | vertical), dividerThickness (pixels, default 1), dividerColor (hex)
        **Global properties:** the date, the time, the ticks, the seconds, the mouseLoc (returns "x,y"), the mouseH, the mouseV, the shiftKey, the optionKey, the commandKey, the version.

        ## System & lifecycle messages

        Hype dispatches messages to a part / card / background / stack when the
        underlying engine event happens. Write `on <messageName> ... end <messageName>`
        in a script to react.

        **Generic part / mouse / keyboard:** mouseUp, mouseDown, mouseEnter, mouseLeave, mouseStillDown, openCard, closeCard, openStack, closeStack, openBackground, closeBackground, idle, openField, closeField, returnInField, tabInField, keyDown, deleteButton, deleteField.
        **Calendar (`recorder` style — fires on the calendar part):** dateChanged.
        **ColorWell:** colorChanged.
        **Stepper / Slider / Gauge:** valueChanged. (Gauge fires on user click/drag when `enabled` is true.)
        **Segmented:** selectionChanged.
        **Button (style=toggle / checkBox):** mouseUp (the click also flips `hilite` automatically).
        **Field (style=search):** searchChanged (param 1 = current text; fires debounced as user types when searchSendsImmediately is true), searchSubmitted (param 1 = final text; fires on Return).
        **Audio Recorder:** recordingStarted, recordingStopped, playbackStarted, playbackStopped.
        **Map:** locationResolved (fires after a successful async geocode of `the maplocation`; read `the centerLat / centerLon of me` inside the handler to get the resolved coords).
        **Scene3D:** modelLoadFailed (param 1 = reason string; fires when SCNScene returns nil or STL conversion fails — use to show a fallback or log an error).
        **ProgressView:** progressFinished (fires once when value reaches total; resets when value drops below total).
        **AI tools:** aiToolFinished, aiToolFailed.

        ## Operators and precedence

        **Arithmetic:** `+`  `-`  `*`  `/`  `mod`  `div`  `^` (power)
            put 5 + 3 into x         -- 8
            put 17 mod 5 into x      -- 2
            put 17 div 5 into x      -- 3   (integer division)
            put 2 ^ 8 into x         -- 256

        **Comparison:** `=`  `is`  `<>`  `!=`  `≠`  `is not`  `<`  `<=`  `>`  `>=`
            if x = 5 then ...        -- numeric or string equality (case-insensitive)
            if name is "OK" then     -- same; "is" and "=" are interchangeable
            if x <> 0 then ...       -- "is not", "<>", and "!=" all parse identically
        Equality on strings is CASE-INSENSITIVE. `"OK" is "ok"` is true.

        **Membership / substring:** `contains`  `is in`  `is not in`
            if field "log" contains "error" then ...
            if "error" is in field "log" then ...    -- same meaning, reversed sides
            if needle is not in haystack then ...
        These are CASE-INSENSITIVE substring tests.

        **Geometry:** `is within`  `is not within`
            if "100,50" is within "0,0,200,200" then ...    -- point in rect
            if the mouseLoc is within the rect of button "OK" then ...

        **Type tests:** `is a number | integer | float | logical | boolean | point | rect | empty`
        and the negated forms `is not a ...`
            if x is a number then put x * 2 into x
            if x is empty then put "(default)" into x
            if it is a point then set the loc of me to it      -- "x,y" string
            if r is a rect then set the rect of me to r        -- "l,t,r,b" string
        `logical` and `boolean` are synonyms — both match `"true"`/`"false"`.

        **Existence:** `there is a <kind> "<name>"`  /  `there is no <kind> "<name>"`
            if there is a button "OK" then go next
            if there is no field "result" then create_field ...
        The kind matches any object reference: button, field, image, card, sprite, label, shape, etc.

        **Boolean:** `and`  `or`  `not`  (and `!` as an alias for `not`)
            if x > 0 and x < 10 then ...
            if not the visible of image "logo" then ...
            if !state then ...

        **String concatenation:** `&` (tight, no space) and `&&` (one space between)
            put "x=" & x into msg                  -- "x=5"
            put "Score:" && score into label       -- "Score: 5"

        **Precedence (loosest at top, tightest at bottom):**
            or
            and
            not
            comparisons   ( = is <> != ≠ < <= > >= contains "is in" "is within" "is a" )
            concatenation ( & && )
            + -
            * / mod div
            ^
            unary -, await
            primary (literal, variable, the X, paren group, ordinal, chunk, function call)

        Concrete precedence pitfalls:
        - **`&` binds TIGHTER than comparison** but LOOSER than `+`/`-`. `if "x=" & x is "x=5" then` works as written, but `a + b & "!"` parses as `(a + b) & "!"`.
        - **`not` binds tighter than `and`/`or`.** `not a or b` is `(not a) or b`, never `not (a or b)`.
        - **Unary minus after a binary operator works**, e.g. `x = -1`, but at the start of a function call argument prefer parens: `random(-5)` not `random -5`.
        - **When in doubt, parenthesize.** Parens are always free.

        ## Chunks (text slicing)
            word 3 of "alpha beta gamma"      -- "gamma"
            item 1 of "a,b,c"                 -- "a"
            line 2 of field "list"
            char 3 of "hello"                 -- "l"
            the number of words in s
            the length of "hello"             -- 5

        Chunk types: `char` / `character`, `word`, `item`, `line`. Plural forms (`chars`, `characters`, `words`, `items`, `lines`) are accepted as synonyms.

        **Ranges:** `<chunk> N to M of X` returns the joined slice.
            put words 2 to 4 of "the quick brown fox jumps" into s     -- "quick brown fox"
            put items 2 to -1 of "a,b,c,d" into s                       -- "b,c,d" (negative = from end)
            put chars 1 to 5 of "hello world" into s                    -- "hello"

        **Ordinals:** `first`, `second`, `third`, ..., `last`, `middle`, `any` work in place of a numeric index.
            put the first word of s into firstWord
            put the last item of "a,b,c" into x       -- "c"
            put the middle line of field "log" into m
            put any item of "red,green,blue" into pick    -- random pick

        **Chunks are READ-ONLY.** There is NO chunk-write or `put before/after chunk` form. To "edit" a chunk, splice and write back the whole field:
            -- WRONG: set the word 3 of field "X" to "newWord"   (parse error)
            -- WRONG: put "Hi " before word 3 of field "X"        (parse error)
            -- RIGHT: read, splice with concatenation, write back
            put word 1 to 2 of field "X" && "newWord" && word 4 to -1 of field "X" into field "X"

        ## Control flow

        **Multi-line `if/then/else`:**
            if x > 10 then
              put "big" into field "out"
            else
              put "small" into field "out"
            end if

        **Single-line `if/then[/else]`** (no `end if` needed):
            if x > 0 then put "positive" into field "out"
            if x = 0 then put "zero" into field "out" else put "negative" into field "out"

        **`else if` does NOT exist.** There is no `elseif` or `else if` keyword. Use a NESTED if inside the else, with its own `end if`:
            if x = 1 then
              put "one" into field "out"
            else
              if x = 2 then
                put "two" into field "out"
              else
                if x = 3 then
                  put "three" into field "out"
                else
                  put "other" into field "out"
                end if
              end if
            end if

        For long ladders the single-line form keeps it tidy:
            if x = 1 then put "one" into field "out"
            else if x = 2 then put "two" into field "out"        -- WRONG: parse error
            -- Correct ladder:
            if x = 1 then put "one" into field "out"
            else if x = 2 then put "two" into field "out"        -- still WRONG
            -- Use a chain of single-line ifs and `exit` early instead:
            if x = 1 then put "one" into field "out"
            if x = 2 then put "two" into field "out"
            if x = 3 then put "three" into field "out"

        **Loops:**
            repeat 5 times                    -- fixed count
              beep
            end repeat

            repeat for 5                      -- accepted alias of "repeat 5 times"
              beep
            end repeat

            repeat with i = 1 to 10           -- counter
              put i into line i of field "list"
            end repeat

            repeat with i = 10 down to 1      -- countdown
              put i into field "out"
              wait 1
            end repeat

            repeat while x < 100              -- conditional
              add 1 to x
            end repeat

            repeat until x >= 100             -- inverse conditional
              add 1 to x
            end repeat

        **Loop control & handler control:**
            exit repeat        -- break out of the innermost repeat
            next repeat        -- continue at the top of the loop
            exit mouseUp       -- stop this handler (must name the handler)
            pass mouseUp       -- stop this handler AND let the next handler in the chain see the message
            return x           -- exit this handler with a value (caller reads it via `the result` only on user functions; for messages, the value is discarded)

        ## Navigation
            go next            go previous        go first         go last
            go card "name"     go card 3          go back
            visual effect dissolve               -- queued for the next `go` (UNQUOTED literal)
            visual effect wipe left              -- multi-word literals also work
            visual effect iris open
            visual effect "dissolve"             -- the quoted form is also accepted
        Effect names: dissolve, wipe (left|right|up|down), iris (open|close), barn (door open|door close), zoom (in|out|open|close), scroll (left|right|up|down), checkerboard, venetian blinds, push (left|right|up|down).

        ## Dialogs
            answer "Are you sure?"               -- alert with OK; `it` is set to "OK" or the chosen button
            answer "Save?" with "Save" or "Discard" or "Cancel"   -- 3-way choice
            ask "What is your name?"             -- input prompt; typed text in `it`
            ask "Pick:" with "default text"      -- prefilled input
        After every `ask`/`answer`, READ FROM `it` IMMEDIATELY — any subsequent command can overwrite it.

        ## Async rules
        HypeTalk is sync by default. A handler only suspends when it uses one of the explicit async forms below.

        **Blocking / legacy forms**
            ask ai "Summarize this card"         -- blocks until Ollama replies
            put ollama("Write a title") into field "out"
            put the aiModels into field "out"

        **Suspending forms**
            wait 2
            wait until the sound is "done"
            put await ollama("Summarize this card") into field "out"
            put await ollamaModels() into field "out"
            put request "http://localhost:8080/health" into reqId

        **Callback forms**
            ask ai "Write a mission briefing" with message "aiFinished"
            request "http://localhost:8080/data" with message "requestFinished"
            listen for http on port 8080 with message "incomingRequest"
            listen for tcp on port 9000 with message "socketEvent"
            connect to host "127.0.0.1" on port 9000 with message "socketEvent"

        Callback handlers receive IDs plus an event name:
        - AI / HTTP request callbacks: `requestId, eventName`
        - TCP callbacks: `connectionId, eventName`
        Common event names: `completed`, `error`, `request`, `connected`, `data`, `closed`, `stopped`.

        ## Sound
            play "Glass"                             -- play macOS system alert sound
            play "boing"                             -- play built-in HyperCard sound
            play "mySound"                           -- play audio clip from sprite repository
            play "harpsichord" "c d e f g a b c5"    -- play notes with instrument
            play "flute" tempo 160 "c4q e4q g4q c5h" -- notes with custom tempo
            play stop                                -- stop current sound
            beep                                     -- system alert sound (once)
            beep 3                                   -- system alert sound (3 times)
            wait 2                                   -- pause script for 2 seconds
            wait 2 seconds                           -- same with explicit unit
            wait until the sound is "done"           -- block until playback ends
            put the sound into s                     -- "done" or name of playing sound
        Note format: NAOD (Name-Accidental-Octave-Duration). Name: c d e f g a b r(rest). Accidental: # or b. Octave: 1-8 (default 4). Duration: w(whole) h(half) q(quarter) e(eighth) s(16th) t(32nd) x(64th). Suffix: .(dotted) 3(triplet). Octave and duration carry forward to next note.
        System alert sounds: Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink. Also supports macOS ToneLibrary alert tones and ringtones (e.g. Sonar, Chime, Bamboo, Aurora, Bloom, Calypso, etc.) by name.

        ## Animation (standard parts)
            animate the loc of button "ball" to "400,300" over 0.5
            animate the left of field "panel" to 0 over 1 seconds
            animate the rotation of shape "spinner" to 360 over 2
            animate the width of button "bar" to 300 over 0.3
            put the animating of button "ball" into busy  -- "true" during, "false" after
        Animatable properties: left, top, width, height, rotation, loc.
        Uses ease-in-out cubic for smooth acceleration/deceleration.
        The command is non-blocking -- execution continues immediately.

        ## Sprite scenes (SpriteKit)
            create sprite "player" in scene "main" with asset "hero"
            remove sprite "enemy"
            pause scene "main"                   resume scene "main"
            set the loc of sprite "player" to "200,300"
            set the velocity of sprite "ball" to "100,-50"
            apply force "10,20" to sprite "ball"
            apply impulse "5,0" to sprite "ball"
            set the text of label "score" to "Score: " & score

        ## Tile maps
            create tilemap "ground" columns 20 rows 15 tilesize 32 with tileset "grass_tiles"
            set tile 3,5 of tilemap "ground" to 7        -- stamp tile 7 at col 3, row 5
            fill tilemap "ground" with 1                  -- paint every cell with tile 1
            clear tilemap "ground"                        -- reset every cell to empty (-1)
            put the tile at 3,5 of tilemap "ground" into t  -- read a cell's tile index
        Tile indices are 0-based left-to-right, top-to-bottom in the tileset sprite sheet. Use -1 for "empty cell". The tileset asset must be classified first (via the Sprite Repository or the `classify_asset_as_tileset` tool) — a plain unclassified image will render as a single vertical strip, since `tileSetColumns` defaults to 1 when no metadata is present.

        ## Networking
            put request "http://localhost:8080/health" into reqId
            put the status of request reqId into s
            put the body of request reqId into t
            put the header "Content-Type" of request reqId into h

            request "http://localhost:8080/submit" method "POST" headers "Content-Type: application/json" body "{\"score\":42}" with message "requestFinished"

            on requestFinished requestId, eventName
              if eventName is "completed" then
                put the body of request requestId into field "output"
              else
                put the error of request requestId into field "output"
              end if
            end requestFinished

            listen for http on port 8080 host "127.0.0.1" with message "networkRequest"

            on networkRequest requestId, eventName
              if eventName is "request" then
                reply to request requestId with status 200 body "hello from Hype"
              end if
            end networkRequest

            listen for tcp on port 9000 host "127.0.0.1" with message "socketEvent"
            connect to host "127.0.0.1" on port 9000 with message "socketEvent"
            send "ping" to connection someConnectionId
            close connection someConnectionId
            stop listener someListenerId

        Runtime objects:
        - `request <id>` supports: `status`, `state`, `method`, `url`, `body`, `error`, `statusCode`, and `header "Name"`.
        - `listener <id>` supports: `status`, `state`, `host`, `port`, `transport`, `callbackMessage`.
        - `connection <id>` supports: `status`, `state`, `host`, `remoteAddress`, `port`, `remotePort`, `lastData`, `body`, `error`.

        ## Canonical patterns

        **Button that navigates:**
            on mouseUp
              go next
            end mouseUp

        **Toggle a part's visibility on click:**
            on mouseUp
              set the visible of image "logo" to not the visible of image "logo"
            end mouseUp

        **React to a calendar selection:**
            on dateChanged
              put the selectedDate of calendar "due" into d
              put "Due: " & d into field "status"
            end dateChanged

        **Navigate a PDF programmatically:**
            set the currentPage of pdf "manual" to 5
            -- Other PDF properties: pdfurl, displayMode (single/continuous/twoUp), autoScales.

        **React to a color pick:**
            on colorChanged
              put the color of colorWell "fill" into hex
              set the fillColor of shape "swatch" to hex
            end colorChanged

        **React to a numeric control change (stepper / slider):**
            on valueChanged
              put the value of slider "volume" into v
              set the textContent of field "level" to v
            end valueChanged
            -- Stepper has the same `value` property and the same
            -- `valueChanged` message.

        **React to a toggle / switch flip:**
            -- Switch / checkbox / toggle styled buttons flip `hilite`
            -- on click. Use mouseUp (the dedicated `valueChanged`
            -- event was retired with the standalone toggle PartType):
            on mouseUp
              if the hilite of me then
                play stop
              end if
            end mouseUp

        **Apply a filter to an image:**
            set the imageFilter of image "logo" to "sepia"
            set the imageFilterIntensity of image "logo" to 0.5
            -- Filters: "" (none), sepia, blackwhite, mono, noir, blur,
            -- vignette, invert, posterize, comic, process, transfer,
            -- instant, fade, tonal, chrome.
            -- Intensity (0..1) affects sepia, blur, vignette, posterize.

        **Load a 3D model (STL, USDZ, OBJ, SCN, DAE):**
            -- Preferred: `object` accepts .stl and auto-converts to OBJ (cached).
            set the object of scene3d "model" to "/path/to/cube.stl"
            -- Non-STL formats work the same way:
            set the object of scene3d "model" to "/path/to/cube.usdz"
            -- Read back the author-visible source path:
            put the object of scene3d "model" into src
            -- The user can orbit/zoom by default; toggle off with:
            -- `set the allowsCameraControl of scene3d "model" to false`
            -- Handle load failure:
            on modelLoadFailed reason
              put "3D load failed: " & reason into field "status"
            end modelLoadFailed

        **Audio recorder — record, save to a chosen file, play back:**
            -- Pin the file path BEFORE starting (otherwise a temp file
            -- under FileManager.temporaryDirectory is auto-generated):
            set the outputPath of recorder "memo" to "/Users/me/voice-memo.m4a"

            -- Start / stop recording (toggle from a button handler):
            on mouseUp
              if the recording of recorder "memo" then
                set the recording of recorder "memo" to false
              else
                set the recording of recorder "memo" to true
              end if
            end mouseUp

            -- Play back the most-recent recording:
            set the playing of recorder "memo" to true
            -- ...stops automatically when the file ends, or:
            set the playing of recorder "memo" to false

            -- React to lifecycle messages:
            on recordingStarted
              put "Recording..." into field "status"
            end recordingStarted
            on recordingStopped
              put "Saved " & the outputPath of me into field "status"
            end recordingStopped
            on playbackStarted
              put "Playing back" into field "status"
            end playbackStarted
            on playbackStopped
              put "Done" into field "status"
            end playbackStopped

            -- Live polling: `the duration of recorder "X"` ticks every
            -- 0.1s while recording. `the recording of <r>` and
            -- `the playing of <r>` return "true"/"false". Format
            -- ("m4a" or "caf") is set via `the format of recorder "X"`.

        **React to a segmented selection:**
            on selectionChanged
              put the selectedSegment of segmented "tabs" into idx
              if idx is 0 then go to card "Home"
              if idx is 1 then go to card "Inbox"
              if idx is 2 then go to card "Settings"
            end selectionChanged

        **Re-center a map by location string OR by lat/lon:**
            -- Easiest: type a place name, address, or US ZIP and the
            -- host geocodes it for you (async; results land in
            -- centerLat/centerLon when it resolves).
            -- Note: use `mapLocation` (not `location`) in HypeTalk
            -- since `location` is the geometry center-point of any part:
            set the mapLocation of map "store" to "Rogue River, OR"
            set the mapLocation of map "store" to "97537"
            set the mapLocation of map "store" to "Eiffel Tower"

            -- Or set lat/lon directly (no geocoding needed):
            set the centerLat of map "store" to 37.7749
            set the centerLon of map "store" to -122.4194
            set the span of map "store" to 0.02

            -- React to a successful geocode (fires after async lookup):
            on locationResolved
              put "Now showing " & the centerLat of me & "," & the centerLon of me into field "status"
            end locationResolved

            -- Add pins via the AI tool `add_map_annotation`, or
            -- replace the entire annotation set by setting
            -- `annotations` to a JSON string like
            -- '[{"lat":37.77,"lon":-122.42,"title":"HQ"}]'.

        **Track progress and react when complete:**
            -- Advance a linear progress bar one step at a time:
            on mouseUp
              set the value of progressView "bar" to (the value of progressView "bar") + 10
            end mouseUp

            -- React when progress hits 100%:
            on progressFinished
              put "Done!" into field "status"
            end progressFinished

        **Open a URL — use a button styled as a link:**
            -- Set the button's style to "link" (underlined text, blue
            -- color) and put the destination in the `url` field.
            -- Clicks dispatch an http/https/mailto open (other
            -- schemes are refused for safety).
            set the style of button "docs" to "link"
            set the url of button "docs" to "https://example.com"
            -- React in the button's mouseUp handler if you need it:
            on mouseUp
              put "Opened the docs page" into field "status"
            end mouseUp

        **Popup menu — use a button styled as popup:**
            -- popupItems is newline-separated labels. The selected
            -- label appears in the button's textContent. Per-item
            -- scripts aren't supported — branch on textContent in
            -- the button's mouseUp handler instead.
            set the style of button "actions" to "popup"
            set the popupItems of button "actions" to "Delete" & return & "Archive" & return & "Share"
            on mouseUp
              if the textContent of me is "Delete" then
                -- handle delete
              end if
            end mouseUp

        **Live search — use a field styled as search:**
            set the style of field "find" to "search"
            on searchChanged query
              -- fires debounced (~300 ms) while the user types
              put query into field "filter"
            end searchChanged

            on searchSubmitted query
              -- always fires when the user presses Return
              put query into field "result"
            end searchSubmitted

        **Flash a part — hide, wait, show:**
            on mouseUp
              set the visible of image "flash" to false
              wait 1 second
              set the visible of image "flash" to true
            end mouseUp

        **Stack-level initialisation — `on openStack` ALWAYS wraps:**
            on openStack
              global score
              put 0 into score
            end openStack
            -- This handler attaches to the STACK itself
            -- (`set_stack_script` tool). The `on openStack ... end
            -- openStack` block is REQUIRED — you cannot just write
            -- `global score` and `put 0 into score` at top level;
            -- the dispatcher only runs handler bodies. The same
            -- rule applies to `on openCard / closeCard`, `on
            -- openBackground / closeBackground`, `on idle`, etc.
            -- Top-level statements outside a handler are dead code.

        **Nudge a sprite every frame (read-modify-write `the loc`):**
            on frameUpdate
              put the loc of sprite "enemy" into pos
              put item 1 of pos into ex
              put (item 2 of pos) + 2 into ey
              set the loc of sprite "enemy" to ex & "," & ey
            end frameUpdate
            -- Sprite position is the comma-string `the loc of sprite
            -- "X"` (alias `position` / `location`). There is NO
            -- `the y of sprite "X"` or `the x of sprite "X"` getter
            -- — read `the loc`, split with `item 1 of` / `item 2 of`,
            -- and write back the full `"x,y"` string.

        **Create a brand-new card — pass the name explicitly:**
            -- AI tool form (the only way scripts can create cards):
            -- create_card(name="about", background_name="title_bg")
            -- Without `name`, the new card gets an autogenerated
            -- name like "Card 4" — almost never what the user
            -- asked for. Always pass `name` when the user named
            -- the new card.

        **React when a field's text changes — use `on closeField`, NOT `on change`:**
            on closeField
              put "updated" into field "shared_status"
            end closeField
            -- closeField fires when the user finishes editing (focus loss /
            -- Tab / Return). HypeTalk has no `on change` handler.

        **Idle logic (use for custom state, not physics simulation):**
            on idle
              global pulse
              if pulse is empty then put 0 into pulse
              add 1 to pulse
              set the text of label "debug" to "tick " & pulse
            end idle

        **Keyboard-controlled physics sprite:**
            on keyDown
              if the key is "w" then set the velocity of sprite "player" to "0,220"
              if the key is "s" then set the velocity of sprite "player" to "0,-220"
              if the key is "a" then set the velocity of sprite "player" to "-220,0"
              if the key is "d" then set the velocity of sprite "player" to "220,0"
            end keyDown

            on keyUp
              set the velocity of sprite "player" to "0,0"
            end keyUp

        **Collision scoring:**
            on beginContact otherName
              global score
              if otherName is "goal" then
                add 10 to score
                set the text of label "score" to "Score: " & score
              end if
            end beginContact
            -- Inside `on beginContact`, the parameter (or `the
            -- otherNode`) is the name of the colliding sprite on
            -- the OTHER side of the contact. The sprite whose
            -- script is running is already known. Don't try to
            -- read `contact.nodeA` / `contact.nodeB` — those are
            -- not HypeTalk expressions.

        **Cursor-over-sprite reaction (e.g. accelerate a ball when
        the cursor touches it):**
            on frameUpdate
              if the hoveredSprite is "blue_ball" then
                set the velocityX of sprite "blue_ball" to (the velocityX of sprite "blue_ball") * 1.5
                set the velocityY of sprite "blue_ball" to (the velocityY of sprite "blue_ball") * 1.5
              end if
            end frameUpdate
            -- `the hoveredSprite` (or `the spriteUnderMouse`)
            -- returns the name of the sprite currently under the
            -- cursor in the scene, or empty string when no sprite
            -- is under it. This is the ONLY correct way to answer
            -- "is the cursor over sprite X?" — do NOT invent
            -- grammar like `the name of node at mouse location`
            -- or `if sprite X intersects the mouse`; those will
            -- not parse. Wrap the body in a one-shot latch if
            -- you want the action to fire once per hover (not
            -- every frame while the cursor stays over the sprite).

        ## Built-in functions

        Functions are called with paren syntax (always safe) or — for unary built-ins — prefix syntax:
            put random(10) into r      -- paren form
            put random 10 into r       -- prefix form (HyperTalk idiom, also OK)
            put abs(-5) into n         -- 5
            put sqrt 16 into s         -- 4
            put length "hello" into l  -- 5

        **Prefix-form rule.** The argument is a single PRIMARY — number, string, variable, paren group, `the X`, `it`/`me`, ordinal, or chunk. Anything more complex still parses, but greedily: `random 2 - 1` is `random(2) - 1`. `random a + 1` is `(random a) + 1`. For computed arguments, parenthesize: `random(a + 1)`.

        Allow-list of prefix-form unary built-ins: `random`, `abs`, `round`, `trunc`, `sqrt`, `sin`, `cos`, `tan`, `atan`, `exp`, `ln`, `log2`, `length`, `value`, `charToNum`, `numToChar`.

        **Numeric:**
            random(N)            -- random integer in [1, N]
            abs(x)               -- absolute value
            round(x) trunc(x)    -- nearest integer / drop fraction
            sqrt(x)
            sin(x) cos(x) tan(x) atan(x)        -- radians
            exp(x) exp1(x) exp2(x)              -- e^x, e^x - 1, 2^x
            ln(x) ln1(x) log2(x)                -- natural log, ln(1+x), log base 2
            min(a, b, ...)  max(a, b, ...)      -- 1+ args
            sum(a, b, ...)  average(a, b, ...)  -- 1+ args
            annuity(rate, periods)              -- HyperTalk financial helper
            compound(rate, periods)             -- HyperTalk financial helper

        **Strings:**
            length(s)                            -- number of characters
            offset(needle, haystack)             -- 1-based char offset, 0 if not found
            charToNum(s)                         -- ASCII/UTF-16 code of char 1
            numToChar(n)                         -- single character
            value(s)                             -- coerce to number (0 if non-numeric)

        **System / lifecycle (no argument; can be called as `the X` too):**
            the date           the time          the ticks         the seconds
            the version        the systemVersion the screenRect
            the diskSpace      the heapSpace     the stackSpace
            the mouseLoc       the mouseH        the mouseV
            the shiftKey       the optionKey     the commandKey   -- return "down" or "up"
            the hoveredSprite  the spriteUnderMouse                -- name or "" if none
            the key                                                  -- inside keyDown/keyUp only
            the otherNode                                            -- inside begin/endContact only

        **AI / models:**
            ollama(prompt)                       -- sync; result returned, also in `it`
            await ollama(prompt)                 -- async variant
            ollamaModels()  /  the aiModels      -- list installed Ollama models, newline-separated

        Note: `the result` (the classic HyperTalk "what did the last command do?") is NOT implemented in this dialect — it always returns `""`. Read return values directly: synchronous calls put their result in `it`; async/network forms invoke a callback handler with the request UUID.

        ## Stub commands & getters — recognized but no-op

        These exist in the lexer/parser for HyperTalk lineage but currently do nothing observable. **Do not rely on them for real behavior.** Use the alternative shown.

        | Stub | What it does today | Alternative |
        | --- | --- | --- |
        | `find "needle" in field "X"` | Stores the search string in `it`. Does NOT highlight / scroll / locate. | `if field "X" contains "needle" then ...` for membership; iterate `line N of field "X"` for line-level search. |
        | `select word 3 of field "X"` | No selection happens; field text is unaffected. | None — programmatic selection is not exposed. |
        | `do "<expression>"` | No-op (parsed but not evaluated). | Inline the expression directly. |
        | `push card`, `pop card` | No-op. | Track navigation in a global if you need a stack. |
        | `clickAt`, `dial`, `print`, `reset`, `run`, `doMenu`, `copy template`, `type "X"` | No-op (recognized as legacy verbs). | Use the relevant explicit command (`go card "X"`, `play "Glass"`, `set the textContent of field "Y" to "X"`). |
        | `the result` | Always returns `""`. | Read sync return values from `it`; for async, use the callback handler and `the body of request <id>`. |
        | `the foundChunk` / `the foundField` / `the foundLine` / `the foundText` | Always return `""`. | Same as `find` row above. |
        | `the params` / `the paramCount` / `param 1` | Always return `""`. | Declare named handler parameters: `on requestFinished requestId, eventName`. |
        | `the selectedChunk` / `the selectedField` / `the selectedLine` / `the selectedText` | Always return `""`. | Read field text and parse it yourself. |
        | `the target` | Returns `""`. | Use `the name of me` or pass identifiers explicitly. |

        ## Common AI hallucinations to AVOID
        - **`int`** is NOT a HypeTalk keyword. To negate a number, just write `-1`, not `-int 1`.
        - **`float`, `string`, `bool`** are not keywords either. All HypeTalk values are strings coerced to numbers during arithmetic.
        - **`function random(N)`** is not a user-definable function. Use the built-in directly.
        - **`var` / `let`** don't exist. Variables are created on first use with `put 5 into x`.
        - **`return` at top level of a handler** is fine, but a handler body is not a function body — use `exit <name>` to stop early.
        - **`else if x = 1 then`** is a parse error. There is NO `elseif`/`else if` keyword. Nest an `if` inside the `else` branch with its own `end if`, OR use a chain of single-line `if/then` statements (see Control flow).
        - **`x starts with "foo"` / `x ends with "foo"`** are NOT operators. Use `char 1 to 3 of x is "foo"` for prefix, `char -3 to -1 of x is "foo"` for suffix, or `x contains "foo"` if position doesn't matter.
        - **`set the word 3 of field "X" to "Hi"`** is a parse error. Chunks are read-only — splice and write the whole field back.
        - **`put "Hi" before/after word 3 of field "X"`** is a parse error too. `put before/after` only targets variables, `it`, or whole object refs (e.g. `put "Hi" before field "X"`).
        - **`do "put 5 into x"` (eval string as script)** is a no-op. Inline the code directly.
        - **`find "x" in field "Y"` followed by reading `the foundChunk`** does not work — both are stubs. Use `if field "Y" contains "x" then ...`.
        - **`the result` after `request ...` / `ask ai ...`** always returns `""`. The sync forms (`ollama(prompt)`, `ask "question"`) put the answer in `it`; the async forms (`request ... with message ...`) deliver it to the callback handler — read `the body of request <id>` there.
        - **`the params`, `the paramCount`, `param 1`** are all stubs. Declare named parameters in the handler signature: `on requestFinished requestId, eventName`.
        - **`send "mouseUp" to button "OK"`** does not trigger a button's handler. The `send` keyword in this dialect is only `send <data> to connection <id>` for TCP. Refactor shared logic into a helper handler (or just call a function-style handler) instead.
        - **Named colors like `red`, `blue`, `green`** are NOT accepted as color values. Use `"#RRGGBB"` hex strings (or `""` for none).
        - **`node at <location>`** is NOT a HypeTalk expression. To find the sprite under the cursor, use `the hoveredSprite` / `the spriteUnderMouse`. There is no `at` keyword for spatial queries.
        - **`contact.nodeA` / `contact.nodeB`** do not exist — HypeTalk has no dot-property syntax. Inside `on beginContact` or `on endContact`, use the handler parameter or `the otherNode`, which carries the name of the colliding sprite on the other side of the contact.
        - **Bare sprite names as references**: always write `sprite "blue_ball"`, never bare `blue_ball`. A bare identifier is treated as a variable lookup and silently returns empty.
        - **`end` without the block name**: always write `end if`, `end mouseUp`, `end frameUpdate`. Bare `end` will not parse.
        - **`the velocityX of physicsBody of sprite "X"`** is tolerated (the parser drops the `physicsBody` wrapper) but the canonical form is `the velocityX of sprite "X"` — physics properties live directly on sprite nodes in HypeTalk.
        - **Comparing `me` to a string name:** `if me is "OK" then ...` will never match. `me` is a UUID; compare with `the name of me` instead.
        - **Boolean-y strings like `"yes"`, `"on"`:** these are FALSY. Only `"true"` (case-insensitive) and non-zero numbers are truthy. Compare explicitly: `if x is "yes" then`.

        ## Generation rules
        - Wrap handler bodies in `on <name> ... end <name>` blocks. The only exception is a bare command passed as a button's `script` tool argument (e.g. `go next`), which Hype auto-wraps in `on mouseUp ... end mouseUp`.
        - Quote object names with double quotes: `button "OK"`, not `button OK`.
        - Points are `"x,y"` strings (comma, no spaces). Rects are `"left,top,right,bottom"`.
        - Colors are `"#RRGGBB"` hex strings.
        - Names are case-insensitive in lookup but case is preserved on display; match the object's actual name when referring to it.
        - Use `global <name>` before reading or writing a shared variable inside a handler. Globals persist across idle ticks and handler calls for the life of the stack session, so `on idle / global counter / add 1 to counter / end idle` actually increments `counter` over time.
        - Be explicit about async intent. Use `await ...` for one-shot async results you need immediately. Use `with message "handlerName"` for long-lived jobs, listeners, and streaming/network callbacks.
        - Treat any request that touches a sprite area, scene, or sprite node as SpriteKit scene authoring first, not as generic part scripting.
        - For SpriteKit motion, bouncing, gravity, and collision behavior, prefer native physics bodies, restitution, velocity, and actions. Do not simulate these with `on idle` or `on frameUpdate` unless the user explicitly asks for custom script-driven movement.
        - If a SpriteKit request needs input handling, use handlers like `keyDown`, `keyUp`, `beginContact`, or `endContact` to adjust physics state or actions instead of manually updating loc every frame.
        - `me` refers to the script-owning part: `the loc of me`, `set the rotation of me to 45`. Shapes support a `rotation` property (degrees clockwise).
        - Prefer the commands listed above. Do not invent new verbs or SpriteKit method calls — if something is not shown here, it is probably not supported.
        - When unsure about layout, alignment, spacing, or whether your last change rendered correctly, call `capture_card_image` to receive a screenshot of the current card on your next turn.

        ## MANDATORY: validate scripts with `check_script` before storing
        You MUST call the `check_script` tool on every HypeTalk script before
        you submit it to any other tool that stores scripts (`create_button`,
        `create_field`, `create_chart`, `set_part_property` with
        `property="script"`, etc.). This is not optional.

        The iteration loop is:
          1. Generate the HypeTalk script you want to attach.
          2. Call `check_script` with the script as the `script` argument.
          3. If the response starts with `OK:`, you may proceed to the
             storage tool call.
          4. If the response starts with `FAIL:`, read the error message
             (which includes the offending line number), fix the script,
             and call `check_script` again.
          5. Repeat step 4 until `check_script` returns `OK:`.
          6. ONLY THEN call the storage tool (`create_button`,
             `set_part_property`, etc.) with the validated script.

        Do not skip step 2 on the belief that a script "looks fine". The
        parser surfaces subtle errors (missing `end if`, misspelled event
        names, the `-int N` hallucination, improper chunk syntax, wrong
        operator precedence) that are not obvious from inspection. Silently
        storing an invalid script results in a part whose handlers never
        fire — the user will see nothing happen and have no idea why.

        A validated script that passed `check_script` is still subject to
        RUNTIME errors (e.g. referring to a nonexistent sprite at execution
        time). `check_script` only guarantees the script is syntactically
        well-formed, not that its actions will succeed against live state.

        ## Host-side draft gate — what `__HYPE_INTERNAL_DRAFT_REFUSED_v1:` means
        Even when you call `check_script` first and it returns OK, the host
        validates your draft a SECOND time at storage time. It also performs
        reference resolution (does the part/asset you mention actually exist?)
        and checks for forbidden patterns (markdown fences, leaked chat
        tokens). If the host refuses your draft, the storage tool returns a
        result string starting with `__HYPE_INTERNAL_DRAFT_REFUSED_v1:`. Read
        the failure list, fix the script, and call the SAME storage tool
        again. The host iterates with you — you don't need a user nudge.
        Iteration stops automatically after a small number of attempts.
        """
}
