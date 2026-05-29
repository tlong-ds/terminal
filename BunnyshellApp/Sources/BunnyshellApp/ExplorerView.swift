import SwiftUI
import BunnyshellCore

// MARK: - Model

private struct FileSystemItem: Identifiable {
    let id: String   // absolute path
    let name: String
    let isDirectory: Bool

    var systemImage: String {
        if isDirectory { return "folder.fill" }
        switch (name as NSString).pathExtension.lowercased() {
        case "swift":                          return "swift"
        case "js", "mjs", "cjs":              return "doc.text"
        case "ts", "tsx":                      return "doc.text"
        case "jsx":                            return "doc.text"
        case "json", "jsonc":                  return "curlybraces"
        case "yaml", "yml":                    return "list.bullet.indent"
        case "toml":                           return "gearshape"
        case "md", "mdx":                      return "doc.richtext"
        case "png", "jpg", "jpeg",
             "gif", "svg", "webp", "ico":      return "photo"
        case "html", "htm":                    return "globe"
        case "css", "scss", "sass", "less":    return "paintbrush.pointed"
        case "sh", "zsh", "bash", "fish":      return "terminal"
        case "py":                             return "doc.text"
        case "rs":                             return "doc.text"
        case "go":                             return "doc.text"
        case "rb":                             return "doc.text"
        case "c", "cpp", "h", "hpp":           return "doc.text"
        case "lock":                           return "lock.doc"
        case "env":                            return "key"
        case "gitignore", "gitattributes":     return "arrow.triangle.branch"
        default:                               return "doc"
        }
    }

    var iconColor: Color {
        if isDirectory { return AppTheme.accent }
        switch (name as NSString).pathExtension.lowercased() {
        case "swift":                return .orange
        case "js", "mjs", "cjs":    return Color(hex: "F0DB4F")
        case "ts", "tsx":            return Color(hex: "3178C6")
        case "json", "jsonc":        return .gray
        case "yaml", "yml", "toml": return Color(hex: "CB171E")
        case "md", "mdx":           return .secondary
        case "html", "htm":         return Color(hex: "E44D26")
        case "css", "scss", "sass": return Color(hex: "264DE4")
        case "sh", "zsh", "bash":   return .green
        case "py":                  return Color(hex: "3572A5")
        case "rs":                  return Color(hex: "DEA584")
        case "go":                  return Color(hex: "00ADD8")
        case "rb":                  return Color(hex: "701516")
        case "png", "jpg", "jpeg",
             "gif", "svg", "webp":  return .purple
        default:                    return AppTheme.textMuted
        }
    }
}

// MARK: - Helpers

private func loadDirContents(path: String) -> [FileSystemItem] {
    guard let entries = try? fsReadDir(path: path, showHidden: false) else { return [] }
    let items: [FileSystemItem] = entries.map { entry in
        let childPath = path.hasSuffix("/") ? "\(path)\(entry.name)" : "\(path)/\(entry.name)"
        let isDir: Bool
        if case .dir = entry.kind { isDir = true } else { isDir = false }
        return FileSystemItem(id: childPath, name: entry.name, isDirectory: isDir)
    }
    return items.sorted {
        if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
}

private func pathBasename(_ path: String) -> String {
    (path as NSString).lastPathComponent
}

private enum SidebarSection {
    case files
    case sourceControl
}

private func runGit(_ arguments: [String], rootPath: String) throws -> (status: Int32, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "-C", rootPath] + arguments

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
    let stderr = String(data: stderrData, encoding: .utf8) ?? ""
    return (status: process.terminationStatus, stdout: stdout, stderr: stderr)
}

private func isGitRepository(path: String) -> Bool {
    guard let result = try? runGit(["rev-parse", "--is-inside-work-tree"], rootPath: path) else { return false }
    return result.status == 0 && result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
}

private struct GitLogEntry: Identifiable {
    var id: String { sha }

    let sha: String
    let shortSha: String
    let author: String
    let authorEmail: String
    let timestampSecs: Int
    let parents: [String]
    let subject: String
}

