#!/bin/bash
#
# mpd deploy-gate wrapper. Builds Hype and installs Hype.app into /Applications
# via the existing deploy path (script/build_and_run.sh --deploy: build → bundle
# → local-codesign → ditto into /Applications). It pins the Xcode-beta toolchain
# because this machine's Command Line Tools are broken (dyld/Swift mismatch — see
# scripts/mpd-test.sh and AGENTS.md); /usr/bin/swift honors DEVELOPER_DIR.
#
# Wired as the "deploy" command in .mpd/config.json so the mpd Deploy gate (and
# the standing end-of-cycle default) installs the built app to /Applications
# rather than leaving it in dist/. mpd requires this to exit 0 to record the
# Deploy gate as PASS. Honors an externally-set DEVELOPER_DIR; otherwise pins
# Xcode-beta.
set -uo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"

exec script/build_and_run.sh --deploy
