import type {
  GitCommitFileDiffTab,
  GitDiffTab,
  Tab,
} from "@/modules/tabs";
import { GitDiffPane } from "./GitDiffPane";
import { PaneTreeView } from "@/components/PaneTreeView";

type Props = {
  tabs: Tab[];
  activeId: number;
  onFocusLeaf: (tabId: number, leafId: number) => void;
};

export function GitDiffStack({ tabs, activeId, onFocusLeaf }: Props) {
  const diffs = tabs.filter(
    (t): t is GitDiffTab | GitCommitFileDiffTab =>
      t.kind === "git-diff" || t.kind === "git-commit-file",
  );
  if (diffs.length === 0) return null;
  return (
    <div className="relative h-full w-full">
      {diffs.map((t) => {
        const visible = t.id === activeId;
        return (
          <div
            key={t.id}
            className={
              visible ? "absolute inset-0" : "absolute inset-0 invisible pointer-events-none"
            }
            aria-hidden={!visible}
          >
            <PaneTreeView
              node={t.paneTree}
              activeLeafId={t.activeLeafId}
              onFocusLeaf={(leafId) => onFocusLeaf(t.id, leafId)}
              renderLeaf={(leafId, focused) => {
                if (t.kind === "git-diff") {
                  return (
                    <GitDiffPane
                      key={leafId}
                      active={visible && focused}
                      source={{
                        kind: "working",
                        repoRoot: t.repoRoot,
                        path: t.path,
                        mode: t.mode,
                        originalPath: t.originalPath,
                      }}
                    />
                  );
                }
                return (
                  <GitDiffPane
                    key={leafId}
                    active={visible && focused}
                    source={{
                      kind: "commit",
                      repoRoot: t.repoRoot,
                      sha: t.sha,
                      path: t.path,
                      originalPath: t.originalPath,
                    }}
                    chipLabel={t.shortSha}
                  />
                );
              }}
            />
          </div>
        );
      })}
    </div>
  );
}
