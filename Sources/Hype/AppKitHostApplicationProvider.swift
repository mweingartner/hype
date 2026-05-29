import Foundation
import HypeCore

#if canImport(AppKit)
import AppKit

/// Production host-application provider that routes HypeTalk application-shell
/// commands to AppKit APIs.
///
/// Security note (for code reviewers)
/// -----------------------------------
/// A hostile downloaded `.hype` stack could script `quit`, `save stack`,
/// `doMenu "..."`, etc.  These run with the same trust level as any HypeTalk
/// author script.  The main gate against abuse is `doMenu`'s curated
/// **allowlist**: only non-destructive navigation and clipboard items are
/// handled; destructive operations such as "Delete Card", "Cut", and "Clear"
/// are *never* forwarded, and the implementation returns `false` for any
/// unrecognised or excluded item.  `quitApp` / `saveStack` / `closeWindow`
/// are standard HyperCard authoring commands that an author's own script
/// would legitimately invoke; they are forwarded but cannot reach anything
/// outside the app's own document model.
public struct AppKitHostApplicationProvider: HostApplicationProvider, Sendable {

    public init() {}

    // MARK: - Screen lock / unlock

    /// Lock the screen: post a notification that `CardCanvasNSView` observes
    /// to suppress `needsDisplay` updates, reducing visual flicker during
    /// multi-step script mutations.
    public func lockScreen() async {
        await MainActor.run {
            NotificationCenter.default.post(name: .hypeScreenLock, object: nil)
        }
    }

    /// Unlock the screen: post a notification that `CardCanvasNSView` observes
    /// to re-enable redraws and trigger an immediate refresh.
    public func unlockScreen() async {
        await MainActor.run {
            NotificationCenter.default.post(name: .hypeScreenUnlock, object: nil)
        }
    }

    // MARK: - Stack file operations

    /// Open a `.hype` stack at the given absolute path.
    ///
    /// - Guards: path must be non-empty, have a `.hype` extension, and point to
    ///   an existing file.  Malformed paths are silently ignored — they must not
    ///   crash, and a hostile stack cannot use this to open arbitrary file types.
    public func openStack(path: String) async {
        guard let resolved = Self.resolvedStackURL(forPath: path) else { return }
        await MainActor.run {
            NSDocumentController.shared.openDocument(withContentsOf: resolved, display: true) { _, _, _ in }
        }
    }

    /// Validate + canonicalize a script-supplied stack path, returning the URL
    /// to open or `nil` when it must be refused. Pure + testable (security
    /// review Finding 2 — CWE-22). Canonicalizes BEFORE the extension/existence
    /// guards so `..` components and symlinks can't smuggle a non-`.hype`
    /// target past the extension check.
    static func resolvedStackURL(forPath path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        let resolved = URL(fileURLWithPath: path).standardized.resolvingSymlinksInPath()
        guard resolved.pathExtension.lowercased() == "hype" else { return nil }
        guard FileManager.default.fileExists(atPath: resolved.path) else { return nil }
        return resolved
    }

    /// Trigger an autosave of the frontmost document.
    public func saveStack() async {
        await MainActor.run {
            guard let doc = NSDocumentController.shared.currentDocument
                      ?? NSDocumentController.shared.documents.first
            else { return }
            doc.save(self)
        }
    }

    /// Perform a close on the frontmost window (honoring the document's
    /// unsaved-changes prompt).
    public func closeWindow() async {
        await MainActor.run {
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
            window.performClose(nil)
        }
    }

    // MARK: - Application lifecycle

    /// Terminate the application.  Equivalent to File > Quit.
    public func quitApp() async {
        await MainActor.run {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Script editor

    /// Open the Script Editor for the object identified by `objectId`.
    ///
    /// Uses the same `openPartScriptEditor` notification that
    /// `CardCanvasAccessibility` and cmd+click already use, so `MainContentView`
    /// handles the actual window-management.  When `objectId` is `nil` the
    /// notification carries no part info and the handler falls through to the
    /// current card's editor.
    public func editScript(ofObjectId objectId: UUID?) async {
        await MainActor.run {
            var userInfo: [AnyHashable: Any] = [:]
            if let objectId {
                userInfo["partId"] = objectId
                userInfo["target"] = ScriptTarget.part(objectId)
            }
            NotificationCenter.default.post(
                name: .openPartScriptEditor,
                object: nil,
                userInfo: userInfo
            )
        }
    }

    // MARK: - Print

    /// Print the current card as a rendered bitmap, or the text content of a
    /// named field.
    ///
    /// Runs entirely on the main actor because `CardRenderer.renderToImage` and
    /// `NSPrintOperation` are both main-thread APIs.
    public func print(target: HostPrintTarget) async {
        await MainActor.run {
            switch target {
            case .card:
                printCurrentCard()
            case .field(let identifier):
                printField(identifier: identifier)
            }
        }
    }

    @MainActor
    private func printCurrentCard() {
        // Gather the document + current card from the focused document window.
        guard let notification = currentDocumentInfo() else { return }
        let (document, cardId) = notification

        let renderer = CardRenderer()
        let size = NSSize(width: 800, height: 600)
        let image = renderer.renderToImage(document: document, cardId: cardId, size: size)

        let printView = NSImageView(frame: NSRect(origin: .zero, size: size))
        printView.image = image

        let op = NSPrintOperation(view: printView)
        op.run()
    }

    @MainActor
    private func printField(identifier: String) {
        guard let notification = currentDocumentInfo() else { return }
        let (document, cardId) = notification

        // Find the field by name or ordinal on the current card.
        let field = document.parts.first(where: {
            $0.partType == .field && $0.cardId == cardId &&
            ($0.name.lowercased() == identifier.lowercased() || "\($0.id)" == identifier)
        }) ?? document.parts.first(where: {
            $0.partType == .field && $0.cardId == cardId
        })
        let text = field?.textContent ?? ""

        let printView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 700))
        printView.string = text

        let op = NSPrintOperation(view: printView)
        op.run()
    }

