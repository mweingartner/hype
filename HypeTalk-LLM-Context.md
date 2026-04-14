# HypeTalk Language Reference — LLM Context Prompt

You are writing scripts in HypeTalk, a modern HyperCard-inspired scripting language for the Hype app. HypeTalk is case-insensitive and English-like. Scripts attach to objects (buttons, fields, cards, backgrounds, stacks, sprite areas, scenes, and sprite nodes) and fire on events. Messages pass up the chain: scene node → parent group(s) → scene → sprite area part → card → background → stack → Hype.

## Handlers & Control Flow

```
on mouseUp
  -- comment
  if x > 10 then
    put "big" into field "out"
  else
    put "small" into field "out"
  end if
  pass mouseUp  -- pass to next in chain
end mouseUp

on idle
  -- fires repeatedly in browse mode
end idle

repeat 5 times
  beep
end repeat

repeat with i = 1 to 10
  put i into line i of field "list"
end repeat

repeat while x < 100
  add 1 to x
end repeat
exit repeat    -- break
next repeat    -- continue
```

## Events

`on mouseUp`, `on mouseDown`, `on mouseEnter`, `on mouseLeave`, `on mouseWithin`, `on openCard`, `on closeCard`, `on openField`, `on closeField`, `on enterKey`, `on idle`, `on keyDown`, `on keyUp`, `on sceneDidLoad`, `on openScene`, `on closeScene`, `on frameUpdate`, `on beginContact`, `on endContact`, `on actionFinished`

## Variables & Data

```
put "hello" into myVar        -- assign
put 42 into x
global sharedVar              -- declare global
add 5 to x                    -- arithmetic mutators
subtract 1 from x
multiply x by 2
divide x by 3
put "a" & "b" into result     -- concatenation ("ab")
put "a" && "b" into result    -- spaced concat ("a b")
```

## Object References

```
button "name"     -- or btn "name", button 1
field "name"      -- or fld "name", field 1
card "name"       -- or card 1
background "name" -- or bg "name"
spritearea "name" -- or spritearea 1
sprite "name"     -- scene node (any type)
label "name"      -- scene label node
shape "name"      -- scene shape node
```

## Properties (get/set)

```
put the name of button "OK" into n
set the loc of button "OK" to "100,200"
put the text of field "input" into t
set the visible of field "info" to false
```

**Part properties:** name, id, left, top, width, height, right, bottom, loc (x,y), rect (l,t,r,b), visible, enabled, hilite, style, textFont, textSize, textAlign, textStyle, fillColor, strokeColor, strokeWidth, cornerRadius, script, showName, autoHilite, lockText

**Global properties:** the date, the time, the ticks, the seconds, the mouseLoc (x,y), the mouseH, the mouseV, the version

## Chunk Expressions

```
put word 2 of "hello world" into w       -- "world"
put item 1 of "a,b,c" into first         -- "a"
put char 3 of "hello" into c             -- "l"
put line 2 of field "list" into second
put the number of words in x into count
put the length of "hello" into len        -- 5
```

## Functions

`length(x)`, `offset(needle, haystack)`, `random(max)`, `abs(x)`, `round(x)`, `trunc(x)`, `sqrt(x)`, `sin(x)`, `cos(x)`, `tan(x)`, `atan(x)`, `exp(x)`, `ln(x)`, `log2(x)`, `min(a,b)`, `max(a,b)`, `average(a,b,...)`, `annuity(r,n)`, `compound(r,n)`, `charToNum(c)`, `numToChar(n)`, `value(expr)`

## Operators

`+`, `-`, `*`, `/`, `^` (power), `mod`, `div` (integer), `=`, `<>` (not equal), `<`, `>`, `<=`, `>=`, `and`, `or`, `not`, `is`, `is not`, `is in`, `is not in`, `is a number`, `is a point`, `contains`, `is within`, `there is a button "x"`

## Navigation

```
go next           go previous       go first         go last
go card "name"    go card 3         go back
show all cards    create card       create card with background "name"
```

## Dialogs

```
answer "Are you sure?"    -- alert, result in "it"
ask "What is your name?"  -- input, result in "it"
```

