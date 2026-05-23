import { forwardRef } from "react";
import { EditorPane, type EditorPaneHandle } from "@/modules/editor/EditorPane";
import { cn } from "@/lib/utils";

type Props = {
  path: string;
  visible: boolean;
  onDirtyChange?: (dirty: boolean) => void;
};

export const MarkdownPreviewPane = forwardRef<EditorPaneHandle, Props>(
  function MarkdownPreviewPane({ path, visible, onDirtyChange }, ref) {
    return (
      <div
        className={cn(
          "h-full w-full overflow-hidden rounded-md border border-border/60 bg-background",
          !visible && "pointer-events-none",
        )}
      >
        <EditorPane
          ref={ref}
          path={path}
          onDirtyChange={onDirtyChange}
        />
      </div>
    );
  },
);