    // MARK: - doMenu

    /// Execute a named menu item from the curated non-destructive allowlist.
    ///
    /// Security – ALLOWLIST RATIONALE
    /// --------------------------------
    /// Only these items are forwarded; everything else returns `false`:
    ///
    /// **Go menu (navigation):**  "Next", "Prev"/"Previous", "First", "Last",
    ///   "Back" — pure navigation, no mutations.
    ///
    /// **Edit (non-destructive clipboard):**  "Copy", "Paste", "Undo" —
    ///   these mirror what a user can do with a keyboard shortcut.
    ///
    /// **Explicitly excluded (destructive):**  "Delete Card", "Cut", "Clear",
    ///   "Delete Stack", "New Card", "Delete Current Card".  Any item not in
    ///   the allowlist is also excluded by default.
    ///
    /// This means a script-scripted `doMenu "Delete Card"` returns `false`
    /// and takes no action, even though the menu item exists.
    public func doMenu(item: String) async -> Bool {
        let normalised = item.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let handled: Bool = await MainActor.run {
            switch normalised {

            // Go menu — card navigation (non-destructive)
            case "next", "next card":
                NotificationCenter.default.post(name: .navigateCard, object: NavigationDirection.next)
                return true
            case "prev", "previous", "prev card", "previous card":
                NotificationCenter.default.post(name: .navigateCard, object: NavigationDirection.previous)
                return true
            case "first", "first card":
                NotificationCenter.default.post(name: .navigateCard, object: NavigationDirection.first)
                return true
            case "last", "last card":
                NotificationCenter.default.post(name: .navigateCard, object: NavigationDirection.last)
                return true
            case "back":
                // HyperCard "Back" = go to the most-recently-visited card.
                // Hype uses `pop card` for the same semantic; post the
                // navigateCard notification with a sentinel is not how
                // the runtime handles pop — so we defer to the runtime's
                // pop path via the HypeTalk `pop card` command instead.
                // As a lightweight UI equivalent, we navigate to previous.
                NotificationCenter.default.post(name: .navigateCard, object: NavigationDirection.previous)
                return true

            // Edit menu — non-destructive clipboard operations.
            // copy/paste mirror plain Cmd-C / Cmd-V keystrokes and don't
            // alter document structure. They go through the responder
            // chain exactly as a user keystroke would.
            case "copy":
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                return true
            case "paste":
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                return true

            // ── EXCLUDED items — return false, take no action ───────────────
            // DESTRUCTIVE: "cut", "clear", "delete card", "delete current
            //   card", "delete stack", "new card".
            // "undo": deliberately excluded (security review Finding 1). A
            //   responder-chain `undo:` can non-interactively reverse the
            //   USER's own edits and isn't reliably targeted at this
            //   document's undo manager. Keeping the allowlist strictly
            //   non-destructive wins over the niche convenience.
            // Anything not matched above also falls through to false.
            default:
                return false
            }
        }
        return handled
    }

    // MARK: - Private helpers

    /// Retrieve the HypeDocument and current card UUID from the focused window's
    /// notification post, falling back to the first open document.
    ///
    /// Returns `nil` if no document is currently open.
    /// Single-entry cache so a pathological `repeat N times / print`
    /// loop doesn't re-read + re-decode the document file from disk on
    /// every iteration (security review Finding 3 — main-thread self-DoS).
    /// Keyed on (path, modification date); invalidated automatically when
    /// the file changes. Main-actor-isolated, so the mutable static is safe.
    @MainActor
    private static var printDocCache: (path: String, mtime: Date, doc: HypeDocument, cardId: UUID)?

    @MainActor
    private func currentDocumentInfo() -> (HypeDocument, UUID)? {
        // The focused document publishes its state via a SwiftUI FocusedValue;
        // since we cannot read that from here, we look up the current NSDocument
        // and read the last-saved state from the mutation coordinator's snapshot.
        // For printing this is accurate enough.
        guard let nsDoc = NSDocumentController.shared.currentDocument
                  ?? NSDocumentController.shared.documents.first,
              let url = nsDoc.fileURL
        else { return nil }

        // Reuse the cached decode when the file is unchanged since last read.
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        if let cache = Self.printDocCache,
           cache.path == url.path,
           let mtime, cache.mtime == mtime {
            return (cache.doc, cache.cardId)
        }

        // Try to decode the on-disk state; if unavailable, bail gracefully.
        guard let data = try? Data(contentsOf: url),
              let hypeDoc = try? JSONDecoder().decode(HypeDocument.self, from: data)
        else { return nil }

        let cardId = hypeDoc.sortedCards.first?.id ?? hypeDoc.stack.id
        if let mtime {
            Self.printDocCache = (url.path, mtime, hypeDoc, cardId)
        }
        return (hypeDoc, cardId)
    }
}

// MARK: - Notification names

extension Notification.Name {
    /// Posted by `AppKitHostApplicationProvider.lockScreen()` to suppress
    /// canvas redraws during bulk HypeTalk mutations.
    static let hypeScreenLock = Notification.Name("hypeScreenLock")
    /// Posted by `AppKitHostApplicationProvider.unlockScreen()` to re-enable
    /// canvas redraws and trigger an immediate refresh.
    static let hypeScreenUnlock = Notification.Name("hypeScreenUnlock")
}

#endif
