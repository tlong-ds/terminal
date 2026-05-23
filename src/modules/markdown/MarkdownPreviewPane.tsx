import { forwardRef, useState, useCallback } from "react";
import { EditorPane, type EditorPaneHandle } from "@/modules/editor/EditorPane";
import { Streamdown } from "streamdown";
import { MarkdownCode } from "./MarkdownCode";
import { cn } from "@/lib/utils";
import {
  ResizableHandle,
  ResizablePanel,
  ResizablePanelGroup,
} from "@/components/ui/resizable";
import { HugeiconsIcon } from "@hugeicons/react";
import {
  Edit02Icon,
  LayoutTwoColumnIcon,
  EyeIcon,
} from "@hugeicons/core-free-icons";
import { Button } from "@/components/ui/button";

type Props = {
  path: string;
  visible: boolean;
  onDirtyChange?: (dirty: boolean) => void;
};

const components = { code: MarkdownCode };

export const MarkdownPreviewPane = forwardRef<EditorPaneHandle, Props>(
  function MarkdownPreviewPane({ path, visible, onDirtyChange }, ref) {
    const [layout, setLayout] = useState<"split" | "editor" | "preview">("split");
    const [liveContent, setLiveContent] = useState<string>("");
    const [status, setStatus] = useState<string>("loading");

    const handleContentChange = useCallback((content: string, status?: string) => {
      if (status) {
        setStatus(status);
      }
      setLiveContent(content);
    }, []);

    return (
      <div
        className={cn(
          "relative flex h-full w-full flex-col overflow-hidden rounded-md bg-background",
          !visible && "pointer-events-none",
        )}
      >
        {/* Floating Mode Toolbar */}
        {status === "ready" && (
          <div className="absolute top-3 right-5 z-20 flex items-center gap-0.5 rounded-lg border border-border/80 bg-background/90 p-0.5 shadow-md backdrop-blur-md">
            <Button
              variant="ghost"
              size="icon"
              onClick={() => setLayout("editor")}
              className={cn(
                "h-7 w-7 rounded-md text-muted-foreground hover:text-foreground",
                layout === "editor" && "bg-accent text-foreground",
              )}
              title="Editor Only"
            >
              <HugeiconsIcon icon={Edit02Icon} size={14} />
            </Button>
            <Button
              variant="ghost"
              size="icon"
              onClick={() => setLayout("split")}
              className={cn(
                "h-7 w-7 rounded-md text-muted-foreground hover:text-foreground",
                layout === "split" && "bg-accent text-foreground",
              )}
              title="Split View"
            >
              <HugeiconsIcon icon={LayoutTwoColumnIcon} size={14} />
            </Button>
            <Button
              variant="ghost"
              size="icon"
              onClick={() => setLayout("preview")}
              className={cn(
                "h-7 w-7 rounded-md text-muted-foreground hover:text-foreground",
                layout === "preview" && "bg-accent text-foreground",
              )}
              title="Preview Only"
            >
              <HugeiconsIcon icon={EyeIcon} size={14} />
            </Button>
          </div>
        )}

        {/* Main Content Area */}
        <div className="flex-1 min-h-0 relative">
          <ResizablePanelGroup orientation="horizontal" className="h-full w-full">
            {/* Editor Panel (Always mounted to preserve CodeMirror state and avoid infinite reload loop) */}
            <ResizablePanel
              defaultSize={50}
              minSize={layout === "editor" || status !== "ready" ? 100 : layout === "preview" ? 0 : 20}
              maxSize={layout === "preview" ? 0 : 100}
              className={cn(
                "h-full transition-all duration-200",
                layout === "preview" && "pointer-events-none opacity-0 invisible",
              )}
            >
              <div className="h-full overflow-hidden rounded-md border border-border/60 bg-background">
                <EditorPane
                  ref={ref}
                  path={path}
                  onDirtyChange={onDirtyChange}
                  onContentChange={handleContentChange}
                />
              </div>
            </ResizablePanel>

            {/* Handle */}
            <ResizableHandle
              className={cn(
                "w-1.5 hover:bg-accent/50 transition-colors",
                (layout !== "split" || status !== "ready") && "hidden pointer-events-none",
              )}
            />

            {/* Preview Panel */}
            <ResizablePanel
              defaultSize={50}
              minSize={layout === "preview" ? 100 : layout === "editor" || status !== "ready" ? 0 : 20}
              maxSize={layout === "editor" || status !== "ready" ? 0 : 100}
              className={cn(
                "h-full transition-all duration-200",
                (layout === "editor" || status !== "ready") && "pointer-events-none opacity-0 invisible",
              )}
            >
              <div className="h-full w-full overflow-auto px-6 py-4 rounded-md border border-border/60 bg-background select-text">
                {status === "ready" && (
                  <Streamdown
                    className="prose-sm [&>*:first-child]:mt-0 [&>*:last-child]:mb-0"
                    components={components}
                  >
                    {liveContent}
                  </Streamdown>
                )}
              </div>
            </ResizablePanel>
          </ResizablePanelGroup>
        </div>
      </div>
    );
  },
);
