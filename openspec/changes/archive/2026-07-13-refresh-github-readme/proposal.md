# Refresh the GitHub README from current repository evidence

## Why

The root README is the public landing page for Hype, but it mixes durable product description with volatile counts, benchmark results, status claims, and setup guidance accumulated across many feature changes. Before the repository is pushed to `main`, the README needs a complete evidence-first refresh so a GitHub reader can understand what Hype is, what is implemented today, how to build and verify it, which capabilities require opt-in services, and where to find authoritative detail without encountering stale or overstated claims.

## What Changes

- Reorganize the root `README.md` around a concise product overview, current capabilities, security/privacy boundaries, installation and contributor quick starts, architecture map, project status, and authoritative documentation links.
- Reconcile every volatile number and capability claim against current source, tests, manifests, scripts, or dated benchmark artifacts; remove or qualify claims that cannot be reproduced.
- Make local-first versus network-backed behavior explicit, including Ollama, OpenAI-compatible providers, OpenAI, Meshy, MCP/debug automation, import, and runtime export boundaries.
- Verify every command, repository-relative link, platform/toolchain requirement, and named file against the current tree.
- Preserve detailed reference material where it remains useful, but reduce duplication with `architecture.md`, `decisions.md`, and focused documents by linking to those sources.
- Add no production code and make no product-behavior, persistence, dependency, or public-API change.

## Capabilities

### New Capabilities

- `github-readme`: an accurate, navigable, evidence-backed GitHub landing page for users and contributors.

### Modified Capabilities

- None.

## Impact

- Primary file: `README.md`.
- Evidence sources: `Package.swift`, `architecture.md`, `decisions.md`, `CONTRIBUTING.md`, current source/test catalogs, build/test/deploy scripts, AI evaluation artifacts, and focused documentation under `docs/`.
- User impact: documentation only; public expectations and onboarding become clearer and more reproducible.
- Compatibility/security impact: no runtime impact. Documentation must not expose secrets, private paths, local user data, unsupported guarantees, or unsafe network assumptions.