private struct GitBranchTracking {
    let branch: String
    let upstream: String?
    let ahead: Int
    let behind: Int
    let isDetached: Bool
}

private enum GraphEdge {
    case straight(lane: Int, color: Color)
    case merge(fromLane: Int, toLane: Int, color: Color)
    case branch(fromLane: Int, toLane: Int, color: Color)
}

private struct GraphRow {
    let sha: String
    let lane: Int
    let nodeColor: Color
    let laneCount: Int
    let topEdges: [GraphEdge]
    let bottomEdges: [GraphEdge]
}

private struct GraphState {
    var lanes: [String?] = []
}

private let graphLaneColors: [Color] = [
    Color(hex: "60A5FA"),
    Color(hex: "C084FC"),
    Color(hex: "34D399"),
    Color(hex: "FBBF24"),
    Color(hex: "F472B6"),
    Color(hex: "22D3EE"),
    Color(hex: "FB923C"),
    Color(hex: "A3E635"),
]

private let graphLaneWidth: CGFloat = 14
private let graphRailPaddingX: CGFloat = 8
private let graphMaxVisibleLanes = 6
private let graphStrokeWidth: CGFloat = 1.5

private func graphLaneColor(_ index: Int) -> Color {
    graphLaneColors[abs(index) % graphLaneColors.count]
}

private func graphLaneX(_ lane: Int) -> CGFloat {
    graphRailPaddingX + CGFloat(lane) * graphLaneWidth
}

private func graphRailWidth(maxLane: Int) -> CGFloat {
    let visible = min(maxLane, graphMaxVisibleLanes)
    return graphRailPaddingX * 2 + CGFloat(max(0, visible - 1)) * graphLaneWidth + 6
}

private func trimTrailing(_ lanes: [String?]) -> [String?] {
    var end = lanes.count
    while end > 0, lanes[end - 1] == nil {
        end -= 1
    }
    return Array(lanes.prefix(end))
}

private func firstFreeSlot(_ lanes: [String?]) -> Int {
    for index in lanes.indices where lanes[index] == nil {
        return index
    }
    return lanes.count
}

private func layoutGraph(commits: [GitLogEntry], previous: GraphState = GraphState()) -> (rows: [GraphRow], state: GraphState) {
    var lanes = previous.lanes
    var rows: [GraphRow] = []

    for commit in commits {
        let claiming = lanes.enumerated().compactMap { index, value in
            value == commit.sha ? index : nil
        }

        let lane = claiming.first ?? firstFreeSlot(lanes)
        if lane == lanes.count {
            lanes.append(nil)
        }

        let lanesBefore = lanes
        var topEdges: [GraphEdge] = []

        for index in lanesBefore.indices {
            guard let value = lanesBefore[index] else { continue }
            if value == commit.sha && index != lane {
                topEdges.append(.merge(fromLane: index, toLane: lane, color: graphLaneColor(index)))
            } else {
                topEdges.append(.straight(lane: index, color: graphLaneColor(index)))
            }
        }

        for index in claiming {
            lanes[index] = nil
        }
        if claiming.isEmpty {
            lanes[lane] = nil
        }

        var bottomEdges: [GraphEdge] = []
        if let firstParent = commit.parents.first {
            lanes[lane] = firstParent
            for parent in commit.parents.dropFirst() {
                var parentLane = lanes.firstIndex(of: parent) ?? -1
                if parentLane == -1 {
                    parentLane = firstFreeSlot(lanes)
                    if parentLane == lanes.count {
                        lanes.append(nil)
                    }
                    lanes[parentLane] = parent
                }
                if parentLane != lane {
                    bottomEdges.append(.branch(fromLane: lane, toLane: parentLane, color: graphLaneColor(parentLane)))
                }
            }
        }

        let branchTargets = Set(
            bottomEdges.compactMap {
                if case let .branch(_, toLane, _) = $0 { return toLane }
                return nil
            }
        )

        for index in lanes.indices {
            guard lanes[index] != nil else { continue }
            if branchTargets.contains(index) { continue }
            bottomEdges.append(.straight(lane: index, color: graphLaneColor(index)))
        }

        let trimmed = trimTrailing(lanes)
        if trimmed.count != lanes.count {
            lanes = trimmed
        }

        let widestLane = max(lanesBefore.count, lanes.count, lane + 1)
        rows.append(
            GraphRow(
                sha: commit.sha,
                lane: lane,
                nodeColor: graphLaneColor(lane),
                laneCount: widestLane,
                topEdges: topEdges,
                bottomEdges: bottomEdges
            )
        )

    }

    return (rows, GraphState(lanes: lanes))
}

