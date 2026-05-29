import SwiftUI
import Cocoa
import os

enum TerminalRestoreError: Error {
    case delegateInvalid
}

class AppDelegate: NSObject, NSApplicationDelegate {
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.crynta.bunnyshell", category: "app")

    let ghostty: Ghostty.App = Ghostty.App()
    var undoManager: UndoManager? = UndoManager()
    
    func applicationDidFinishLaunching(_ notification: Notification) {}
    
    func checkForUpdates(_ sender: Any?) {}
    
    func performGhosttyBindingMenuKeyEquivalent(with event: NSEvent) -> Bool {
        return false
    }

    func closeAllWindows(_ sender: Any?) {}
    func toggleVisibility(_ sender: Any?) {}
    func syncFloatOnTopMenu(_ window: NSWindow) {}
    func setSecureInput(_ mode: Any) {}
    func toggleQuickTerminal(_ sender: Any?) {}
}

class HiddenTitlebarTerminalWindow: NSWindow {}
class TerminalWindow: NSWindow {}

class DummySurfaceTree {
    var isSplit: Bool { false }
}

class BaseTerminalController: NSWindowController {
    @objc var commandPaletteIsShowing: Bool { false }
    @objc var focusFollowsMouse: Bool { false }
    var surfaceTree = DummySurfaceTree()
    @objc func changeTabTitle(_ sender: Any?) {}
    var focusedSurface: Ghostty.SurfaceView? { nil }
    func toggleBackgroundOpacity() {}
    var titleOverride: String? = nil
    func promptTabTitle() {}
}

@main
struct BunnyshellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
                .background(AppTheme.bg)
                .environmentObject(appDelegate.ghostty)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}
