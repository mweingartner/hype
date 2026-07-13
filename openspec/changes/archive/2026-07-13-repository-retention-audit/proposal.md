# Repository retention audit

## Why

Hype adopted MPD/OpenSpec after years of accumulating implementation plans, audit records, reference material, generated tool outputs, and vendored sources. The repository needs a verification-first retention decision, not a deletion sweep based on age, naming, or missing inbound links.

The verified baseline is 888 tracked files, including 65 Markdown files. Every tracked path is enumerated in `audit-inventory.tsv`; every Markdown file receives additional history, overlap, reference, and role evidence in `markdown-audit.tsv`.

## What Changes

- Classify all 888 tracked files by ownership and lifecycle.
- Review all 65 Markdown files individually, distinguishing active durable docs, active workflow material, historical plans/audits, OpenSpec archives/specs/templates, vendor documentation/licenses, experiment records, and subsystem references.
- Require positive obsolescence evidence before deletion: a superseding artifact must preserve all unique rationale, open/deferred work, provenance, reproducibility data, commands, and legal obligations.
- Treat age, a word such as `draft`, completion status, or zero inbound links as signals for review, never as sufficient deletion proof.
- Preserve MPD/OpenSpec archives as change provenance; MPD adoption does not retroactively replace pre-MPD records.
- Produce an explicit deletion set. After Security-plan challenge, the revised architecture finds exactly two files with sufficient positive evidence: the transient MCP compiler output `Tools/hype-mcp-server/bin/index.js` and the obsolete machine-specific checkpoint guide `scripts/ai-training/RESUME_V4.md`.

## Capabilities

### New Capabilities

- `repository-retention`: evidence-backed classification and conservative retirement of repository artifacts.

### Modified Capabilities

- None.

## Impact

No production API, persisted document, dependency, runtime behavior, or user-facing surface changes. The tooling build script changes so TypeScript compilation leaves only the shipped `hype-mcp.js`; the retained AI-training README gains a concise non-operative historical experiment record; and two obsolete tracked artifacts are removed. The Builder must independently validate the evidence and may not expand the deletion set without returning to Architecture.