private func compactDate(_ secs: Int) -> String {
    guard secs > 0 else { return "" }
    let date = Date(timeIntervalSince1970: TimeInterval(secs))
    let calendar = Calendar.current
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        ? "MMM d  HH:mm"
        : "MMM d yyyy"
    return formatter.string(from: date)
}

private func parseGitLogEntry(from line: String) -> GitLogEntry? {
    guard line.contains("\u{1f}") else { return nil }
    let fields = line.split(separator: "\u{1f}", omittingEmptySubsequences: false)
    guard fields.count >= 7 else { return nil }
    return GitLogEntry(
        sha: String(fields[0]),
        shortSha: String(fields[1]),
        author: String(fields[2]),
        authorEmail: String(fields[3]),
        timestampSecs: Int(String(fields[4])) ?? 0,
        parents: String(fields[5]).split(whereSeparator: \.isWhitespace).map(String.init),
        subject: String(fields[6])
    )
}

private func loadGitBranchTracking(path: String) -> GitBranchTracking {
    let branchResult = try? runGit(["rev-parse", "--abbrev-ref", "HEAD"], rootPath: path)
    let branch = branchResult?.status == 0
        ? branchResult?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? "detached"
        : "detached"
    let isDetached = branch == "HEAD" || branch == "detached"

    let upstreamResult = try? runGit(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], rootPath: path)
    let upstream = upstreamResult?.status == 0
        ? upstreamResult?.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        : nil

    var ahead = 0
    var behind = 0
    if let upstream, !upstream.isEmpty, let result = try? runGit(["rev-list", "--left-right", "--count", "\(branch)...\(upstream)"], rootPath: path),
       result.status == 0 {
        let parts = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t")
        if parts.count >= 2 {
            ahead = Int(parts[0]) ?? 0
            behind = Int(parts[1]) ?? 0
        } else {
            let whitespaceParts = result.stdout.split(whereSeparator: \.isWhitespace)
            if whitespaceParts.count >= 2 {
                ahead = Int(whitespaceParts[0]) ?? 0
                behind = Int(whitespaceParts[1]) ?? 0
            }
        }
    }

    return GitBranchTracking(
        branch: branch.isEmpty ? "detached" : branch,
        upstream: upstream,
        ahead: ahead,
        behind: behind,
        isDetached: isDetached
    )
}

private func loadGitGraph(path: String, limit: Int = 120) throws -> (tracking: GitBranchTracking, commits: [GitLogEntry]) {
    guard isGitRepository(path: path) else {
        throw NSError(
            domain: "SourceControl",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Current path is not inside a Git repository."]
        )
    }

    let format = "--pretty=format:%H%x1f%h%x1f%an%x1f%ae%x1f%ct%x1f%P%x1f%s"
    let graphResult = try runGit(
        ["log", "--no-color", "--shortstat", "--date=relative", format, "-n", "\(limit)"],
        rootPath: path
    )

    if graphResult.status != 0 {
        let message = graphResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        throw NSError(
            domain: "SourceControl",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? "Failed to load commit graph." : message]
        )
    }

    let commits = graphResult.stdout
        .split(whereSeparator: \.isNewline)
        .compactMap { parseGitLogEntry(from: String($0)) }

    return (tracking: loadGitBranchTracking(path: path), commits: commits)
}

