#!/bin/bash
# Canonical test invocation for the Hype package.
#
# Parallel-runner deadlock — RESOLVED
# ------------------------------------
# This suite previously required `--no-parallel` to avoid a cooperative-
# thread starvation deadlock:
#
#   1. Each @Test func called `runOnLargeStack { dispatcher.dispatch(...) }`,
#      which spawned a POSIX Thread (for the 8 MB stack the interpreter needs)
#      and BLOCKED the calling cooperative thread on a DispatchSemaphore.
#   2. The worker thread scheduled `Task { @MainActor in await dispatchAsync(...) }`.
#   3. The MainActor task's continuation needed a cooperative thread to resume,
#      but all cooperative threads were blocked on their semaphores.
#      Total deadlock: suite hung consuming ~zero CPU.
#
# Fix (2026-05-05): all @Test functions that drive dispatch are now `async`,
# and the shared `runOnLargeStack` helper in TestSupport/AsyncDispatch.swift
# uses `withCheckedContinuation` to SUSPEND (not block) the cooperative
# thread. The worker Thread resumes the continuation when done, returning
# the thread to the pool so other continuations can run.
#
# The full 1377-test suite now completes in ~82 seconds under the default
# parallel runner. `--no-parallel` is retained as a fallback for debugging
# test-ordering issues.
#
# Usage:
#   scripts/test.sh                    # run everything (parallel)
#   scripts/test.sh --no-parallel      # sequential, for debugging ordering
#   scripts/test.sh --filter Foo       # forward extra args to swift test

set -e

cd "$(dirname "$0")/.."

exec swift test "$@"
