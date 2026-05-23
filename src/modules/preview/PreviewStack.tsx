import { cn } from "@/lib/utils";
import type { PreviewTab, Tab } from "@/modules/tabs";
import { useEffect, useRef } from "react";
import { PreviewPane, type PreviewPaneHandle } from "./PreviewPane";
import { PaneTreeView } from "@/components/PaneTreeView";
import { leafIds } from "@/modules/terminal/lib/panes";

type Props = {
  tabs: Tab[];
  activeId: number;
  onUrlChange: (id: number, url: string) => void;
  registerHandle: (id: number, handle: PreviewPaneHandle | null) => void;
  onFocusLeaf: (tabId: number, leafId: number) => void;
};

export function PreviewStack({
  tabs,
  activeId,
  onUrlChange,
  registerHandle,
  onFocusLeaf,
}: Props) {
  const previews = tabs.filter((t): t is PreviewTab => t.kind === "preview");

  const registerRef = useRef(registerHandle);
  const urlChangeRef = useRef(onUrlChange);
  useEffect(() => {
    registerRef.current = registerHandle;
  }, [registerHandle]);
  useEffect(() => {
    urlChangeRef.current = onUrlChange;
  }, [onUrlChange]);

  const refCallbacks = useRef(
    new Map<number, (h: PreviewPaneHandle | null) => void>(),
  );
  const urlCallbacks = useRef(new Map<number, (url: string) => void>());

  const getRefCallback = (id: number) => {
    let cb = refCallbacks.current.get(id);
    if (!cb) {
      cb = (h: PreviewPaneHandle | null) => registerRef.current(id, h);
      refCallbacks.current.set(id, cb);
    }
    return cb;
  };
  const getUrlCallback = (id: number) => {
    let cb = urlCallbacks.current.get(id);
    if (!cb) {
      cb = (url: string) => urlChangeRef.current(id, url);
      urlCallbacks.current.set(id, cb);
    }
    return cb;
  };

  // Drop callback entries for closed panes to avoid unbounded growth.
  useEffect(() => {
    const live = new Set<number>();
    for (const t of previews) {
      for (const id of leafIds(t.paneTree)) live.add(id);
    }
    for (const id of refCallbacks.current.keys()) {
      if (!live.has(id)) refCallbacks.current.delete(id);
    }
    for (const id of urlCallbacks.current.keys()) {
      if (!live.has(id)) urlCallbacks.current.delete(id);
    }
  }, [previews]);

  if (previews.length === 0) return null;
  return (
    <div className="relative h-full w-full">
      {previews.map((t) => {
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
                <PreviewPane
                  ref={getRefCallback(leafId)}
                  url={t.url}
                  visible={visible && focused}
                  onUrlChange={getUrlCallback(leafId)}
                />
              )}
            />
          </div>
        );
      })}
    </div>
  );
}
