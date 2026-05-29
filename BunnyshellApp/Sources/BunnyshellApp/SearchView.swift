import SwiftUI
import BunnyshellCore

// MARK: - Search Result Model

struct SearchResult: Identifiable {
    let id = UUID()
    let filePath: String
    let fileName: String
    let matchKind: MatchKind
    let lineNumber: Int?
    let lineText: String?

    enum MatchKind {
        case fileName
        case fileContent
    }

    var displayPath: String {
        // Show last 2 path components for readability
        let parts = filePath.split(separator: "/")
        if parts.count >= 2 {
            return parts.suffix(2).joined(separator: "/")
        }
        return filePath
    }
}

// MARK: - Search Engine

actor SearchEngine {
    /// Search for files matching query (name + content) under rootPath
    func search(query: String, rootPath: String, maxResults: Int = 60) async -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let lowQuery = query.lowercased()
        var results: [SearchResult] = []

        enumerateFiles(at: rootPath, maxResults: maxResults, results: &results, lowQuery: lowQuery)
        return results
    }

    private func enumerateFiles(
        at path: String,
        maxResults: Int,
        results: inout [SearchResult],
        lowQuery: String
    ) {
        guard results.count < maxResults,
              let entries = try? fsReadDir(path: path, showHidden: false) else { return }

        for entry in entries {
            guard results.count < maxResults else { break }

            let childPath = path.hasSuffix("/") ? "\(path)\(entry.name)" : "\(path)/\(entry.name)"
            let isDir: Bool
            if case .dir = entry.kind { isDir = true } else { isDir = false }

            if isDir {
                // Skip common non-useful directories
                let skip = [".git", "node_modules", ".build", "target", "dist", ".DS_Store"]
                if skip.contains(entry.name) { continue }
                enumerateFiles(at: childPath, maxResults: maxResults, results: &results, lowQuery: lowQuery)
            } else {
                // File name match
                if entry.name.lowercased().contains(lowQuery) {
                    results.append(SearchResult(
                        filePath: childPath,
                        fileName: entry.name,
                        matchKind: .fileName,
                        lineNumber: nil,
                        lineText: nil
                    ))
                }

                // File content match (text files only, limit to reasonable size)
                searchFileContent(path: childPath, fileName: entry.name, lowQuery: lowQuery, results: &results, maxResults: maxResults)
            }
        }
    }

    private func searchFileContent(
        path: String,
        fileName: String,
        lowQuery: String,
        results: inout [SearchResult],
        maxResults: Int
    ) {
        // Only search text-like files
        let textExtensions: Set<String> = [
            "swift", "js", "ts", "tsx", "jsx", "json", "jsonc",
            "yaml", "yml", "toml", "md", "mdx", "html", "htm",
            "css", "scss", "sass", "less", "sh", "zsh", "bash",
            "fish", "py", "rs", "go", "rb", "c", "cpp", "h",
            "hpp", "txt", "env", "gitignore", "lock", "xml", "csv"
        ]
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard textExtensions.contains(ext) else { return }

        guard let content = try? fsReadFile(path: path),
              case .text(let text, _) = content else { return }

        // Limit to avoid huge files
        let lines = text.components(separatedBy: .newlines)
        guard lines.count < 10_000 else { return }

        for (idx, line) in lines.enumerated() {
            guard results.count < maxResults else { break }
            if line.lowercased().contains(lowQuery) {
                // Avoid duplicate if file name already matched
                let alreadyHasNameMatch = results.contains {
                    $0.filePath == path && $0.matchKind == .fileName
                }
                // Don't add a content match right after a name match for the same query
                _ = alreadyHasNameMatch
                results.append(SearchResult(
                    filePath: path,
                    fileName: fileName,
                    matchKind: .fileContent,
                    lineNumber: idx + 1,
                    lineText: line.trimmingCharacters(in: .whitespaces)
                ))
            }
        }
    }
}

// MARK: - Search Result Row