## Async Rules

HypeTalk is sync by default. Use explicit async forms when you want suspension or callbacks.

### Blocking / legacy forms
```
ask ai "Summarize this card"
put ollama("Write a short title") into field "out"
put the aiModels into field "out"
```

### Suspending forms
```
wait 2
wait until the sound is "done"
put await ollama("Summarize this card") into field "out"
put await ollamaModels() into field "out"
put request "http://localhost:8080/health" into reqId
```

### Callback forms
```
ask ai "Write a mission briefing" with message "aiFinished"
request "http://localhost:8080/score" with message "requestFinished"
listen for http on port 8080 with message "networkRequest"
listen for tcp on port 9000 with message "socketEvent"
connect to host "127.0.0.1" on port 9000 with message "socketEvent"
```

Callback handlers receive an ID plus an event name:
- AI / HTTP request: `requestId, eventName`
- TCP: `connectionId, eventName`
- Common event names: `completed`, `error`, `request`, `connected`, `data`, `closed`, `stopped`

## AI

```
ask ai "Summarize the current scene"
ask ai "Write a tagline" with model "llama3.2"
ask ai "Write a quest hook" with message "aiFinished"

put await ollama("Summarize this card") into field "out"
put await ollama("llama3.2", "Write a quest hook") into field "out"
put await ollamaModels() into field "out"

put the aiModel into field "out"
put the aiModels into field "out"

on aiFinished requestId, eventName
  if eventName is "completed" then
    put the body of request requestId into field "out"
  end if
end aiFinished
```

## Commands

```
beep              beep 3
wait 2 seconds
hide button "x"   show button "x"
delete button "x"
lock screen       unlock screen
visual effect "dissolve"
send "mouseUp" to button "OK"
do "put 1+1 into x"
set the pencilSize to 5
set the pencilColor to "#FF0000"
drag from "100,100" to "300,300"  -- bitmap drawing
```

## Networking

### HTTP client
```
put request "http://localhost:8080/health" into reqId
put the status of request reqId into s
put the body of request reqId into t
put the header "Content-Type" of request reqId into h

request "http://localhost:8080/submit" method "POST" headers "Content-Type: application/json" body "{\"score\":42}" with message "requestFinished"

on requestFinished requestId, eventName
  if eventName is "completed" then
    put the body of request requestId into field "out"
  else
    put the error of request requestId into field "out"
  end if
end requestFinished
```

### HTTP server
```
listen for http on port 8080 host "127.0.0.1" with message "networkRequest"

on networkRequest requestId, eventName
  if eventName is "request" then
    reply to request requestId with status 200 body "hello from Hype"
  end if
end networkRequest
```

### Raw TCP
```
listen for tcp on port 9000 host "127.0.0.1" with message "socketEvent"
connect to host "127.0.0.1" on port 9000 with message "socketEvent"
send "ping" to connection someConnectionId
close connection someConnectionId
stop listener someListenerId
```

Runtime object properties:
- `request <id>`: `status`, `state`, `method`, `url`, `body`, `error`, `statusCode`, `header "Name"`
- `listener <id>`: `status`, `state`, `host`, `port`, `transport`, `callbackMessage`
- `connection <id>`: `status`, `state`, `host`, `remoteAddress`, `port`, `remotePort`, `lastData`, `body`, `error`

## SpriteKit (Sprite Scenes)

### Creating Scenes & Nodes
```
create spritearea "game" at rect 20,20,760,560
create scene "main" in spritearea "game" with size 760,560
create sprite "player" in scene "main" with asset "ship"
create sprite "ball" in scene "main"
remove sprite "enemy"
pause scene "main"
resume scene "main"
open scene "level2" with transition "fade" duration 1.0
```

### Node Properties (get/set — works for sprite, label, shape, emitter, camera)
```
set the loc of sprite "player" to "200,300"
set the size of sprite "player" to "48,48"
set the width of sprite "player" to 64
set the rotation of sprite "player" to 45
set the alpha of sprite "player" to 0.5
set the xScale of sprite "player" to 2.0
set the hidden of sprite "enemy" to true
set the zPosition of sprite "player" to 10
put the loc of sprite "player" into pos
put item 1 of pos into xPos
put item 2 of pos into yPos
```

