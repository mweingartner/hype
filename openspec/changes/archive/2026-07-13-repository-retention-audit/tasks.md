## 1. Evidence validation

- [x] 1.1 Verify the 888-row tracked-file inventory exactly matches the pre-change `git ls-files` baseline by path and category.
- [x] 1.2 Verify the 65-row Markdown audit exactly matches the tracked Markdown baseline and manually recheck every watchlist classification.
- [x] 1.3 Recheck package, workflow, hook, MPD, OpenSpec, vendor, generated/source-pair, fixture, resource, and direct-entrypoint ownership.

## 2. Retention decision

- [x] 2.1 Add `Historical v3/v4 training snapshot (2026-04-22)` to `scripts/ai-training/README.md`, preserving the exact v4 loss sequence (1.311 validation initially; 0.106 training at iteration 100; 0.057 training at iteration 190) and v3 result (0.020 validation loss at iteration 800 but 3/26 quality prompts passing), with no operational/default/resume claims.
- [x] 2.2 Delete exactly `Tools/hype-mcp-server/bin/index.js` and `scripts/ai-training/RESUME_V4.md`; retain all other baseline files.
- [x] 2.3 Change MCP build to move transient `bin/index.js` into retained `bin/hype-mcp.js`.
- [x] 2.4 Add a non-mutating regression that compiles into a temporary directory, byte-compares current TypeScript output with executable `hype-mcp.js`, leaves no `index.js`, and fails on isolated source drift; run check/build and protocol smoke.
- [x] 2.5 Audit retained historical docs for destructive, credential-bearing, and machine-specific executable guidance.

## 3. Independent verification

- [x] 3.1 Security reviews deletion safety, secrets, legal/provenance material, workflow integrity, and supply-chain ownership.
- [x] 3.2 Tester validates inventory cardinality/path equality, links, active commands/configuration, and repository gates proportionately to the no-production-change outcome.
- [x] 3.3 Record Deploy as no-installable-change readiness only; do not replace `/Applications/Hype.app` for an audit-only result.
