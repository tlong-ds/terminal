import { cn } from "@/lib/utils";
import type { MarkdownTab, Tab } from "@/modules/tabs";
import { MarkdownPreviewPane } from "./MarkdownPreviewPane";
import { PaneTreeView } from "@/components/PaneTreeView";

type Props = {
  tabs: Tab[];
  activeId: number;
  onFocusLeaf: (tabId: number, leafId: number) => void;
};

export function MarkdownStack({ tabs, activeId, onFocusLeaf }: Props) {
  const markdowns = tabs.filter((t): t is MarkdownTab => t.kind === "markdown");
  if (markdowns.length === 0) return null;
  return (
    <div className="relative h-full w-full">
      {markdowns.map((t) => {
        const visible = t.id === activeId;
        return (
          <div
            key={t.id}
            className={cn(
              "absolute inset-0",
              !visible && "invisible pointer-events-none",
            )}
            aria-hidden={!visible}
          >
            <PaneTreeView
              node={t.paneTree}
              activeLeafId={t.activeLeafId}
              onFocusLeaf={(leafId) => onFocusLeaf(t.id, leafId)}
              renderLeaf={(_leafId, focused) => (
                <MarkdownPreviewPane path={t.path} visible={visible && focused} />
              )}
            />
          </div>
        );
      })}
    </div>
  );
}
