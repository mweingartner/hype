# Legacy Card Script Lifecycle Test Plan

This plan defines durable parity coverage for classic HyperCard lifecycle
messages in Hype. It is a test plan, not a claim that every item is implemented
today.

## References

- HyperCard Center `openStack`: HyperCard sends `openStack` when navigation
  enters a stack different from the most recent card's stack.
  https://hypercard.center/HyperTalkReference/systemmessages/openStack
- Apple, *HyperCard Script Language Guide*, Chapter 8: `idle` is sent to the
  current card repeatedly when nothing else is happening and the Browse tool is
  current.
  https://cancel.fm/stuff/share/HyperCard_Script_Language_Guide_1.pdf
- Apple, *HyperCard Script Language Guide*, Chapter 8 message order table:
  startup/resume and card/background/stack creation/deletion have defined
  open/close ordering.
- Apple, *HyperCard Script Language Guide*, `lockMessages`: prevents open,
  close, suspend, and resume system messages while true, and HyperCard resets it
  after pending handlers.

## Product Split Under Test

Hype intentionally separates authoring from runtime behavior:

- **Edit/authoring mode:** quiet by default. Opening a document, selecting
  cards, editing scripts, or changing tools must not automatically dispatch
  `openStack`, `openCard`, `closeCard`, or `idle`.
- **Runtime/Browse compatibility mode:** HyperCard-like lifecycle dispatch is
  enabled through the normal `StackRuntime` and `MessageDispatcher` path.
- **Future compatibility preview:** if Hype later adds a Browse-tool preview
  inside authoring, test it as a third mode with explicit user opt-in. It must
  not make ordinary authoring noisy again.

## Canonical Fixture Stack

Maintain one generated fixture and one imported-HyperCard fixture with the same
logical shape:

- Two cards sharing the same background where possible.
- A card field named `Log` on each card.
- A `Clear` button.
- A `Next` button.
- Stack, card, and button scripts below.

The generated fixture should live in a test helper so assertions do not depend
on a mutable checked-in `.hype` user document. Imported-stack parity tests may
use a tiny checked-in legacy fixture only if the fixture is treated as test data
and never rewritten in place.

### Stack Script

```hypercard
global gIdleCount

on logEvent what
  put the ticks & tab & what & return after card field "Log"
end logEvent

on openStack
  global gIdleCount
  put 0 into gIdleCount
  logEvent "STACK openStack"
  pass openStack
end openStack

on closeStack
  logEvent "STACK closeStack"
  pass closeStack
end closeStack

on idle
  global gIdleCount
  add 1 to gIdleCount
  if gIdleCount <= 5 then logEvent "STACK idle" && gIdleCount
  pass idle
end idle
```

### Card Script

Attach this script to each card:

```hypercard
on openCard
  logEvent "CARD openCard" && the short name of this card
  pass openCard
end openCard

on closeCard
  logEvent "CARD closeCard" && the short name of this card
  pass closeCard
end closeCard
```

### Clear Button Script

```hypercard
on mouseUp
  put empty into card field "Log"
end mouseUp
```

### Next Button Script

```hypercard
on mouseUp
  logEvent "BUTTON Next mouseUp before go"
  go next card
  logEvent "BUTTON Next mouseUp after go"
end mouseUp
```

## Golden HyperCard Baseline

Run the canonical fixture in HyperCard 2.4, record the log, and keep the result
as compact test evidence in this document or a neighboring text fixture.

Baseline observations to preserve:

- Opening the stack logs stack/card open lifecycle in HyperCard's observed
  order.
- Clicking `Next` logs the button pre-navigation line, card close/open lifecycle
  around the navigation, then the button post-navigation line if HyperCard
  continues the handler after `go next card`.
- With `lockMessages` true, `go next card` suppresses `openCard` and
  `closeCard`.
- After `lockMessages` is false again, the next card navigation logs lifecycle
  messages again.
- `idle` logs while the Browse tool is current and the stack is otherwise idle.
- Switching to Button, Field, or another authoring tool stops Browse-tool idle
  delivery.

## Automated Regression Layers

Use multiple layers because lifecycle behavior spans parser, dispatcher,
runtime, and app mode state.

1. **Parser/validator coverage**
   - `on openStack`, `on closeStack`, `on openCard`, `on closeCard`, and
     `on idle` parse as normal handlers.
   - Hook-context validation accepts card/background lifecycle handlers that
     pass up to stack scripts.
   - `set the lockMessages to true/false` parses and validates as a global
     environment property.

2. **MessageDispatcher ordering coverage**
   - Directly dispatch lifecycle messages against an in-memory document and
     assert exact `Log` field contents.
   - Assert pass-up order for card -> background -> stack when card and
     background handlers use `pass`.
   - Assert no false positives: `on idleState` must not handle `idle`.