private struct SourceControlGraphRail: View {
    let row: GraphRow
    let rowHeight: CGFloat
    let maxLaneCount: Int
    var active: Bool = false

    @ViewBuilder
    private func renderTopEdge(_ edge: GraphEdge, midY: CGFloat) -> some View {
        switch edge {
        case let .straight(lane, color):
            let x = graphLaneX(lane)
            Path { path in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: midY))
            }
            .stroke(color, style: StrokeStyle(lineWidth: graphStrokeWidth, lineCap: .round))
        case let .merge(fromLane, toLane, color):
            let xFrom = graphLaneX(fromLane)
            let xTo = graphLaneX(toLane)
            let controlY = midY * 0.55
            Path { path in
                path.move(to: CGPoint(x: xFrom, y: 0))
                path.addCurve(
                    to: CGPoint(x: xTo, y: midY),
                    control1: CGPoint(x: xFrom, y: controlY),
                    control2: CGPoint(x: xTo, y: controlY)
                )
            }
            .stroke(color, style: StrokeStyle(lineWidth: graphStrokeWidth, lineCap: .round))
        case .branch:
            EmptyView()
        }
    }

    @ViewBuilder
    private func renderBottomEdge(_ edge: GraphEdge, midY: CGFloat, bottomY: CGFloat) -> some View {
        switch edge {
        case let .straight(lane, color):
            let x = graphLaneX(lane)
            Path { path in
                path.move(to: CGPoint(x: x, y: midY))
                path.addLine(to: CGPoint(x: x, y: bottomY))
            }
            .stroke(color, style: StrokeStyle(lineWidth: graphStrokeWidth, lineCap: .round))
        case let .branch(fromLane, toLane, color):
            let xFrom = graphLaneX(fromLane)
            let xTo = graphLaneX(toLane)
            let controlY = midY + (bottomY - midY) * 0.45
            Path { path in
                path.move(to: CGPoint(x: xFrom, y: midY))
                path.addCurve(
                    to: CGPoint(x: xTo, y: bottomY),
                    control1: CGPoint(x: xFrom, y: controlY),
                    control2: CGPoint(x: xTo, y: controlY)
                )
            }
            .stroke(color, style: StrokeStyle(lineWidth: graphStrokeWidth, lineCap: .round))
        case .merge:
            EmptyView()
        }
    }

    var body: some View {
        let width = graphRailWidth(maxLane: maxLaneCount)
        let midY = round(rowHeight / 2)
        let nodeX = graphLaneX(row.lane)
        let visible = min(maxLaneCount, graphMaxVisibleLanes)
        let overflow = row.laneCount > visible

        return ZStack(alignment: .trailing) {
            ZStack {
                ForEach(Array(row.topEdges.enumerated()), id: \.offset) { _, edge in
                    renderTopEdge(edge, midY: midY)
                }
                ForEach(Array(row.bottomEdges.enumerated()), id: \.offset) { _, edge in
                    renderBottomEdge(edge, midY: midY, bottomY: rowHeight)
                }

                Circle()
                    .fill(row.nodeColor)
                    .frame(width: active ? 9.2 : 7.2, height: active ? 9.2 : 7.2)
                    .overlay(
                        Circle()
                            .stroke(AppTheme.sidebarBg, lineWidth: 1.5)
                    )
                    .shadow(color: row.nodeColor.opacity(active ? 0.35 : 0.18), radius: active ? 4 : 2)
                    .position(x: nodeX, y: midY)

                if active {
                    Circle()
                        .stroke(row.nodeColor.opacity(0.35), lineWidth: 1.2)
                        .frame(width: 13, height: 13)
                        .position(x: nodeX, y: midY)
                }
            }
            .frame(width: width, height: rowHeight, alignment: .leading)

            if overflow {
                Text("+\(row.laneCount - visible)")
                    .font(.system(size: 8))
                    .foregroundColor(AppTheme.textMuted)
                    .padding(.trailing, 4)
            }
        }
        .frame(width: width, height: rowHeight, alignment: .leading)
        .accessibilityHidden(true)
    }
}

