import type { GitHistoryTab, Tab } from "@/modules/tabs";
import { GitHistoryPane, type GitHistorySearchHandle } from "./GitHistoryPane";
import { PaneTreeView } from "@/components/PaneTreeView";

type CommitFileDiffOpenInput = {
  repoRoot: string;
  sha: string;
  shortSha: string;
  subject: string;
  path: string;
  originalPath: string | null;
};

type Props = {
  tabs: Tab[];
  activeId: number;
  onOpenCommitFile: (input: CommitFileDiffOpenInput) => void;
  onSearchHandle?: (handle: GitHistorySearchHandle | null) => void;
  onFocusLeaf: (tabId: number, leafId: number) => void;
};

export function GitHistoryStack({
  tabs,
  activeId,
  onOpenCommitFile,
  onSearchHandle,
  onFocusLeaf,
}: Props) {
  const histories = tabs.filter((t): t is GitHistoryTab => t.kind === "git-history");
  if (histories.length === 0) return null;
  return (
    <div className="relative h-full w-full">
      {histories.map((t) => {
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
              renderLeaf={(leafId) => (
                <GitHistoryPane
                  key={leafId}
                  repoRoot={t.repoRoot}
                  onOpenCommitFile={onOpenCommitFile}
                  onSearchHandle={onSearchHandle}
                />
              )}
            />
          </div>
        );
      })}
    </div>
  );
}
