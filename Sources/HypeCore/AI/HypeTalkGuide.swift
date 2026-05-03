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
/// The guide is intentionally **concise** (under ~4 KB, roughly 900
/// tokens) so the injection cost per request stays bounded. It trades
/// narrative prose for structured headings and compact examples that a
/// model can grep by keyword. The complete, verbose reference lives in
/// `HypeTalk-LLM-Context.md` / `HyperTalk_Reference.md` in the repo
/// root — this constant is the curated subset we ship to the model.
public enum HypeTalkGuide {

    /// The HypeTalk authoring guide embedded on every Ollama chat turn.
    ///
    /// Sections:
    ///
    /// 1. Language essentials (character, comments, values, message routing)
    /// 2. Handler syntax and common events
    /// 3. Variables, arithmetic, concatenation, and the `it` variable
    /// 4. Object references (parts and sprite-scene nodes)
    /// 5. Property get/set surface for parts and sprite nodes
    /// 6. Chunk expressions (text slicing)
    /// 7. Control flow
    /// 8. Navigation and visual effects
    /// 9. Dialogs (ask / answer)
    /// 10. Sprite scene commands (SpriteKit)
    /// 11. Canonical handler patterns
    /// 12. Generation rules the model should follow
    public static let llmContext: String = """
        # HypeTalk scripting guide

        HypeTalk is a HyperCard-inspired, case-insensitive, English-like scripting language used inside Hype. Scripts attach to parts (buttons, fields, shapes, images, videos, web views, charts, sprite areas), cards, backgrounds, stacks, and nodes inside sprite scenes, and run in response to events. All values are strings; arithmetic coerces them to numbers when needed. Line comments start with `--`.

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
        openField, closeField, enterKey, keyDown, keyUp, idle,
        openScene, closeScene, sceneDidLoad, frameUpdate,
        beginContact, endContact, actionFinished.

        ## Variables and data
            put "hello" into myVar        -- assign
            put 42 into score
            global score                  -- declare a shared global in this handler
            add 5 to score                -- arithmetic mutators: add, subtract, multiply, divide
            put a & b into result         -- string concatenation (tight)
            put a && b into result        -- concatenation with a single space
        The special variable `it` receives the result of `ask`, `answer`, `get`, and built-ins. `me` is the object whose script is running; `this card`, `this background`, `this stack` are also valid.

        ## Object references
            button "OK"        field "input"       card "home"          card 3
            background "Main"  stack               spritearea "game"
            sprite "player"    label "score"       shape "wall"
            camera "cam"       emitter "fire"      tilemap "map"
            audio "music"      video "intro"       chart "sales"
            calendar "due"     pdf "manual"        map "store"
            colorWell "fill"   stepper "qty"       slider "volume"
            toggle "muted"     segmented "tabs"    recorder "memo"
            scene3d "model"
        Use double-quoted names; bare words are only valid for short keywords.

        ## Properties — get and set
            put the name of button "OK" into n
            set the text of field "input" to "hello"
            set the visible of field "info" to false       -- hide a field
            set the visible of image "logo" to true        -- show an image
            set the visible of button "OK" to false        -- hide a button
            set the visible of image "logo" to not the visible of image "logo"   -- toggle (boolean negation)
            set the loc of sprite "player" to "200,300"      -- points are "x,y" strings

        **Part properties:** name, id, left, top, width, height, right, bottom, loc, rect, visible, enabled, hilite, style, script, textFont, textSize, textAlign, textStyle, textContent, fillColor, strokeColor, strokeWidth, cornerRadius, showName, autoHilite, lockText, url.
        **Sprite-node properties:** loc, size, width, height, rotation, alpha, xScale, yScale, zPosition, hidden, text, fontName, fontSize, fontColor, fillColor, strokeColor, lineWidth, velocity, angularVelocity, density, friction, restitution, damping, dynamic, affectedByGravity, birthRate, particleLifetime, particleSpeed, particleColor, particleScale, emissionAngle, volume, loop, autoplay, target, zoom.
        **Framework control properties** (used as `the <prop> of <kind> "name"`):
          - **calendar:** selectedDate, displayMonth, minDate, maxDate, calendarStyle (graphical | textual | clockAndCalendar)
          - **pdf:** pdfurl, currentPage, displayMode (single | continuous | twoUp), autoScales
          - **map:** centerLat, centerLon, span, mapType (standard | satellite | hybrid | mutedStandard), annotations, location (alias: maplocation / map_location — geocoded place name, address, or US ZIP; resolves async)
          - **colorWell:** color (hex like "#FF5500"), interactive
          - **stepper / slider:** value, min, max, step
          - **toggle:** on (true / false)
          - **segmented:** segments, selectedSegment
          - **recorder:** recording, playing, duration, outputPath, format (m4a | caf)
          - **scene3d:** modelURL, allowsCameraControl, autoLighting, antialiasing, background3d
          - **image:** imageFilter, imageFilterIntensity (along with the standard part properties)
        **Global properties:** the date, the time, the ticks, the seconds, the mouseLoc (returns "x,y"), the mouseH, the mouseV, the shiftKey, the optionKey, the commandKey, the version.

        ## System & lifecycle messages

        Hype dispatches messages to a part / card / background / stack when the
        underlying engine event happens. Write `on <messageName> ... end <messageName>`
        in a script to react.

        **Generic part / mouse / keyboard:** mouseUp, mouseDown, mouseEnter, mouseLeave, mouseStillDown, openCard, closeCard, openStack, closeStack, openBackground, closeBackground, idle, openField, closeField, returnInField, tabInField, keyDown, deleteButton, deleteField.
        **Calendar (`recorder` style — fires on the calendar part):** dateChanged.
        **ColorWell:** colorChanged.
        **Stepper / Slider / Toggle:** valueChanged.
        **Segmented:** selectionChanged.
        **Audio Recorder:** recordingStarted, recordingStopped, playbackStarted, playbackStopped.
        **Map:** locationResolved (fires after a successful async geocode of `the maplocation`; read `the centerLat / centerLon of me` inside the handler to get the resolved coords).
        **AI tools:** aiToolFinished, aiToolFailed.

        ## Chunks (text slicing)
            word 3 of "alpha beta gamma"      -- "gamma"
            item 1 of "a,b,c"                 -- "a"
            line 2 of field "list"
            char 3 of "hello"                 -- "l"
            the number of words in s
            the length of "hello"             -- 5

        ## Control flow
            if x > 10 then
              put "big" into field "out"
            else
              put "small" into field "out"
            end if

            repeat 5 times                    -- fixed count
              beep
            end repeat

            repeat with i = 1 to 10           -- counter
              put i into line i of field "list"
            end repeat

            repeat while x < 100              -- conditional
              add 1 to x
            end repeat

        ## Navigation
            go next            go previous        go first         go last
            go card "name"     go card 3          go back
            visual effect "dissolve"             -- queued for the next `go`

        ## Dialogs
            answer "Are you sure?"               -- alert; result in `it`
            ask "What is your name?"             -- input prompt; typed text in `it`

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

        **React to a toggle flip:**
            on valueChanged
              if the on of toggle "muted" then
                play stop
              end if
            end valueChanged

        **Apply a filter to an image:**
            set the imageFilter of image "logo" to "sepia"
            set the imageFilterIntensity of image "logo" to 0.5
            -- Filters: "" (none), sepia, blackwhite, mono, noir, blur,
            -- vignette, invert, posterize, comic, process, transfer,
            -- instant, fade, tonal, chrome.
            -- Intensity (0..1) affects sepia, blur, vignette, posterize.

        **Load a 3D model:**
            set the modelURL of scene3d "model" to "/path/to/cube.usdz"
            -- The user can orbit/zoom by default; toggle off with
            -- `set the allowsCameraControl of scene3d "model" to false`.

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

        **Flash a part — hide, wait, show:**
            on mouseUp
              set the visible of image "flash" to false
              wait 1 second
              set the visible of image "flash" to true
            end mouseUp

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

        ## Functions
        Built-in functions accept either paren syntax or prefix syntax:

            put random(10) into r      -- paren form (always safe)
            put random 10 into r       -- prefix form (HyperTalk idiom, also OK)
            put abs -5 into n          -- abs of -5, result 5
            put sqrt 16 into s         -- 4
            put length "hello" into l  -- 5

        Prefix syntax works for unary built-ins: `random`, `abs`, `round`, `trunc`, `sqrt`, `sin`, `cos`, `tan`, `atan`, `exp`, `ln`, `log2`, `length`, `value`, `charToNum`, `numToChar`. Prefix binds tight — `random 2 - 1` is `random(2) - 1`, not `random(2 - 1)`. Use parens if you need a computed argument.

        ## Common AI hallucinations to AVOID
        - **`int`** is NOT a HypeTalk keyword. To negate a number, just write `-1`, not `-int 1`.
        - **`float`, `string`, `bool`** are not keywords either. All HypeTalk values are strings coerced to numbers during arithmetic.
        - **`function random(N)`** is not a user-definable function. Use the built-in directly.
        - **`var` / `let`** don't exist. Variables are created on first use with `put 5 into x`.
        - **`return` at top level of a handler** is fine, but a handler body is not a function body — use `exit <name>` to stop early.
        - **`node at <location>`** is NOT a HypeTalk expression. To find the sprite under the cursor, use `the hoveredSprite` / `the spriteUnderMouse`. There is no `at` keyword for spatial queries.
        - **`contact.nodeA` / `contact.nodeB`** do not exist — HypeTalk has no dot-property syntax. Inside `on beginContact` or `on endContact`, use the handler parameter or `the otherNode`, which carries the name of the colliding sprite on the other side of the contact.
        - **Bare sprite names as references**: always write `sprite "blue_ball"`, never bare `blue_ball`. A bare identifier is treated as a variable lookup and silently returns empty.
        - **`end` without the block name**: always write `end if`, `end mouseUp`, `end frameUpdate`. Bare `end` will not parse.
        - **`the velocityX of physicsBody of sprite "X"`** is tolerated (the parser drops the `physicsBody` wrapper) but the canonical form is `the velocityX of sprite "X"` — physics properties live directly on sprite nodes in HypeTalk.

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