private struct SourceControlCommitRow: View {
    let commit: GitLogEntry
    let graphRow: GraphRow
    let maxLaneCount: Int
    let isActive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            SourceControlGraphRail(row: graphRow, rowHeight: 34, maxLaneCount: maxLaneCount, active: isActive)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(commit.shortSha)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(AppTheme.textMuted)

                    Text(commit.subject.isEmpty ? "(no subject)" : commit.subject)
                        .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                        .foregroundColor(AppTheme.text)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(commit.author.isEmpty ? "Unknown" : commit.author)
                    Text("•")
                    Text(commit.timestampSecs > 0 ? compactDate(commit.timestampSecs) : "")
                }
                .font(.system(size: 10.5))
                .foregroundColor(AppTheme.textMuted)
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isActive ? AppTheme.accent.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
    }
}

private struct SourceControlGraphView: View {
    let rootPath: String
    @State private var isLoading = false
    @State private var error: String?
    @State private var tracking = GitBranchTracking(branch: "-", upstream: nil, ahead: 0, behind: 0, isDetached: false)
    @State private var commits: [GitLogEntry] = []
    @State private var maxLaneCount = 1

    private func reload() {
        isLoading = true
        error = nil
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let snapshot = try loadGitGraph(path: rootPath)
                let layout = layoutGraph(commits: snapshot.commits)
                DispatchQueue.main.async {
                    self.tracking = snapshot.tracking
                    self.commits = snapshot.commits
                    self.maxLaneCount = max(1, layout.rows.map(\.laneCount).max() ?? 1)
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.tracking = GitBranchTracking(branch: "-", upstream: nil, ahead: 0, behind: 0, isDetached: false)
                    self.commits = []
                    self.maxLaneCount = 1
                    self.isLoading = false
                    self.error = error.localizedDescription
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("Commit Graph", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.text)
                Spacer()
                if tracking.ahead > 0 || tracking.behind > 0 {
                    HStack(spacing: 4) {
                        if tracking.ahead > 0 {
                            StatusChip(
                                symbol: "arrow.up",
                                label: "\(tracking.ahead)"
                            )
                        }
                        if tracking.behind > 0 {
                            StatusChip(
                                symbol: "arrow.down",
                                label: "\(tracking.behind)"
                            )
                        }
                    }
                }
                if let upstream = tracking.upstream, !upstream.isEmpty {
                    StatusChip(
                        symbol: "arrow.triangle.branch",
                        label: upstream
                    )
                } else if !tracking.isDetached {
                    StatusChip(
                        symbol: "arrow.triangle.branch",
                        label: "No upstream"
                    )
                }
                if tracking.isDetached {
                    Text("detached")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AppTheme.border.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Text(tracking.branch)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(AppTheme.textMuted)
                }
                Button(action: reload) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(AppTheme.textMuted)
                .help("Refresh Commit Graph")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().background(AppTheme.border)

            Group {
                if isLoading {
                    ProgressView("Loading commits...")
                        .font(.system(size: 12))
                        .tint(AppTheme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    VStack(spacing: 8) {
                        Text("Source Control unavailable")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.text)
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 14)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if commits.isEmpty {
                    Text("No commits yet")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let graphRows = layoutGraph(commits: commits).rows
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(commits.enumerated()), id: \.element.id) { index, commit in
                                if index < graphRows.count {
                                    SourceControlCommitRow(
                                        commit: commit,
                                        graphRow: graphRows[index],
                                        maxLaneCount: maxLaneCount,
                                        isActive: false
                                    )
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .background(AppTheme.sidebarBg)
        }
        .onAppear(perform: reload)
        .onChange(of: rootPath) { _, _ in reload()
        }
    }
}

private struct StatusChip: View {
    let symbol: String
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .semibold))
            Text(label)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(AppTheme.textMuted)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }
}

// MARK: - Recursive Row

private struct FileTreeRow: View {
    let item: FileSystemItem
    let onOpenFile: (String) -> Void

