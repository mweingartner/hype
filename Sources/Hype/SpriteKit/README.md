# SpriteKit / AppKit host views — note for new contributors

You will see this pattern repeated across every file in this folder and across
the AppKit host views in `Sources/Hype/Views/*HostView.swift`:

```swift
required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
}
```

This is the standard way to satisfy `NSCoder` for non-storyboard AppKit views.
**The `fatalError` never fires in production** because:

- Hype's UI is built entirely in code (no `.xib` / `.storyboard` files).
- Every `NSView` subclass here is instantiated only through the in-code
  initializer (`init(frame:)`, `init()`, or a designated init defined on the
  class).
- The `init?(coder:)` initializer is required by `NSView`'s class contract —
  Swift forces you to declare it on every subclass — but no one in Hype calls
  it.

Don't try to "fix" these stubs to return `nil` instead. The `fatalError` is a
loud signal that something serious has gone wrong (a future contributor added
storyboard-loading without realizing this folder's contract). `nil` would be a
quieter failure mode for the same underlying bug.

If you ever genuinely need NSCoder-based loading for one of these views (e.g.,
to support state restoration), implement it explicitly on that one class — and
update this note so future contributors know one or more classes have a real
init(coder:).
