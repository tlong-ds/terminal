import SwiftUI
import BunnyshellCore

// MARK: - Compact tab pill (Safari-style)

private struct TabPill: View {
    let tab: AppTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    private var icon: String { tab.kind == .terminal ? "terminal" : "doc.text" }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isActive ? .primary : .secondary)

            Text(tab.title)
                .font(.system(size: 12, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .leading)

            // Close button — always visible on active, visible on hover for inactive
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(isHovered ? 0.12 : 0))
                    )
            }
            .buttonStyle(.plain)
            .opacity(isActive || isHovered ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isActive)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject private var ghostty: Ghostty.App
    @StateObject private var viewModel = AppViewModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isSearchExpanded: Bool = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ExplorerView(rootPath: viewModel.explorerRootPath) { path in
                viewModel.openFile(path: path)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 400)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            // Pure content area — tab bar lives in the toolbar above
            ZStack {
                if viewModel.tabs.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "terminal")
                            .font(.system(size: 48))
                            .foregroundColor(AppTheme.textMuted)
                        Text("Bunnyshell AI Terminal")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppTheme.text)
                        Text("Open a file in the sidebar or start a new terminal session.")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textMuted)
                        Button("Launch Shell") {
                            viewModel.spawnTerminal(cwd: viewModel.explorerRootPath)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.bg)
                } else {
                    // Keep all tab views alive, show/hide via opacity
                    ForEach(viewModel.tabs) { tab in
                        Group {
                            switch tab.kind {
                            case .terminal:
                                if let session = viewModel.terminalSessions[tab.id] {
                                    TerminalView(session: session)
                                }
                            case .editor:
                                if let textBinding = viewModel.bindingForFile(id: tab.id) {
                                    EditorView(path: tab.path ?? "", text: textBinding)
                                }
                            }
                        }
                        .opacity(viewModel.activeTabId == tab.id ? 1 : 0)
                        .disabled(viewModel.activeTabId != tab.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .background(AppTheme.bg)
        }
        .background(AppTheme.bg)
        .toolbar {
            // ── All hidden keyboard shortcuts in ONE ToolbarItem ─────────
            ToolbarItem(placement: .navigation) {
                ZStack {
                    // ⌘⇧B — toggle sidebar
                    Button(action: {
                        withAnimation {
                            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                        }
                    }) { EmptyView() }
                    .keyboardShortcut("b", modifiers: [.command, .shift])

                    // ⌘T — new terminal
                    Button(action: { viewModel.spawnTerminal(cwd: viewModel.explorerRootPath) }) { EmptyView() }
                        .keyboardShortcut("t", modifiers: .command)

                    // ⌘W — close current tab
                    Button(action: { viewModel.closeActiveTab() }) { EmptyView() }
                        .keyboardShortcut("w", modifiers: .command)

                    // ⌘⇧F — toggle search
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isSearchExpanded.toggle()
                        }
                    }) { EmptyView() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])

                    // ⌃Tab — next tab
                    Button(action: { viewModel.selectNextTab() }) { EmptyView() }
                        .keyboardShortcut(KeyEquivalent("\t"), modifiers: .control)

                    // ⌃⇧Tab — previous tab
                    Button(action: { viewModel.selectPreviousTab() }) { EmptyView() }
                        .keyboardShortcut(KeyEquivalent("\t"), modifiers: [.control, .shift])

                    // ⌘1–⌘9 — jump to tab by index
                    Button(action: { viewModel.selectTab(at: 0) }) { EmptyView() }
                        .keyboardShortcut("1", modifiers: .command)
                    Button(action: { viewModel.selectTab(at: 1) }) { EmptyView() }
                        .keyboardShortcut("2", modifiers: .command)
                    Button(action: { viewModel.selectTab(at: 2) }) { EmptyView() }
                        .keyboardShortcut("3", modifiers: .command)
                    Button(action: { viewModel.selectTab(at: 3) }) { EmptyView() }
                        .keyboardShortcut("4", modifiers: .command)
                    Button(action: { viewModel.selectTab(at: 4) }) { EmptyView() }
                        .keyboardShortcut("5", modifiers: .command)
                    Button(action: { viewModel.selectTab(at: 5) }) { EmptyView() }
                        .keyboardShortcut("6", modifiers: .command)
                    Button(action: { viewModel.selectTab(at: 6) }) { EmptyView() }
                        .keyboardShortcut("7", modifiers: .command)
                    Button(action: { viewModel.selectTab(at: 7) }) { EmptyView() }
                        .keyboardShortcut("8", modifiers: .command)
                    Button(action: { viewModel.selectTab(at: 8) }) { EmptyView() }
                        .keyboardShortcut("9", modifiers: .command)
                }
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
            }

            // ── Safari-style compact tab strip ───────────────────────────
            ToolbarItem(placement: .principal) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(viewModel.tabs) { tab in
                            TabPill(
                                tab: tab,
                                isActive: viewModel.activeTabId == tab.id,
                                onSelect: { viewModel.activeTabId = tab.id },
                                onClose: { viewModel.closeTab(id: tab.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: 560)
            }

            // ── Search bubble — collapsed by default, Cmd+Shift+F to expand ──
            ToolbarItem(placement: .primaryAction) {
                SearchBubbleView(
                    rootPath: viewModel.explorerRootPath,
                    onOpenFile: { path in viewModel.openFile(path: path) },
                    isExpanded: $isSearchExpanded
                )
            }
        }
        .toolbar(removing: .sidebarToggle)
        .onAppear {
            viewModel.setGhostty(ghostty)
            if let savedJson = try? loadWorkspaceState(), savedJson != "{}" {
                viewModel.deserializeState(savedJson)
            } else {
                viewModel.spawnTerminal(cwd: viewModel.explorerRootPath)
            }
        }
    }
}
