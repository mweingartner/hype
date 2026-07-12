#!/usr/bin/env bash
set -euo pipefail

version="2026-07-09"
canonical="/Users/mweingar/dev/hype-v2/docs/Model-Paired-Development-Playbook.md"
pdf="/Users/mweingar/Documents/ModelPairedDev.pdf"
files=(
  "$canonical"
  "/Users/mweingar/.codex/AGENTS.md"
  "/Users/mweingar/.claude/CLAUDE.md"
  "/Users/mweingar/.claude/commands/pipeline.md"
  "/Users/mweingar/.claude/agents/designer.md"
  "/Users/mweingar/.claude/agents/architect.md"
  "/Users/mweingar/.claude/agents/security.md"
  "/Users/mweingar/.claude/agents/builder.md"
  "/Users/mweingar/.claude/agents/tester.md"
  "/Users/mweingar/dev/pebble/AGENTS.md"
  "/Users/mweingar/dev/hype-v2/AGENTS.md"
  "/Users/mweingar/dev/hype-stubs/AGENTS.md"
  "/Users/mweingar/dev/lucy/CLAUDE.md"
  "/Users/mweingar/dev/lucy/.claude/commands/pipeline.md"
  "/Users/mweingar/dev/lucy/.claude/agents/architect.md"
  "/Users/mweingar/dev/lucy/.claude/agents/security.md"
  "/Users/mweingar/dev/lucy/.claude/agents/builder.md"
  "/Users/mweingar/dev/lucy/.claude/agents/tester.md"
)

sequence='Design Mock → Architecture → Design Review/Revision → Security (plan) → Build → Security (code) → Design Sign-off → Test → Deploy'
legacy_patterns=(
  'Architect → Security'
  'Architect → Builder'
  'Architecture → Security'
  'Architecture → Builder'
  'Design Review → Security'
  'Security (code) → Tester'
  'Test → Git Commit'
  'Skip the pipeline entirely'
  'SKIP the whole pipeline'
)
invalid_adjacency='Design Mock → (?!Architecture)|Architecture → (?!Design Review/Revision)|Design Review/Revision → (?!Security \(plan\))|Security \(plan\) → (?!Build)|Build → (?!Security \(code\))|Security \(code\) → (?!Design Sign-off)|Design Sign-off → (?!Test)|Test → (?!Deploy)'

normalize() {
  perl -0pe 's/\r//g; s/\s+/ /g; s/\*\*//g; s/`//g; s/->/→/g'
}

for file in "${files[@]}"; do
  [[ -f "$file" ]] || { echo "missing protocol file: $file" >&2; exit 1; }
  rg -qi "protocol version:? ${version}|canonical ${version}|canonical .*version ${version}|updated: ${version}" "$file" || {
    echo "stale or missing protocol version: $file" >&2
    exit 1
  }
  normalize < "$file" | rg -Fq "$sequence" || {
    echo "missing or reordered lifecycle: $file" >&2
    exit 1
  }
  normalized="$(normalize < "$file")"
  for legacy in "${legacy_patterns[@]}"; do
    if [[ "$normalized" == *"$legacy"* ]]; then
      echo "legacy lifecycle conflicts with canonical sequence in $file: $legacy" >&2
      exit 1
    fi
  done
  if printf '%s' "$normalized" | rg --pcre2 -q "$invalid_adjacency"; then
    echo "interposed or reordered lifecycle stage: $file" >&2
    exit 1
  fi
done

command -v pdftotext >/dev/null || { echo "pdftotext is required" >&2; exit 1; }
pdf_text="$(mktemp)"
trap 'rm -f "$pdf_text"' EXIT
pdftotext -layout "$pdf" "$pdf_text"
rg -q "Protocol version: ${version}" "$pdf_text" || { echo "stale PDF version" >&2; exit 1; }
normalize < "$pdf_text" | rg -Fq "$sequence" || { echo "stale or reordered PDF lifecycle" >&2; exit 1; }
canonical_hash="$(shasum -a 256 "$canonical" | awk '{print $1}')"
pdfinfo "$pdf" | rg -Fq "Subject:         Canonical SHA-256: ${canonical_hash}" || {
  echo "PDF was not generated from the current canonical Markdown" >&2
  exit 1
}

echo "Model-paired protocol ${version} is consistent across ${#files[@]} instruction files and the PDF export."