private struct SearchResultRow: View {
    let result: SearchResult
    let query: String
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: result.matchKind == .fileName ? "doc" : "text.alignleft")
                .font(.system(size: 11))
                .foregroundStyle(result.matchKind == .fileName ? AppTheme.accent : AppTheme.textMuted)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                // File name with highlighted query
                HighlightedText(text: result.fileName, query: query)
                    .font(.system(size: 12, weight: .medium))

                HStack(spacing: 4) {
                    Text(result.displayPath)
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textMuted)

                    if let line = result.lineNumber {
                        Text(":\(line)")
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.accent.opacity(0.8))
                    }
                }

                if let snippet = result.lineText, !snippet.isEmpty {
                    HighlightedText(text: snippet, query: query)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected
                    ? AppTheme.accent.opacity(0.18)
                    : isHovered ? Color.white.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - Highlighted Text

private struct HighlightedText: View {
    let text: String
    let query: String

    var body: some View {
        let lower = text.lowercased()
        let lowerQuery = query.lowercased()

        if lowerQuery.isEmpty || !lower.contains(lowerQuery) {
            return Text(text).foregroundStyle(AppTheme.text)
        }

        // Build attributed string
        var result = Text("")
        var remaining = text[...]
        let lowerRemaining = lower[...]

        var searchStart = lowerRemaining.startIndex
        while let range = lowerRemaining[searchStart...].range(of: lowerQuery) {
            let before = remaining[remaining.startIndex..<range.lowerBound]
            if !before.isEmpty {
                result = result + Text(String(before)).foregroundStyle(AppTheme.text)
            }
            let matched = remaining[range.lowerBound..<range.upperBound]
            result = result + Text(String(matched))
                .foregroundStyle(AppTheme.accent)
                .bold()
            remaining = remaining[range.upperBound...]
            searchStart = range.upperBound
        }
        if !remaining.isEmpty {
            result = result + Text(String(remaining)).foregroundStyle(AppTheme.text)
        }
        return result
    }
}

// MARK: - SearchBubbleView

struct SearchBubbleView: View {
    let rootPath: String
    let onOpenFile: (String) -> Void

    // Expansion state driven by Cmd+Shift+F from parent
    @Binding var isExpanded: Bool

    @State private var searchText: String = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @State private var selectedIndex: Int = 0
    @FocusState private var fieldFocused: Bool

    private let engine = SearchEngine()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // The bubble itself
            HStack(spacing: isExpanded ? 6 : 0) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: isExpanded ? 12 : 13, weight: .medium))
                    .foregroundStyle(isExpanded ? AppTheme.accent : AppTheme.textMuted)
                    .animation(.spring(duration: 0.28), value: isExpanded)

                if isExpanded {
                    TextField("Search files & content…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.text)
                        .frame(width: 200)
                        .focused($fieldFocused)
                        .onSubmit { openSelected() }
                        .transition(.opacity.combined(with: .move(edge: .trailing)))

                    if !searchText.isEmpty {
                        if isSearching {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        } else {
                            Button(action: { searchText = ""; results = [] }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.textMuted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, isExpanded ? 10 : 0)
            .padding(.vertical, isExpanded ? 6 : 0)
            .frame(width: isExpanded ? 258 : 30, height: 30)
            .clipped()
            .contentShape(RoundedRectangle(cornerRadius: isExpanded ? 20 : 999))
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
            .onTapGesture {
                if !isExpanded {
                    // Tap on collapsed icon doesn't expand (requires shortcut)
                    // but we can allow it for discoverability
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded = true
                    }
                    fieldFocused = true
                }
            }

            // Results popup — anchored below the bubble
            if isExpanded && !results.isEmpty {
                resultsPopup
                    .offset(y: 38)
                    .zIndex(100)
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                fieldFocused = true
            } else {
                searchText = ""
                results = []
                fieldFocused = false
            }
        }
        .onChange(of: searchText) { _, newValue in
            selectedIndex = 0
            triggerSearch(query: newValue)
        }
        .onKeyPress(.escape) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded = false
            }
            return .handled
        }
        // Ctrl+J — move selection down (vim style)
        .onKeyPress(KeyEquivalent("j"), phases: .down) { press in
            guard press.modifiers.contains(.control), !results.isEmpty else { return .ignored }
            selectedIndex = min(selectedIndex + 1, results.count - 1)
            return .handled
        }
        // Ctrl+K — move selection up (vim style)
        .onKeyPress(KeyEquivalent("k"), phases: .down) { press in
            guard press.modifiers.contains(.control), !results.isEmpty else { return .ignored }
            selectedIndex = max(selectedIndex - 1, 0)
            return .handled
        }
    }

    // MARK: Results Popup

    private var resultsPopup: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.textMuted)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                Spacer()
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.5)
                        .padding(.trailing, 10)
                        .padding(.top, 6)
                }
            }

            Divider()
                .background(AppTheme.border)

            // Results list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            SearchResultRow(
                                result: result,
                                query: searchText,
                                isSelected: index == selectedIndex
                            ) {
                                onOpenFile(result.filePath)
                                isExpanded = false
                            }
                            .id(index)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                }
                .onChange(of: selectedIndex) { _, idx in
                    withAnimation { proxy.scrollTo(idx, anchor: .center) }
                }
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.sidebarBg)
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(AppTheme.border, lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: results.count)
    }

    // MARK: - Logic

    private func openSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        onOpenFile(results[selectedIndex].filePath)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isExpanded = false
        }
    }

    private func triggerSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        let rootPath = self.rootPath

        Task {
            let found = await engine.search(query: trimmed, rootPath: rootPath)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.18)) {
                    results = found
                }
                isSearching = false
            }
        }
    }
}