3. **StackRuntime navigation coverage**
   - Start a runtime session on card 1.
   - Dispatch or perform runtime navigation to card 2.
   - Assert exact event sequence and current-card state.
   - Repeat through button `mouseUp` so the test covers `go next card` inside a
     running handler, not only a host-initiated navigation.

4. **Mode-gating coverage**
   - Edit mode document open/select-card must not mutate `Log`.
   - Runtime/Browse mode open must dispatch lifecycle according to the runtime
     compatibility contract.
   - Authoring tool changes away from Browse must stop automatic `idle`.
   - Returning to Browse may resume idle only if runtime compatibility mode is
     active.

5. **Imported stack coverage**
   - Import the legacy fixture.
   - Assert scripts are preserved on stack/card/button objects.
   - Run the same runtime lifecycle tests against the imported document.

6. **Manual app smoke**
   - Install `/Applications/Hype.app` for app-facing changes.
   - Open the fixture in edit mode: `Log` remains quiet.
   - Enter runtime/Browse mode with tracing visible: lifecycle order matches
     the automated expectation.

## Core Test Matrix

| Case | Mode | Action | Expected |
| --- | --- | --- | --- |
| Open document in authoring | Edit | Open fixture | `Log` remains empty |
| Select another card in authoring | Edit | Select card 2 | No automatic `closeCard` or `openCard` |
| Start runtime | Browse/runtime | Open fixture | `STACK openStack` and current-card `CARD openCard` in defined order |
| Navigate by button | Browse/runtime | Click `Next` | Button before line, lifecycle navigation lines, button after line |
| Navigate by command | Browse/runtime | `go next card` | Same lifecycle order minus button lines |
| Lock messages | Browse/runtime | `set lockMessages true`; navigate | No open/close lifecycle lines during locked navigation |
| Unlock messages | Browse/runtime | `set lockMessages false`; navigate | Open/close lifecycle lines resume |
| Idle in browse | Browse/runtime | Wait idle ticks | `STACK idle 1` through `STACK idle 5` appear at most once each |
| Idle in authoring tool | Runtime session, non-browse tool | Choose Button or Field tool and wait | No new `STACK idle` lines |
| Close runtime | Browse/runtime | Close document/session | `closeCard`, `closeBackground` if applicable, and `closeStack` in defined order |

## Exact Assertions

Assert on content, not existence. Use normalized event tokens when tick values
are nondeterministic:

```text
STACK openStack
CARD openCard <card name>
BUTTON Next mouseUp before go
CARD closeCard <card 1 name>
CARD openCard <card 2 name>
BUTTON Next mouseUp after go
STACK idle 1
STACK idle 2
STACK idle 3
STACK idle 4
STACK idle 5
```

When tick values are useful for debugging, keep them in the `Log` field but
strip the leading tick column before comparing order.

## Implementation Notes

- Route all lifecycle dispatch through `StackRuntime` and `MessageDispatcher`.
  Tests should fail if a view calls the interpreter directly.
- Keep edit-mode tests outside `StackRuntime`; edit mode should mutate the
  document only through authoring actions.
- `lockMessages` should suppress open/close/suspend/resume lifecycle dispatch,
  not unrelated user messages such as `mouseUp`.
- `lockMessages` reset timing needs a separate expectation. HyperCard resets it
  after pending handlers; Hype should either match that behavior in runtime
  compatibility mode or document the intentional difference in
  `decisions.md`.
- Avoid sleeping in tests. Inject or drive the runtime clock/tick scheduler so
  `idle` coverage is deterministic.
- Imported fixture tests must run on temporary copies. Never rewrite a source
  `.hype` package as part of load or verification.

## Verification Commands

For lifecycle-only HypeTalk work:

```bash
scripts/test.sh --filter EventDispatchTests
scripts/test.sh --filter StackRuntimeAsyncTests
scripts/test.sh --filter HyperTalkReferenceCompatibilityTests
```

For parser, interpreter, chunk, file-format, or protocol changes that affect
lifecycle scripts, also keep the property/fuzz suite green:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  swift test --no-parallel --filter InterpreterFuzzNoCrashTests --filter InterpreterMetamorphicTests
```

For app-facing lifecycle behavior:

```bash
PATH=/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Codex.app/Contents/Resources ./script/build_and_run.sh --deploy
/usr/bin/open -n /Applications/Hype.app
```

## Done Criteria

- HyperCard 2.4 baseline evidence is recorded for the canonical fixture.
- Automated tests cover edit quietness, runtime open/navigation/close ordering,
  `lockMessages`, and Browse-tool-only idle behavior.
- Imported legacy fixture scripts pass the same runtime lifecycle assertions as
  the generated fixture.
- Documentation names any intentional divergence from HyperCard, especially
  around `lockMessages` reset timing or authoring preview behavior.
