# Repository retention

## Requirements

### Requirement: Complete tracked-file inventory

The audit SHALL enumerate every tracked repository path and SHALL prove baseline cardinality and path equality.

#### Scenario: Full repository coverage

- **GIVEN** the pre-change tracked tree contains 888 files
- **WHEN** the retention evidence is validated
- **THEN** every one of those 888 paths appears exactly once in the inventory
- **AND** no untracked current-change artifact is misrepresented as part of the baseline

### Requirement: Exhaustive Markdown classification

The audit SHALL individually classify all 65 tracked Markdown files by lifecycle and ownership, including active docs, historical plans/audits, OpenSpec archives/specs/templates, vendor docs, experiment records, and subsystem references.

#### Scenario: A completed pre-MPD plan is reviewed

- **GIVEN** a plan predates MPD and is marked completed
- **WHEN** it contains unique commits, measurements, rationale, or deferred work
- **THEN** it SHALL be retained as historical evidence
- **AND** MPD adoption SHALL NOT be treated as a replacement artifact

### Requirement: Positive obsolescence evidence

A tracked file SHALL be deleted only when all retirement predicates in `design.md` are proven for that exact path.

#### Scenario: Weak deletion signal

- **GIVEN** a file is old, unlinked, similarly worded, completed, or named `draft`
- **WHEN** no complete replacement and ownership proof exists
- **THEN** the file SHALL be retained

#### Scenario: Proven obsolete file

- **GIVEN** a named replacement preserves all current facts, unique rationale, provenance, open work, legal notices, and reproducibility data
- **AND** build, test, packaging, workflow, command, and source ownership are absent
- **WHEN** Security and Tester independently validate those facts
- **THEN** deletion MAY proceed after Architecture names the exact path

### Requirement: Exact approved deletion set

The implementation SHALL delete exactly the two Architecture-approved obsolete paths and SHALL NOT expand the set without renewed review.

#### Scenario: Transient compiler output

- **GIVEN** TypeScript emits `bin/index.js` and only `bin/hype-mcp.js` is consumed
- **WHEN** the MCP tool is built cleanly
- **THEN** build SHALL move the transient output to `hype-mcp.js`
- **AND** SHALL leave no `index.js`
- **AND** retained executable SHALL pass a protocol smoke

#### Scenario: Obsolete machine-state guide

- **GIVEN** `RESUME_V4.md` describes a superseded checkpoint, hardcoded path, and destructive reset
- **WHEN** current results and local completion evidence contradict it
- **THEN** its unique v3/v4 loss and quality measurements SHALL first be preserved in the retained training README
- **AND** the stale guide SHALL then be deleted
- **AND** the preserved subsection SHALL contain no resume/default commands, destructive commands, machine paths, or transient-state claims

### Requirement: Historical command safety

Retained historical documents SHALL NOT present destructive, credential-bearing, or machine-specific commands as current guidance without an explicit safe historical warning.

### Requirement: Operational and legal integrity

The audit SHALL preserve manifest-owned code/resources, direct command entrypoints, source/generated pairs, fixtures, licenses, vendor provenance, MPD/OpenSpec lifecycle artifacts, and experiment reproducibility records unless positive replacement evidence exists.

#### Scenario: Text references are absent

- **GIVEN** a SwiftPM-discovered source, executable script, agent directive, vendor license, or generated distribution file has zero inbound text references
- **WHEN** its owner consumes it by convention, manifest, or direct invocation
- **THEN** it SHALL be retained
