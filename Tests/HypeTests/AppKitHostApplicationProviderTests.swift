import Foundation
import Testing
@testable import Hype
@testable import HypeCore

/// Security-focused tests for the REAL `AppKitHostApplicationProvider`
/// (the spy-based dispatch tests live in HypeCoreTests; these exercise the
/// production allowlist + path-validation logic that the spy can't reach).
@MainActor
@Suite("AppKitHostApplicationProvider — security gates")
struct AppKitHostApplicationProviderTests {

    // MARK: - doMenu allowlist (the primary destructive-action gate)

    @Test("doMenu forwards non-destructive navigation items")
    func allowlistAllowsNavigation() async {
        let p = AppKitHostApplicationProvider()
        for item in ["Next", "Prev", "Previous", "First", "Last", "Back", "Copy", "Paste"] {
            #expect(await p.doMenu(item: item) == true, "'\(item)' should be handled")
        }
    }

    @Test("doMenu normalization: padded + mixed case still resolves")
    func allowlistNormalizes() async {
        let p = AppKitHostApplicationProvider()
        #expect(await p.doMenu(item: "  Next  ") == true)
        #expect(await p.doMenu(item: "NEXT CARD") == true)
        #expect(await p.doMenu(item: "copy") == true)
    }

    @Test("doMenu REFUSES every destructive item (returns false, no action)")
    func allowlistRefusesDestructive() async {
        let p = AppKitHostApplicationProvider()
        // Each of these, in several case/space variants, must be unhandled.
        let destructive = [
            "Delete Card", "delete card", "  DELETE CARD  ",
            "Delete Stack", "delete stack",
            "Cut", "cut",
            "Clear", "clear",
            "New Card", "new card",
            "Delete Current Card",
        ]
        for item in destructive {
            #expect(await p.doMenu(item: item) == false, "'\(item)' must be refused")
        }
    }

    @Test("doMenu 'undo' is excluded (security review Finding 1)")
    func allowlistExcludesUndo() async {
        let p = AppKitHostApplicationProvider()
        #expect(await p.doMenu(item: "undo") == false)
        #expect(await p.doMenu(item: "Undo") == false)
    }

    @Test("doMenu unknown item is unhandled by default")
    func allowlistDefaultsToFalse() async {
        let p = AppKitHostApplicationProvider()
        #expect(await p.doMenu(item: "Frobnicate") == false)
        #expect(await p.doMenu(item: "") == false)
    }

    // MARK: - openStack path validation (CWE-22)

    @Test("resolvedStackURL accepts a real .hype file")
    func openStackAcceptsRealHype() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hype-host-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let stack = dir.appendingPathComponent("real.hype")
        try Data("{}".utf8).write(to: stack)

        let resolved = AppKitHostApplicationProvider.resolvedStackURL(forPath: stack.path)
        #expect(resolved != nil, "a genuine .hype file must be accepted")
        #expect(resolved?.pathExtension.lowercased() == "hype")
    }

    @Test("resolvedStackURL refuses non-.hype extensions")
    func openStackRefusesNonHype() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hype-host-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let txt = dir.appendingPathComponent("notes.txt")
        try Data("secret".utf8).write(to: txt)

        #expect(AppKitHostApplicationProvider.resolvedStackURL(forPath: txt.path) == nil)
    }

    @Test("resolvedStackURL refuses empty + nonexistent paths")
    func openStackRefusesEmptyAndMissing() {
        #expect(AppKitHostApplicationProvider.resolvedStackURL(forPath: "") == nil)
        #expect(AppKitHostApplicationProvider.resolvedStackURL(forPath: "/no/such/stack.hype") == nil)
    }

    @Test("resolvedStackURL refuses a .hype symlink that resolves to a non-.hype file (CWE-22)")
    func openStackRefusesDisguisingSymlink() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hype-host-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // A real non-hype file...
        let secret = dir.appendingPathComponent("passwd.txt")
        try Data("secret".utf8).write(to: secret)
        // ...behind a .hype-named symlink. Canonicalization must see through it.
        let disguise = dir.appendingPathComponent("disguise.hype")
        try FileManager.default.createSymbolicLink(at: disguise, withDestinationURL: secret)

        #expect(AppKitHostApplicationProvider.resolvedStackURL(forPath: disguise.path) == nil,
                "a .hype symlink pointing at a non-.hype file must be refused")
    }

    @Test("resolvedStackURL collapses .. traversal before the extension check")
    func openStackCollapsesTraversal() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hype-host-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let txt = dir.appendingPathComponent("notes.txt")
        try Data("x".utf8).write(to: txt)
        // Path with a .. segment that resolves to the .txt — must be refused.
        let traversal = dir.appendingPathComponent("sub/../notes.txt").path
        #expect(AppKitHostApplicationProvider.resolvedStackURL(forPath: traversal) == nil)
    }
}