    @State private var isExpanded = false
    @State private var children: [FileSystemItem] = []
    @State private var childrenLoaded = false

    var body: some View {
        if item.isDirectory {
            DisclosureGroup(isExpanded: $isExpanded) {
                if childrenLoaded {
                    if children.isEmpty {
                        Text("Empty folder")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textMuted)
                            .padding(.leading, 4)
                    } else {
                        ForEach(children) { child in
                            FileTreeRow(item: child, onOpenFile: onOpenFile)
                        }
                    }
                }
            } label: {
                Label {
                    Text(item.name)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.text)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: item.systemImage)
                        .foregroundColor(item.iconColor)
                        .font(.system(size: 12))
                }
            }
            .onChange(of: isExpanded) { _, expanded in
                guard expanded, !childrenLoaded else { return }
                childrenLoaded = true
                let path = item.id
                DispatchQueue.global(qos: .userInitiated).async {
                    let loaded = loadDirContents(path: path)
                    DispatchQueue.main.async { children = loaded }
                }
            }
        } else {
            Label {
                Text(item.name)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.text)
                    .lineLimit(1)
            } icon: {
                Image(systemName: item.systemImage)
                    .foregroundColor(item.iconColor)
                    .font(.system(size: 12))
            }
            .contentShape(Rectangle())
            .onTapGesture { onOpenFile(item.id) }
        }
    }
}

// MARK: - ExplorerView

struct ExplorerView: View {
    let rootPath: String
    let onOpenFile: (String) -> Void

    @State private var rootItems: [FileSystemItem] = []
    @State private var selectedSection: SidebarSection = .files
    @State private var isGitRepo = false

    private func refreshRepositoryState(for path: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let repo = isGitRepository(path: path)
            DispatchQueue.main.async {
                self.isGitRepo = repo
                if !repo && self.selectedSection == .sourceControl {
                    self.selectedSection = .files
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Workspace header
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.accent)

                Text(pathBasename(rootPath))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.text)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 8) {
                    Button(action: {}) {
                        Image(systemName: "doc.badge.plus")
                    }
                    .buttonStyle(.plain)
                    .help("New File")

                    Button(action: {}) {
                        Image(systemName: "folder.badge.plus")
                    }
                    .buttonStyle(.plain)
                    .help("New Folder")
                }
                .foregroundColor(AppTheme.textMuted)
                .font(.system(size: 11))
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider().background(AppTheme.border)

            // Native sidebar content
            if selectedSection == .files {
                List {
                    ForEach(rootItems) { item in
                        FileTreeRow(item: item, onOpenFile: onOpenFile)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(AppTheme.sidebarBg)
            } else {
                SourceControlGraphView(rootPath: rootPath)
            }

            Divider().background(AppTheme.border)

            // Bottom section tabs
            HStack(spacing: 0) {
                Button(action: { selectedSection = .files }) {
                    Label("Files", systemImage: "folder")
                        .font(.system(size: 11, weight: selectedSection == .files ? .semibold : .regular))
                }
                .buttonStyle(.plain)
                .foregroundColor(selectedSection == .files ? AppTheme.text : AppTheme.textMuted)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)

                Spacer()

                Button(action: { selectedSection = .sourceControl }) {
                    Label("Source Control", systemImage: "square.stack.3d.up")
                        .font(.system(size: 11, weight: selectedSection == .sourceControl ? .semibold : .regular))
                }
                .buttonStyle(.plain)
                .foregroundColor(isGitRepo ? AppTheme.text : AppTheme.textMuted)
                .disabled(!isGitRepo)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
            .background(AppTheme.sidebarBg)
        }
        .background(AppTheme.sidebarBg)
        .onAppear {
            if rootItems.isEmpty {
                rootItems = loadDirContents(path: rootPath)
            }
            refreshRepositoryState(for: rootPath)
        }
        .onChange(of: rootPath) { _, nextRoot in
            rootItems = loadDirContents(path: nextRoot)
            refreshRepositoryState(for: nextRoot)
        }
    }
}
