#!/bin/bash
#
# watch-kernel-probe.sh — prove the HypeTalk interpreter (and almost all of
# HypeCore) builds for watchOS, the project's "small footprint on Apple Watch"
# north star.
#
# HypeCore is already remarkably watch-clean: every AppKit/SpriteKit/MusicKit/
# FoundationModels/Network/SwiftUI import is `#if canImport(...)`- or
# `#if !os(watchOS)`-guarded, EXCEPT a short list of device-specific *leaf*
# files (live audio engines, a SceneKit asset loader, an AppKit-only control
# view, and the C HyperCard-stack importer). None of those leaves are referenced
# by the interpreter kernel.
#
# This script compiles all of HypeCore for the watchOS-simulator triple with
# only those leaves excluded, and reports the resulting __text size. It proves
# the interpreter + its transitive dependencies are watch-portable WITHOUT the
# permanent multi-module restructure (that is a separate, deferred step). It does
# NOT compile the AppKit/SwiftUI GUI in Sources/Hype — only the HypeCore library.
#
# Exit 0 = HypeCore (minus the documented leaves) compiles for watchOS.
# Non-zero = a watch-incompatible symbol leaked into a non-leaf file; the error
# names the offending file/API (add a guard there, or extend BLOCKLIST if it is
# a genuine device-only leaf).
#
# Usage:    scripts/watch-kernel-probe.sh
# Requires: Xcode (or Xcode-beta) with the watchOS SDK installed.

set -euo pipefail

# This machine's Command Line Tools are broken under macOS 27; prefer Xcode-beta
# if present, else fall back to whatever `xcrun` resolves.
if [[ -d /Applications/Xcode-beta.app ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$REPO_ROOT/Sources/HypeCore"

SDK="$(xcrun --sdk watchsimulator --show-sdk-path 2>/dev/null || true)"
if [[ -z "$SDK" ]]; then
  echo "FAIL: watchOS simulator SDK not found (install a watchOS platform in Xcode)." >&2
  exit 2
fi

# Device-only leaf files excluded from the watch build. Each is a leaf the
# interpreter kernel never references. Keep this list SHORT and justified — a new
# entry means a new watch-incompatible dependency that ideally should be guarded
# in-place instead.
BLOCKLIST=(
  "Audio/AudioKitMusicProvider.swift"      # AudioKit + AVFoundation (no watchOS)
  "Audio/ToneSynthesizer.swift"            # AVFoundation engine (watch-unavailable APIs)
  "Audio/SoundPlayer.swift"                # AVFoundation engine (watch-unavailable APIs)
  "Rendering/Scene3DAssetLoader.swift"     # SceneKit + ModelIO (no watchOS)
  "Rendering/Scene3DAssetConverter.swift"  # ModelIO (no watchOS)
  "Export/TargetRuntimeControlViews.swift" # unguarded AppKit view
  "HyperCardImport/StackImportRuntime.swift"   # CStackImport C module (classic .stak import)
  "HyperCardImport/StackImportCImporter.swift" # CStackImport C module (classic .stak import)
  "HyperCardImport/HyperCardToHypeConverter.swift" # depends on StackImportRuntime leaf
  "HyperCardImport/StackImportPackageConverter.swift"      # classic .stak import cluster
  "HyperCardImport/StackImportPackageDocumentImporter.swift" # classic .stak import cluster
  # View / tooling layer that references AppKit-guarded render types or SwiftPM
  # resources — not part of the interpreter execution path.
  "MCP/HypeMCPDocumentBackend.swift"       # uses AppKit-only CardRenderer
  "Theme/ThemeEnvironment.swift"           # SwiftUI glassEffect/systemBackground (watch 26+/unavailable)
  "AI/MeshyAnimationCatalog.swift"         # Bundle.module resource accessor (SwiftPM-only)
  "AI/CardImageCapturer.swift"             # AppKit card rendering
  "AI/HypeToolExecutor.swift"              # AppKit-only render types
  # AI document-tooling executor cluster (lets the AI chat panel mutate the
  # document). Not part of the HypeTalk interpreter execution path; densely
  # coupled to the AppKit render layer via HypeToolExecutor.
  "AI/AIEditTransaction.swift"
  "AI/Executors/FileIOExecutorBranches.swift"
  "AI/Executors/GameRecipeExecutorBranches.swift"
  "AI/Executors/Scene3DExecutorBranches.swift"
  "AI/Executors/SceneNodeExecutorBranches.swift"
  "AI/Executors/WebAssetExecutorBranches.swift"
)

is_blocked() {
  local rel="$1"
  for b in "${BLOCKLIST[@]}"; do
    [[ "$rel" == "$b" ]] && return 0
  done
  return 1
}

FILES=()
while IFS= read -r f; do
  rel="${f#"$CORE"/}"
  is_blocked "$rel" || FILES+=("$f")
done < <(find "$CORE" -name "*.swift" | sort)

TOTAL=$(find "$CORE" -name "*.swift" | wc -l | tr -d ' ')
echo "Compiling ${#FILES[@]} of $TOTAL HypeCore files for arm64-apple-watchos10.0-simulator"
echo "(excluding ${#BLOCKLIST[@]} device-only leaf files)…"

OUT="$(mktemp -d)/HypeWatchCore.o"
xcrun --sdk watchsimulator swiftc \
  -target arm64-apple-watchos10.0-simulator \
  -sdk "$SDK" \
  -parse-as-library \
  -Osize -wmo \
  -emit-object \
  -module-name HypeWatchCore \
  -package-name HypeCore \
  "${FILES[@]}" \
  -o "$OUT"

echo ""
echo "PASS: HypeCore (minus ${#BLOCKLIST[@]} device-only leaves) compiles for watchOS."
echo "watchOS HypeCore __text footprint (-Osize, whole-module):"
size -m "$OUT" 2>/dev/null | grep -E "__TEXT, __text\)" || size "$OUT"
