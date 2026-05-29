import SwiftUI
import AppKit
import BunnyshellCore
import Combine

class AppViewModel: ObservableObject {
    @Published var tabs: [AppTab] = []
    @Published var activeTabId: UUID? = nil {
        didSet {
            syncExplorerRootFromActiveTerminal()
        }
    }
    @Published var terminalSessions: [UUID: Ghostty.SurfaceView] = [:]
    @Published var openFiles: [UUID: String] = [:]
    @Published var explorerRootPath: String = NSHomeDirectory()

    // Prefer the injected Ghostty.App over reaching into NSApplication.shared.delegate.
    // In some SwiftUI/Xcode contexts the delegate may not be our AppDelegate.
    private var ghosttyAppState: Ghostty.App?
    
    let ptyManager = PtyManager()
    private var nextPtyId: UInt32 = 1
    private var terminalSessionObservers: [UUID: AnyCancellable] = [:]
    private var terminalCwds: [UUID: String] = [:]

    func setGhostty(_ ghostty: Ghostty.App) {
        ghosttyAppState = ghostty
    }
    
    func openFile(path: String) {
        if let existing = tabs.first(where: { $0.path == path }) {
            activeTabId = existing.id
            return
        }
        
        // Load file in a background queue to keep UI responsive
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try fsReadFile(path: path)
                let content: String
                switch result {
                case .text(let text, _):
                    content = text
                default:
                    content = "[Binary file]"
                }
                
                let id = UUID()
                let tab = AppTab(id: id, title: self.basename(path), kind: .editor, path: path)
                DispatchQueue.main.async {
                    self.openFiles[id] = content
                    self.tabs.append(tab)
                    self.activeTabId = id
                }
            } catch {
                print("Failed to read file: \(error)")
            }
        }
    }
    
    func spawnTerminal(cwd: String? = nil, retry: Int = 0) {
        let ghostty = ghosttyAppState
        guard let ghostty else {
            print("[bunnyshell] spawnTerminal: missing Ghostty.App (environment not injected yet)")
            return
        }

        guard let app = ghostty.app else {
            if retry == 0 {
                print("[bunnyshell] spawnTerminal: ghostty app not ready (will retry)")
            }
            if retry >= 50 {
                print("[bunnyshell] spawnTerminal: ghostty app still not ready after retries readiness=\(ghostty.readiness.rawValue)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.spawnTerminal(cwd: cwd, retry: retry + 1)
            }
            return
        }

        let id = UUID()
        var config = Ghostty.SurfaceConfiguration()
        config.command = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        // Always set a working directory; fall back to user home so the shell
        // never starts at the filesystem root.
        config.workingDirectory = cwd ?? NSHomeDirectory()

        print("[bunnyshell] spawnTerminal: uuid=\(id.uuidString) command=\(config.command ?? "nil") cwd=\(config.workingDirectory ?? "nil")")
        let session = Ghostty.SurfaceView(app, baseConfig: config, uuid: id)
        if let error = session.error {
            print("Terminal surface init error: \(error)")
        }
        
        DispatchQueue.main.async {
            self.bindTerminalSession(id: id, session: session)
            self.terminalSessions[id] = session
            let tab = AppTab(id: id, title: "terminal", kind: .terminal, path: nil)
            self.tabs.append(tab)
            self.activeTabId = id
        }
    }
    
    func closeTab(id: UUID) {
        if let idx = tabs.firstIndex(where: { $0.id == id }) {
            let removed = tabs.remove(at: idx)
            if activeTabId == id {
                activeTabId = tabs.last?.id
            }

            if removed.kind == .terminal {
                terminalSessionObservers.removeValue(forKey: id)
                terminalCwds.removeValue(forKey: id)
                terminalSessions.removeValue(forKey: id)
            }
            openFiles.removeValue(forKey: id)
            syncExplorerRootFromActiveTerminal()
        }
    }

    func closeActiveTab() {
        guard let activeTabId else { return }
        closeTab(id: activeTabId)
    }

    func selectNextTab() {
        guard !tabs.isEmpty else { return }
        if let current = tabs.firstIndex(where: { $0.id == activeTabId }) {
            activeTabId = tabs[(current + 1) % tabs.count].id
        } else {
            activeTabId = tabs.first?.id
        }
    }

    func selectPreviousTab() {
        guard !tabs.isEmpty else { return }
        if let current = tabs.firstIndex(where: { $0.id == activeTabId }) {
            activeTabId = tabs[(current - 1 + tabs.count) % tabs.count].id
        } else {
            activeTabId = tabs.last?.id
        }
    }

    func selectTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        activeTabId = tabs[index].id
    }
    
    func bindingForFile(id: UUID) -> Binding<String>? {
        guard openFiles[id] != nil else { return nil }
        return Binding<String>(
            get: { self.openFiles[id] ?? "" },
            set: { self.openFiles[id] = $0 }
        )
    }
    
    func serializeState() throws -> String {
        let savedTabs = tabs.map { tab in
            SavedTab(id: tab.id.uuidString, title: tab.title, kind: tab.kind == .terminal ? "terminal" : "editor", path: tab.path)
        }
        
        var stringFiles: [String: String] = [:]
        for (k, v) in openFiles {
            stringFiles[k.uuidString] = v
        }
        
        let state = SavedState(activeTabId: activeTabId?.uuidString, tabs: savedTabs, openFiles: stringFiles)
        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    
    func deserializeState(_ json: String) {
        guard let data = json.data(using: .utf8) else { return }
        let decoder = JSONDecoder()
        guard let state = try? decoder.decode(SavedState.self, from: data) else { return }

        // Restore editor tabs immediately (no Ghostty dependency)
        var newTabs: [AppTab] = []
        var newFiles: [UUID: String] = [:]
        var terminalCount = 0

        for savedTab in state.tabs {
            guard let id = UUID(uuidString: savedTab.id) else { continue }
            let kind: TabKind = savedTab.kind == "terminal" ? .terminal : .editor

            if kind == .editor {
                let tab = AppTab(id: id, title: savedTab.title, kind: kind, path: savedTab.path)
                newTabs.append(tab)
                if let path = savedTab.path {
                    newFiles[id] = state.openFiles[savedTab.id] ?? ""
                }
            } else {
                terminalCount += 1
            }
        }

        DispatchQueue.main.async {
            self.tabs = newTabs
            self.openFiles = newFiles
            self.activeTabId = newTabs.first?.id

            // Spawn fresh terminals via the retry-safe spawnTerminal path.
            // This ensures Ghostty is ready before creating surfaces, and
            // terminals always start at the user home directory.
            let count = terminalCount > 0 ? terminalCount : 1
            for _ in 0 ..< count {
                self.spawnTerminal(cwd: NSHomeDirectory())
            }
        }
    }
    
    private func basename(_ path: String) -> String {
        let parts = path.split(separator: "/")
        return parts.last.map(String.init) ?? path
    }

    private func bindTerminalSession(id: UUID, session: Ghostty.SurfaceView) {
        terminalSessionObservers[id] = session.$pwd.sink { [weak self] pwd in
            guard let self else { return }
            guard let pwd, !pwd.isEmpty else { return }
            self.terminalCwds[id] = pwd
            self.syncExplorerRootFromActiveTerminal()
        }

        if let pwd = session.pwd, !pwd.isEmpty {
            terminalCwds[id] = pwd
        }
    }

    private func syncExplorerRootFromActiveTerminal() {
        guard
            let activeTabId,
            let tab = tabs.first(where: { $0.id == activeTabId }),
            tab.kind == .terminal,
            let cwd = terminalCwds[activeTabId],
            !cwd.isEmpty
        else { return }

        if explorerRootPath != cwd {
            explorerRootPath = cwd
        }
    }
}

struct SavedState: Codable {
    let activeTabId: String?
    let tabs: [SavedTab]
    let openFiles: [String: String]
}

struct SavedTab: Codable {
    let id: String
    let title: String
    let kind: String
    let path: String?
}

struct AppTab: Identifiable, Hashable {
    let id: UUID
    let title: String
    let kind: TabKind
    let path: String?
}

enum TabKind: Codable {
    case terminal
    case editor
}
