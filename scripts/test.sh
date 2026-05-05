#!/bin/bash
# Canonical test invocation for the Hype package.
#
# Why `--no-parallel`?
# --------------------
# Many test files (ComprehensiveScriptTests, GIFScriptingTests,
# HypeTalkAITests, …) drive HypeTalk handlers through
# `MessageDispatcher.dispatch`, which bridges sync→async via a
# `DispatchSemaphore`. The bridge:
#
#   1. The test calls `runOnLargeStack { dispatcher.dispatch(...) }`,
#      which spawns a real POSIX `Thread` (for the large stack the
#      interpreter needs for deep recursion) and BLOCKS the calling
#      cooperative thread on a semaphore.
#   2. The worker thread runs `MessageDispatcher.dispatch`, which
#      schedules `Task { @MainActor in await dispatchAsync(...) }`
#      and itself blocks on a semaphore.
#   3. The MainActor task suspends inside `await dispatchAsync(...)`.
#      Its continuation needs a cooperative thread to resume.
#
# Under swift-testing's default parallel runner, each `@Test func`
# is dispatched to a cooperative thread. Once enough sync tests are
# in flight (typically `# CPU cores` of them), every cooperative
# thread is blocked on its `runOnLargeStack` semaphore — and the
# continuations needed to signal those semaphores have nowhere to
# run. Total deadlock: the suite hangs forever consuming ~zero CPU.
#
# `--no-parallel` keeps the suite to one cooperative thread at a
# time, eliminating the starvation. The full 1377-test suite
# completes in ~90 seconds with this flag set.
#
# Long-term fix: convert the affected `@Test func`s and helpers to
# `async` and call `dispatcher.dispatchAsync(...)` directly,
# eliminating the sync→async bridge entirely. Tracked separately.
#
# Usage:
#   scripts/test.sh                    # run everything
#   scripts/test.sh --filter Foo       # forward extra args to swift test

set -e

cd "$(dirname "$0")/.."

exec swift test --no-parallel "$@"