### Label Properties
```
set the text of label "score" to "Score: 100"
set the font of label "score" to "Helvetica"
set the fontSize of label "score" to 24
set the fontColor of label "score" to "#FF0000"
```

### Shape Properties
```
set the fillColor of shape "wall" to "#333333"
set the strokeColor of shape "wall" to "#FFFFFF"
set the lineWidth of shape "wall" to 2
set the cornerRadius of shape "box" to 8
```

### Physics
```
set the velocity of sprite "ball" to "100,-50"
set the angularVelocity of sprite "wheel" to 3.14
set the density of sprite "ball" to 2.0
set the friction of sprite "ball" to 0.5
set the restitution of sprite "ball" to 0.8
set the damping of sprite "ball" to 0.1
set the dynamic of sprite "wall" to false
set the affectedByGravity of sprite "ball" to true
apply force "10,20" to sprite "ball"
apply impulse "5,0" to sprite "ball"
create joint "rope" type pin from sprite "a" to sprite "b"
create physicsfield "wind" type linearGravity strength 5 direction 1,0
constrain sprite "enemy" distance 50 to 200 from sprite "player"
```

### Camera
```
create camera "cam"
set the loc of camera "cam" to "400,300"
set the zoom of camera "cam" to 2.0
set the target of camera "cam" to "player"
```

### Tile Maps
```
create tilemap "map" columns 20 rows 15 tilesize 32 with tileset "terrain"
set tile 5,3 of tilemap "map" to 2
put the columns of tilemap "map" into cols
```

### Emitter Properties
```
set the birthRate of emitter "fire" to 200
set the particleLifetime of emitter "fire" to 1.5
set the particleSpeed of emitter "fire" to 150
set the particleColor of emitter "fire" to "#FF4400"
set the particleScale of emitter "fire" to 0.5
set the emissionAngle of emitter "fire" to 90
```

### Audio/Video
```
set the volume of audio "music" to 0.5
set the loop of audio "music" to true
set the autoplay of video "intro" to true
```

### Mouse Tracking in Scenes
```
on mouseWithin
  put the mouseLoc into pos
  set the loc of sprite "cursor" to pos
end mouseWithin
```

## Common Patterns

**Button navigation:**
```
on mouseUp
  go next
end mouseUp
```

**Idle logic (use for custom state, not physics simulation):**
```
on idle
  global pulse
  if pulse is empty then put 0 into pulse
  add 1 to pulse
  set the text of label "debug" to "tick " & pulse
end idle
```

Treat any request that touches a sprite area, scene, or sprite node as
SpriteKit scene authoring first, not as generic part scripting.

For SpriteKit motion, bouncing, gravity, and collisions, prefer native physics
bodies, restitution, velocity, and actions. Do not simulate those with `on
idle` or `on frameUpdate` unless the user explicitly asks for custom scripted
movement.

If a SpriteKit request needs input handling, use handlers like `keyDown`,
`keyUp`, `beginContact`, or `endContact` to adjust physics state or actions
instead of moving sprites by hand every frame.

**Keyboard-controlled physics sprite:**
```
on keyDown
  if the key is "w" then set the velocity of sprite "player" to "0,220"
  if the key is "s" then set the velocity of sprite "player" to "0,-220"
  if the key is "a" then set the velocity of sprite "player" to "-220,0"
  if the key is "d" then set the velocity of sprite "player" to "220,0"
end keyDown

on keyUp
  set the velocity of sprite "player" to "0,0"
end keyUp
```

**Score tracking:**
```
on beginContact
  global score
  add 10 to score
  set the text of label "score" to "Score: " & score
  remove sprite "coin1"
end beginContact
```

**Mouse-following sprite:**
```
on mouseWithin
  set the loc of sprite "cursor" to the mouseLoc
  put the mouseH into mx
  put the mouseV into my
  set the text of label "coords" to mx & "," & my
end mouseWithin
```
