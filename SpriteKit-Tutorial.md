# Hype SpriteKit Tutorial

A hands-on guide to building interactive 2D games and animated experiences inside Hype using the new SpriteKit integration.

## Table of Contents

1. [Core Concepts](#core-concepts)
2. [Getting Started Manually](#getting-started-manually)
3. [The Asset Repository](#the-asset-repository)
4. [Scripting Sprites with HypeTalk](#scripting-sprites-with-hypetalk)
5. [Physics and Collisions](#physics-and-collisions)
6. [Actions and Animation](#actions-and-animation)
7. [The Message Path](#the-message-path)
8. [Debug Tools](#debug-tools)
9. [Building with AI](#building-with-ai)
10. [Walkthrough: Pong in Hype](#walkthrough-pong-in-hype)

---

## Core Concepts

Hype's SpriteKit integration adds a new **Sprite Area** part type that embeds a live SpriteKit scene on any card or background. Everything you build is stored as a declarative **SceneSpec** (JSON) inside the stack document, keeping stacks portable and AI-friendly.

**Key objects:**

| Object | What it is |
|--------|------------|
| **Sprite Area** | A Hype part that hosts an SKView and one active scene |
| **Scene** | The root container — has a size, background color, gravity, and child nodes |
| **Sprite** | An image-based node (textured from a repository asset) |
| **Label** | A text node |
| **Shape** | A geometric node (rectangle, circle, ellipse, or freeform path) |
| **Group** | A logical container for organizing child nodes |
| **Emitter** | A particle effect node |

**Architecture rule:** The SceneSpec JSON is the source of truth. The live SpriteKit scene is a generated projection. When you edit properties in the inspector, write HypeTalk scripts, or use AI tools, you're modifying the SceneSpec — the runtime bridge materializes it into SpriteKit nodes automatically.

---

## Getting Started Manually

### Creating a Sprite Area

1. Select the **Sprite Area** tool from the tool palette (the gamecontroller icon).
2. Click and drag on the card to draw the area's bounds.
3. The area appears as a teal placeholder in edit mode showing the scene name and node count.
4. Switch to **Browse** mode to see the live SpriteKit scene.

Alternatively, from HypeTalk:

```hypertalk
create spritearea "game" at rect 20,20,760,560
```

### Creating a Scene

Every Sprite Area starts with a default scene. You can rename it or configure it:

```hypertalk
create scene "level1" in spritearea "game" with size 760,560
```

### Adding Sprites

```hypertalk
create sprite "player" in scene "level1" with asset "ship"
set the loc of sprite "player" to 380,480
```

### Adding Labels

Labels are text nodes rendered directly in the scene:

```hypertalk
create sprite "scoreLabel"
-- Labels are created as sprite nodes with text properties set via the SceneSpec
```

### Adding Shapes

Shapes can be rectangles, circles, ellipses, or freeform paths — useful for walls, boundaries, and simple game elements.

---

## The Asset Repository

The **Asset Repository** is a stack-scoped asset library. Import art once, reuse it across every scene in your stack. Assets are stored inside the stack document itself, so stacks remain fully portable.

### Opening the Repository

Click the **tray icon** in the toolbar to open the Asset Repository window.

### Importing Assets

1. Click the **+** button in the repository window.
2. Select one or more PNG or JPEG files.
3. Each file becomes a named asset, using the filename as the default name.

AI tools can also add assets with `import_repository_asset`, `generate_sprite_asset`,
or the opt-in web asset tools. HypeTalk scripts reference repository assets by
name after they exist; file import itself is an authoring UI/tool operation.

### Browsing and Searching

- Assets display as a grid of thumbnails.
- Use the search field to filter by name.
- Click an asset to see its detail panel: preview, dimensions, file size, tags, and slices.

### Using Assets in Scenes

When you create a sprite with the `with asset` clause, Hype resolves the asset name to a stable UUID reference. Renaming an asset later won't break your scenes.

```hypertalk
create sprite "enemy" with asset "alien"
```

### Deleting Assets

Select an asset in the repository and click **Delete Asset** in the detail panel.

---

## Scripting Sprites with HypeTalk

All sprite commands modify the SceneSpec (the document data), and the runtime bridge updates the live scene automatically.

### Creating Objects

```hypertalk
-- Create a sprite area on the current card
create spritearea "game" at rect 20,20,760,560

-- Create a scene in it
create scene "main" in spritearea "game" with size 760,560

-- Add sprites
create sprite "ball" in scene "main" with asset "ball"
create sprite "paddle" in scene "main" with asset "paddle"
```

### Reading Properties

```hypertalk
put the loc of sprite "ball" into myVar
put the rotation of sprite "ball" into angle
put the alpha of sprite "ball" into opacity
put the width of sprite "ball" into w
put the height of sprite "ball" into h
put the size of sprite "ball" into dims      -- "width,height"
put the hidden of sprite "ball" into isHidden -- "true" or "false"
put the xScale of sprite "ball" into sx
put the yScale of sprite "ball" into sy
put the zPosition of sprite "ball" into z
```

### Setting Properties

```hypertalk
set the loc of sprite "ball" to "380,280"
set the rotation of sprite "ball" to 45
set the alpha of sprite "ball" to 0.5
set the xScale of sprite "ball" to 2.0
set the yScale of sprite "ball" to 2.0
set the hidden of sprite "ball" to true
set the zPosition of sprite "ball" to 10
set the name of sprite "ball" to "gameBall"
```

### Removing Sprites

```hypertalk
remove sprite "ball"
```

### Pausing and Resuming

```hypertalk
pause scene "main"
resume scene "main"
```

### Coordinate System

HypeTalk uses a **top-left origin** coordinate system to match Hype's card coordinates:

- `x` increases to the right
- `y` increases downward
- `loc` refers to the position of a node

The bridge converts to SpriteKit's bottom-left origin internally. You never need to think about SpriteKit coordinates.

---

## Physics and Collisions

Sprites can have physics bodies that enable gravity, collisions, and contact detection.

Physics properties are configured through the SceneSpec. Each node can have a `physicsBody` with these settings:

| Property | Description | Default |
|----------|-------------|---------|
| `bodyType` | `circle`, `rect`, `texture`, or `none` | — |
| `isDynamic` | Whether physics simulation affects this body | `true` |
| `affectedByGravity` | Whether gravity pulls this body | `true` |
| `restitution` | Bounciness (0 = no bounce, 1 = full bounce) | `0.2` |
| `friction` | Surface friction | `0.2` |
| `mass` | Body mass (nil = auto from size) | `nil` |
| `allowsRotation` | Whether collisions can spin the body | `true` |
| `categoryBitmask` | Category for collision filtering | `0xFFFFFFFF` |
| `contactTestBitmask` | Categories that trigger contact events | `0` |
| `collisionBitmask` | Categories that cause physical collisions | `0xFFFFFFFF` |

### Scene Gravity

The scene has a `gravity` vector (default: `dx=0, dy=-9.8`). You can view gravity in the PropertyInspector when a Sprite Area is selected.

### Contact Events

When two physics bodies touch, HypeTalk messages are dispatched:

- **`beginContact`** — sent to both nodes when they start touching
- **`endContact`** — sent to both nodes when they stop touching

```hypertalk
on beginContact
  -- 'the params' contains the other node's name
  put "Hit something!" into field "status"
end beginContact
```

---

## Actions and Animation

SpriteKit actions let you animate nodes without per-frame scripting. Actions are declarative and run natively at full frame rate.

### Available Action Types

| Action | Description | Key Parameters |
|--------|-------------|----------------|
| `moveTo` | Move to absolute position | `x`, `y` |
| `moveBy` | Move by relative offset | `dx`, `dy` |
| `rotateTo` | Rotate to angle (degrees) | `degrees` |
| `rotateBy` | Rotate by offset (degrees) | `degrees` |
| `scaleTo` | Scale to absolute value | `scale` |
| `scaleBy` | Scale by relative factor | `scale` |
| `fadeTo` | Fade to alpha value | `alpha` |
| `fadeIn` | Fade to fully visible | — |
| `fadeOut` | Fade to invisible | — |
| `wait` | Pause before next action | (uses `duration`) |
| `removeFromParent` | Delete the node | — |
| `sequence` | Run children in order | child actions |
| `group` | Run children simultaneously | child actions |
| `repeatForever` | Loop a child action | child action |
| `repeatCount` | Loop N times | `count`, child action |
| `animate` | Cycle through frame textures | frame references |

### Running Actions from HypeTalk

```hypertalk
run action "bounce" on sprite "ball"
```

Actions are defined in the SceneSpec's node `actions` array. The AI tools can add actions via `apply_scene_diff`.

---

## The Message Path

SpriteKit events integrate into Hype's full message-passing chain. When something happens in a sprite scene, the message travels:

```
target node -> parent groups -> scene -> Sprite Area (Part) -> card -> background -> stack -> Hype
```

This means you can write handlers at any level:

- **On a sprite node** (in the node's script): Handle events for that specific sprite
- **On the Sprite Area part** (in the part's script): Handle all unhandled scene events
- **On the card** (in the card's script): Handle events that pass through the scene
- **On the background/stack/Hype**: Global fallback handlers

### Events from SpriteKit

| Event | When it fires | Parameters |
|-------|---------------|------------|
| `mouseDown` | Click on a node or the scene | position |
| `mouseUp` | Release click | position |
| `mouseDragged` | Drag while mouse down | position |
| `keyDown` | Key pressed while scene has focus | key character |
| `keyUp` | Key released | key character |
| `beginContact` | Two physics bodies start touching | other node |
| `endContact` | Two physics bodies stop touching | other node |
| `sceneDidLoad` | Scene finishes loading | — |

### Example: Handling clicks on sprites

```hypertalk
-- On the Sprite Area part's script:
on mouseUp
  put "Clicked in the game area!" into field "log"
end mouseUp
```

If a specific sprite has its own `mouseUp` handler, that fires first. If it doesn't handle it (or uses `pass mouseUp`), the message continues up through the chain.

---

## Debug Tools

When a Sprite Area is selected in the PropertyInspector, you get debug toggles:

| Toggle | What it shows |
|--------|---------------|
| **Show FPS** | Frames per second counter |
| **Show Physics** | Physics body outlines and contacts |
| **Show Node Count** | Total nodes in the scene |
| **Paused** | Freeze the simulation |

The inspector also shows:

- Scene name and size
- Current gravity vector
- A list of all nodes with their types (sprite, label, shape, group, emitter)

---

## Building with AI

Hype's Ollama AI integration has full SpriteKit support. Open the AI panel (sparkles icon) and describe what you want.

### AI Tools Available

| Tool | What it does |
|------|-------------|
| `create_sprite_area` | Creates a new Sprite Area on the card with a default scene |
| `get_scene_spec` | Retrieves the full SceneSpec JSON for inspection |
| `apply_scene_diff` | Applies incremental changes to a scene (add/remove/update nodes) |
| `add_sprite_to_scene` | Adds a sprite node with optional asset binding |
| `list_repository_assets` | Shows all assets in the Asset Repository |
| `import_repository_asset` | Imports an image file into the repository |

### Example Prompts

**Create a game from scratch:**
> "Create a sprite area called 'game' that fills most of the card. Add a blue rectangle shape at the bottom as a paddle and a red circle as a ball near the center."

**Inspect the current scene:**
> "What sprites are in the game area? Show me their positions."

**Modify the scene:**
> "Move the ball to the top of the scene and make it smaller."

**Work with assets:**
> "Import the file ~/Art/spaceship.png into the sprite repository as 'ship', then create a sprite using it."

### How AI Scene Editing Works

The AI uses **structured JSON diffs** (SceneDiff) to modify scenes safely:

1. AI calls `get_scene_spec` to see the current state
2. AI constructs a `SceneDiff` with specific changes (add nodes, remove nodes, update properties)
3. AI calls `apply_scene_diff` to apply changes transactionally
4. The runtime bridge detects the SceneSpec change and rebuilds the scene

This is safer than free-form code generation because every change is validated against the schema before applying.

---

## Walkthrough: Pong in Hype

Let's build a simple Pong game step by step using HypeTalk.

### Step 1: Create the Game Area

```hypertalk
on openCard
  -- Create the game area
  create spritearea "pong" at rect 20,20,760,560
  create scene "main" in spritearea "pong" with size 760,560
end openCard
```

### Step 2: Add Game Objects

```hypertalk
on mouseUp
  -- Create the paddle (a wide shape near the bottom)
  create sprite "paddle" in scene "main"
  set the loc of sprite "paddle" to "380,520"

  -- Create the ball
  create sprite "ball" in scene "main"
  set the loc of sprite "ball" to "380,280"

  -- Create walls (shapes at edges)
  create sprite "topWall" in scene "main"
  set the loc of sprite "topWall" to "380,0"

  create sprite "leftWall" in scene "main"
  set the loc of sprite "leftWall" to "0,280"

  create sprite "rightWall" in scene "main"
  set the loc of sprite "rightWall" to "760,280"
end mouseUp
```

### Step 3: Add Controls

Add a button with this script to move the paddle:

```hypertalk
on keyDown
  if the key is "a" then
    put the loc of sprite "paddle" into pos
    set the loc of sprite "paddle" to (item 1 of pos - 20) & "," & item 2 of pos
  end if
  if the key is "d" then
    put the loc of sprite "paddle" into pos
    set the loc of sprite "paddle" to (item 1 of pos + 20) & "," & item 2 of pos
  end if
end keyDown
```

### Step 4: Or Just Ask the AI

Open the AI panel and type:

> "Build me a Pong game in a sprite area. Include a paddle at the bottom that moves with A and D keys, a bouncing ball, and walls on three sides. Add a score field above the game area."

The AI will create the sprite area, scene, nodes, physics bodies, and HypeTalk handlers — all through the structured tool-calling system.

---

## Quick Reference Card

### HypeTalk Commands

```
create spritearea "name" [at rect L,T,W,H]
create scene "name" [in spritearea "area"] [with size W,H]
create sprite "name" [in scene "scene"] [with asset "assetName"]
remove sprite "name"
pause scene ["name"]
resume scene ["name"]
run action "name" on sprite "spriteName"
```

### Readable Properties

```
the loc of sprite "name"          -- "x,y"
the rotation of sprite "name"     -- degrees
the alpha of sprite "name"        -- 0.0 to 1.0
the width of sprite "name"
the height of sprite "name"
the size of sprite "name"         -- "w,h"
the hidden of sprite "name"       -- "true"/"false"
the xScale of sprite "name"
the yScale of sprite "name"
the zPosition of sprite "name"
```

### Settable Properties

```
set the loc of sprite "name" to "x,y"
set the rotation of sprite "name" to 45
set the alpha of sprite "name" to 0.5
set the hidden of sprite "name" to true
set the xScale of sprite "name" to 2.0
set the name of sprite "name" to "newName"
```

### Scene Events

```
on mouseDown         -- click in scene
on mouseUp           -- release in scene
on mouseDragged      -- drag in scene
on keyDown           -- key pressed
on keyUp             -- key released
on beginContact      -- physics contact started
on endContact        -- physics contact ended
on sceneDidLoad      -- scene finished loading
```
