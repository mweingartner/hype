# Vendored AudioKit 5.2.3 (patched)

This directory is a vendored copy of [AudioKit](https://github.com/AudioKit/AudioKit)
at tag `5.2.3` (revision `9d25f6c1e40975f321786d9b70502b4d74421707`), MIT licensed
(see `LICENSE` in this directory). `Tests/` and the playground are omitted.

## Why vendored

Current macOS SDKs annotate `AVAudioUnit.auAudioUnit` as macOS 13+. Upstream
AudioKit (every published tag through 5.7.2, and `main` as of 2026-06-10)
declares a macOS 10.13/11 minimum and accesses `auAudioUnit` unguarded in
`Sources/AudioKit/Nodes/Effects/Dynamics/{Compressor,Expander,DynamicsProcessor}.swift`,
so the package no longer compiles as a remote dependency under Swift 6.4 /
the macOS 27 SDK. SwiftPM offers no way to override a dependency's declared
platform minimums from the root package.

## Local patch (the only changes — both in `Package.swift`)

- platforms raised from `[.macOS(.v10_13), .iOS(.v11), .tvOS(.v11)]` to
  `[.macOS(.v13), .iOS(.v16), .tvOS(.v16)]`.
- `swift-tools-version` raised from 5.3 to 5.9 (PackageDescription 5.3 has no
  `.v13`/`.v16` platform enums).

No Swift source files are modified. Hype itself targets macOS 15+, so the
raised minimum is satisfied everywhere this copy is built.

## Relationship to runtime export

`TargetRuntimePackageBuilder` embeds this vendored AudioKit copy into generated
iPhone/iPad/tvOS runtime packages and points the generated `HypeRuntimeCore`
package at `Vendor/AudioKit`. Runtime exports therefore build from the same
patched source as the authoring app and do not need a remote AudioKit fetch.

## Upgrading

If upstream ships a release whose declared platforms are macOS 13+ (or guards
`auAudioUnit`), delete this directory and restore
`.package(url: "https://github.com/AudioKit/AudioKit.git", exact: "<version>")`
in the root `Package.swift` and in `TargetRuntimePackageBuilder`.
