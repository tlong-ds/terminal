import { cn } from "@/lib/utils";
import type { MarkdownTab, Tab } from "@/modules/tabs";
import { MarkdownPreviewPane } from "./MarkdownPreviewPane";
import { PaneTreeView } from "@/components/PaneTreeView";
import { useEffect, useRef } from "react";
import type { EditorPaneHandle } from "@/modules/editor/EditorPane";
import { leafIds } from "@/modules/terminal/lib/panes";

type Props = {
  tabs: Tab[];
  activeId: number;
  registerHandle: (id: number, handle: EditorPaneHandle | null) => void;
  onDirtyChange: (id: number, dirty: boolean) => void;
  onFocusLeaf: (tabId: number, leafId: number) => void;
};

export function MarkdownStack({
  tabs,
  activeId,
  registerHandle,
  onDirtyChange,
  onFocusLeaf,
}: Props) {
  const markdowns = tabs.filter((t): t is MarkdownTab => t.kind === "markdown");

  const registerRef = useRef(registerHandle);
  const dirtyRef = useRef(onDirtyChange);
  useEffect(() => {
    registerRef.current = registerHandle;
  }, [registerHandle]);
  useEffect(() => {
    dirtyRef.current = onDirtyChange;
  }, [onDirtyChange]);

  const refCallbacks = useRef(
    new Map<number, (h: EditorPaneHandle | null) => void>(),
  );
  const dirtyCallbacks = useRef(new Map<number, (dirty: boolean) => void>());

  const getRefCallback = (id: number) => {
    let cb = refCallbacks.current.get(id);
    if (!cb) {
      cb = (h: EditorPaneHandle | null) => registerRef.current(id, h);
      refCallbacks.current.set(id, cb);
    }
    return cb;
  };
  const getDirtyCallback = (id: number) => {
    let cb = dirtyCallbacks.current.get(id);
    if (!cb) {
      cb = (dirty: boolean) => dirtyRef.current(id, dirty);
      dirtyCallbacks.current.set(id, cb);
    }
    return cb;
  };

  // Drop callback entries for closed panes to avoid unbounded growth.
  useEffect(() => {
    const live = new Set<number>();
    for (const t of markdowns) {
      for (const id of leafIds(t.paneTree)) live.add(id);
    }
    for (const id of refCallbacks.current.keys()) {
      if (!live.has(id)) refCallbacks.current.delete(id);
    }
    for (const id of dirtyCallbacks.current.keys()) {
      if (!live.has(id)) dirtyCallbacks.current.delete(id);
    }
  }, [markdowns]);

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
              renderLeaf={(leafId, focused) => (
                <MarkdownPreviewPane
                  ref={getRefCallback(leafId)}
                  path={t.path}
                  visible={visible && focused}
                  onDirtyChange={getDirtyCallback(leafId)}
                />
              )}
            />
          </div>
        );
      })}
    </div>
  );
}
