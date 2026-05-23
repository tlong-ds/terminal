import { Fragment } from "react";
import {
  ResizableHandle,
  ResizablePanel,
  ResizablePanelGroup,
} from "@/components/ui/resizable";
import type { PaneNode } from "@/modules/terminal/lib/panes";

type Props = {
  node: PaneNode;
  activeLeafId: number;
  onFocusLeaf: (leafId: number) => void;
  renderLeaf: (leafId: number, focused: boolean) => React.ReactNode;
};

export function PaneTreeView({
  node,
  activeLeafId,
  onFocusLeaf,
  renderLeaf,
}: Props) {
  if (node.kind === "leaf") {
    const focused = node.id === activeLeafId;
    return (
      <div
        onMouseDownCapture={() => {
          if (!focused) onFocusLeaf(node.id);
        }}
        // Catches focus from Tab, programmatic focus, or any path that
        // skips mousedown — keeps activeLeafId in sync with DOM focus.
        onFocus={() => {
          if (!focused) onFocusLeaf(node.id);
        }}
        data-pane-leaf={node.id}
        className="relative h-full w-full"
      >
        {renderLeaf(node.id, focused)}
      </div>
    );
  }

  return (
    <ResizablePanelGroup
      orientation={node.dir === "row" ? "horizontal" : "vertical"}
    >
      {node.children.map((child, i) => (
        <Fragment key={child.id}>
          {i > 0 && <ResizableHandle />}
          <ResizablePanel id={`pane-${child.id}`} minSize="10%">
            <PaneTreeView
              node={child}
              activeLeafId={activeLeafId}
              onFocusLeaf={onFocusLeaf}
              renderLeaf={renderLeaf}
            />
          </ResizablePanel>
        </Fragment>
      ))}
    </ResizablePanelGroup>
  );
}
