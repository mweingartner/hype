## ADDED Requirements

### Requirement: Only stack document windows persist launch geometry
The app SHALL persist window geometry (frame origin and size) only for windows
that belong to an open stack document (an `NSDocument` whose window controllers
contain the window). Auxiliary windows — panels, sheets, the About window, the
script editor, the asset repository, the console, the Theme Designer, the AI
context library, import helper windows, and the Settings window — SHALL NOT
write launch geometry.

#### Scenario: Hover help panel does not poison saved geometry
- **WHEN** the user hovers object tools (showing the floating help panel), then
  quits and relaunches Hype
- **THEN** the stack window reopens at the frame the stack document window last
  had, not at the help panel's mouse-adjacent frame

#### Scenario: Auxiliary window key at quit
- **WHEN** the user quits Hype while the script editor (or any non-document
  window) is the key window
- **THEN** the persisted launch geometry remains the stack document window's
  last frame

### Requirement: Saved geometry is keyed per stack file
The app SHALL store saved window frames keyed by the stack file's canonical
path (standardized, symlinks resolved), alongside a global last-document-window
frame used as the fallback for untitled documents. The per-stack store SHALL be
validated on read (finite values; width and height greater than 100 points) and
bounded (at most 32 entries, evicting least-recently-used).

#### Scenario: Two stacks do not share a frame
- **WHEN** the user sizes stack A's window large, opens stack B and sizes it
  small, then quits with stack A frontmost and relaunches
- **THEN** stack A reopens at stack A's saved frame, not stack B's

#### Scenario: Untitled launch uses the global fallback
- **WHEN** Hype launches with no last-opened stack (a new untitled document is
  created)
- **THEN** the untitled window uses the last saved document-window frame when
  one exists, and the default size and placement otherwise

### Requirement: Launch restores the reopened stack's frame, clamped on-screen
At launch, the app SHALL reopen the last-opened stack at that stack's saved
window frame, applied exactly once to that stack's document window, before the
window's current frame is persisted. The restored frame SHALL be clamped to the
currently visible screen area: used as-is when fully visible on some screen;
translated (and, only when larger than the screen, shrunk to the screen's
visible area) otherwise. The app SHALL NOT write geometry while computing the
restored frame.

#### Scenario: Relaunch restores size and position
- **WHEN** the user resizes and moves the stack window, quits, and relaunches
- **THEN** the stack window reopens with the same frame (origin and size)

#### Scenario: Display disconnected since last quit
- **WHEN** the saved frame lies entirely on a display that is no longer
  attached
- **THEN** the window reopens at its saved size (capped to the current screen's
  visible area) fully within a currently attached screen, rather than
  off-screen or at the default size

#### Scenario: Saved frame larger than the current screen
- **WHEN** the saved frame exceeds the visible area of every attached screen
- **THEN** the window reopens shrunk to fit fully within the best-matching
  screen's visible area

#### Scenario: First-ever launch
- **WHEN** Hype launches with no saved window frame
- **THEN** the window opens at the default size and system-provided placement
  (no restore is attempted, and invalid or non-finite stored values are treated
  as absent)
