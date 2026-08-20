# part-properties (delta)

## MODIFIED Requirements

### Requirement: Color writes validate through one hex validator

Every color-kind property write on the HypeTalk and AI surfaces SHALL
validate through a shared `HexColor` validator accepting the empty string
(clear/auto), 6- or 8-digit hex with optional leading `#` (stored as the
normalized uppercase `#`-prefixed form), and a fixed case-insensitive
classic color-name table — `black, white, red, green, blue, yellow, orange,
purple, pink, brown, gray (grey), cyan, magenta, lime, navy, teal` — each
resolving to its canonical `#RRGGBB` value (e.g. `red` → `#FF0000`,
`green` → `#008000`, `lime` → `#00FF00`). All other values SHALL error.
Chart spider color validation via `ChartConfig.normalizedHex` SHALL be
unchanged.

#### Scenario: Garbage hex errors

- **WHEN** a script runs `set the fillColor of shape "Box" to "reddish"`
- **THEN** the script errors naming the expected format and the stored fill
  is unchanged; `set the fillColor of shape "Box" to "#ff0000"` stores
  `#FF0000`, and setting it to `""` clears to auto

#### Scenario: Named colors resolve identically everywhere

- **WHEN** `setPenColor "red"` runs in HypeTalk, `set the fillColor of shape
  "x" to "red"` runs in HypeTalk, and `set_part_property` writes
  `fill_color=red`
- **THEN** all three store `#FF0000` from the single `HexColor` table
