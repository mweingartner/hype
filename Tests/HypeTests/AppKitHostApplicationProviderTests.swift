import Foundation
import AppKit
import Testing
@testable import Hype
@testable import HypeCore

/// Tests for the REAL `AppKitHostApplicationProvider` (the spy-based dispatch
/// tests live in HypeCoreTests; these exercise the production AppKit bridge and
/// path-validation logic that the spy can't reach).
@MainActor
@Suite("AppKitHostApplicationProvider — host bridge", .serialized)
struct AppKitHostApplicationProviderTests {

    // MARK: - doMenu full menu surface

    @Test("doMenu forwards Hype-owned menu items across menus")
    func doMenuForwardsHypeOwnedMenuItems() async {
        let p = AppKitHostApplicationProvider()
        let items = [
            "First Card", "Previous Card", "Next Card", "Last Card",
            "New Card", "Delete Current Card", "Edit Card", "Edit Background",
            "Button", "Field", "PDF Viewer", "MusicKit Search", "3D Scene",
            "Group", "Ungroup", "Move to Background", "Move to Card",
            "Bring Forward", "Send to Back", "Align Horizontal Center",
            "Browse", "Select", "Bucket Fill",
            "Switch Runtime/Edit Mode", "Show Objects Panel", "Target Platforms...",
            "Export Runtime Packages...", "Test Stack in Simulator...",
            "Show AI Assistant", "Show Console", "Halt Current Run",
            "Asset Repository", "AI Context Library", "Theme Designer",
            "Duplicate",
        ]
        for item in items {
            #expect(await p.doMenu(item: item) == true, "'\(item)' should be handled")
        }
    }

    @Test("chooseTool forwards classic tool names")
    func chooseToolForwardsClassicNames() async {
        let p = AppKitHostApplicationProvider()
        #expect(await p.chooseTool("browse") == true)
        #expect(await p.chooseTool("select") == true)
        #expect(await p.chooseTool("spray can") == true)
        #expect(await p.chooseTool("not a real tool") == false)
    }

    @Test("doMenu normalization: padded + mixed case + ellipsis still resolves")
    func doMenuNormalizes() async {
        let p = AppKitHostApplicationProvider()
        #expect(await p.doMenu(item: "  Next  ") == true)
        #expect(await p.doMenu(item: "NEXT CARD") == true)
        #expect(await p.doMenu(item: "selectall") == true)
        #expect(await p.doMenu(item: "copy") == true)
        #expect(await p.doMenu(item: "Target Platforms…") == true)
        #expect(AppKitHostApplicationProvider.normalizedMenuKey("Target Platforms…") == "targetplatforms")
    }

    @Test("doMenu supports classic/system mutating edit commands")
    func doMenuSupportsMutatingEditCommands() async {
        let p = AppKitHostApplicationProvider()
        let commands = [
            "Cut", "Copy", "Paste", "Clear", "Undo", "Redo", "Select All",
            "New Card", "Delete Current Card",
        ]
        for item in commands {
            #expect(await p.doMenu(item: item) == true, "'\(item)' should be handled")
        }
    }

    @Test("doMenu falls back to enabled NSMenuItem target/action entries")
    func doMenuDispatchesEnabledMainMenuItem() async {
        let oldMenu = NSApplication.shared.mainMenu
        let mainMenu = NSMenu(title: "Main")
        let topItem = NSMenuItem(title: "Custom", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Custom")
        let item = NSMenuItem(title: "Revert…", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        item.target = NSApplication.shared
        submenu.addItem(item)
        topItem.submenu = submenu
        mainMenu.addItem(topItem)
        NSApplication.shared.mainMenu = mainMenu
        defer { NSApplication.shared.mainMenu = oldMenu }

        let p = AppKitHostApplicationProvider()
        #expect(await p.doMenu(item: "Revert") == true)
    }

    @Test("doMenu does not dispatch disabled NSMenuItem target/action entries")
    func doMenuDoesNotDispatchDisabledMainMenuItem() async {
        let oldMenu = NSApplication.shared.mainMenu
        let mainMenu = NSMenu(title: "Main")
        let topItem = NSMenuItem(title: "Custom", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Custom")
        let item = NSMenuItem(title: "Disabled Thing", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        item.target = NSApplication.shared
        item.isEnabled = false
        submenu.addItem(item)
        topItem.submenu = submenu
        mainMenu.addItem(topItem)
        NSApplication.shared.mainMenu = mainMenu
        defer { NSApplication.shared.mainMenu = oldMenu }

        let p = AppKitHostApplicationProvider()
        #expect(await p.doMenu(item: "Disabled Thing") == false)
    }

    @Test("doMenu unknown item is unhandled by default")
    func doMenuUnknownReturnsFalse() async {
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
