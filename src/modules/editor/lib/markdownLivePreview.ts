import {
  Decoration,
  type DecorationSet,
  EditorView,
  ViewPlugin,
  type ViewUpdate,
} from "@codemirror/view";
import { syntaxTree } from "@codemirror/language";
import { RangeSetBuilder } from "@codemirror/state";

const livePreviewTheme = EditorView.theme({
  // Clean centered document layout
  "&.cm-editor": {
    height: "100%",
  },
  ".cm-scroller": {
    overflowY: "auto",
  },
  ".cm-content": {
    padding: "24px 48px !important",
    maxWidth: "720px",
    margin: "0 auto",
    fontFamily: "var(--font-sans, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif) !important",
    fontSize: "15px !important",
    lineHeight: "1.65 !important",
  },
  // Hide line numbers and gutters for clean writing UI
  ".cm-gutters": {
    display: "none !important",
  },
  // Header styling
  ".cm-md-h1": {
    fontSize: "2em",
    fontWeight: "700",
    lineHeight: "1.3",
    color: "var(--foreground)",
    marginTop: "24px",
    marginBottom: "12px",
    display: "inline-block",
    width: "100%",
  },
  ".cm-md-h2": {
    fontSize: "1.6em",
    fontWeight: "600",
    lineHeight: "1.35",
    color: "var(--foreground)",
    marginTop: "20px",
    marginBottom: "10px",
    display: "inline-block",
    width: "100%",
  },
  ".cm-md-h3": {
    fontSize: "1.3em",
    fontWeight: "600",
    lineHeight: "1.4",
    color: "var(--foreground)",
    marginTop: "16px",
    marginBottom: "8px",
    display: "inline-block",
    width: "100%",
  },
  ".cm-md-h4": { fontSize: "1.15em", fontWeight: "600", color: "var(--foreground)" },
  ".cm-md-h5": { fontSize: "1.05em", fontWeight: "600", color: "var(--foreground)" },
  ".cm-md-h6": { fontSize: "1em", fontWeight: "600", color: "var(--muted-foreground)" },
  ".cm-md-bold": { fontWeight: "700", color: "var(--foreground)" },
  ".cm-md-italic": { fontStyle: "italic" },
  ".cm-md-code": {
    fontFamily: "var(--font-mono, monospace) !important",
    backgroundColor: "color-mix(in srgb, var(--foreground) 7%, transparent)",
    padding: "2px 5px",
    borderRadius: "4px",
    fontSize: "0.85em",
    border: "1px solid color-mix(in srgb, var(--foreground) 12%, transparent)",
  },
  ".cm-md-link": {
    color: "oklch(0.6 0.18 250)",
    textDecoration: "underline",
    cursor: "pointer",
  },
  ".cm-md-strikethrough": { textDecoration: "line-through" },
  ".cm-md-blockquote": {
    borderLeft: "4px solid var(--border)",
    paddingLeft: "16px",
    color: "var(--muted-foreground)",
    fontStyle: "italic",
    display: "inline-block",
    width: "100%",
    marginTop: "8px",
    marginBottom: "8px",
  },
});

export class LivePreviewPlugin {
  decorations: DecorationSet;

  constructor(view: EditorView) {
    this.decorations = this.buildDecorations(view);
  }

  update(update: ViewUpdate) {
    if (update.docChanged || update.selectionSet || update.viewportChanged) {
      this.decorations = this.buildDecorations(update.view);
    }
  }

  buildDecorations(view: EditorView): DecorationSet {
    const decs: { from: number; to: number; value: any }[] = [];
    const selection = view.state.selection.main;

    const overlapsSelection = (from: number, to: number) => {
      return selection.from <= to && selection.to >= from;
    };

    const isCursorOnLine = (from: number, to: number) => {
      try {
        const cursorLine = view.state.doc.lineAt(selection.from).number;
        const fromLine = view.state.doc.lineAt(from).number;
        const toLine = view.state.doc.lineAt(to).number;
        return cursorLine >= fromLine && cursorLine <= toLine;
      } catch (e) {
        return false;
      }
    };

    const tree = syntaxTree(view.state);
    for (const { from, to } of view.visibleRanges) {
      tree.iterate({
        from,
        to,
        enter(node) {
          const type = node.name;
          const parent = node.node.parent;

          // 1. Styling nodes
          if (type === "ATXHeading1") {
            decs.push({ from: node.from, to: node.to, value: Decoration.mark({ class: "cm-md-h1" }) });
          } else if (type === "ATXHeading2") {
            decs.push({ from: node.from, to: node.to, value: Decoration.mark({ class: "cm-md-h2" }) });
          } else if (type === "ATXHeading3") {
            decs.push({ from: node.from, to: node.to, value: Decoration.mark({ class: "cm-md-h3" }) });
          } else if (type === "ATXHeading4") {
            decs.push({ from: node.from, to: node.to, value: Decoration.mark({ class: "cm-md-h4" }) });
          } else if (type === "ATXHeading5") {
            decs.push({ from: node.from, to: node.to, value: Decoration.mark({ class: "cm-md-h5" }) });
          } else if (type === "ATXHeading6") {
            decs.push({ from: node.from, to: node.to, value: Decoration.mark({ class: "cm-md-h6" }) });
          } else if (type === "Emphasis") {
            decs.push({ from: node.from, to: node.to, value: Decoration.mark({ class: "cm-md-italic" }) });
          } else if (type === "StrongEmphasis") {
            decs.push({ from: node.from, to: node.to, value: Decoration.mark({ class: "cm-md-bold" }) });
          } else if (type === "InlineCode") {
            decs.push({ from: node.from, to: node.to, value: Decoration.mark({ class: "cm-md-code" }) });
          } else if (type === "Link") {
            decs.push({ from: node.from, to: node.to, value: Decoration.mark({ class: "cm-md-link" }) });
          } else if (type === "Strikethrough") {
            decs.push({ from: node.from, to: node.to, value: Decoration.mark({ class: "cm-md-strikethrough" }) });
          } else if (type === "BlockQuote") {
            decs.push({ from: node.from, to: node.to, value: Decoration.mark({ class: "cm-md-blockquote" }) });
          }

          // 2. Hiding Mark nodes when cursor is outside
          if (parent) {
            if (type === "EmphasisMark" || type === "StrikethroughMark") {
              if (!overlapsSelection(parent.from, parent.to)) {
                decs.push({ from: node.from, to: node.to, value: Decoration.replace({}) });
              }
            }
            
            if (type === "HeaderMark") {
              if (!isCursorOnLine(parent.from, parent.to)) {
                decs.push({ from: node.from, to: node.to, value: Decoration.replace({}) });
              }
            }
            
            if (type === "CodeMark") {
              if (!overlapsSelection(parent.from, parent.to)) {
                decs.push({ from: node.from, to: node.to, value: Decoration.replace({}) });
              }
            }
            
            if (type === "LinkMark" || type === "URL" || type === "LinkTitle") {
              let linkParent = parent;
              while (linkParent && linkParent.name !== "Link" && linkParent.parent) {
                linkParent = linkParent.parent;
              }
              if (linkParent && linkParent.name === "Link") {
                if (!overlapsSelection(linkParent.from, linkParent.to)) {
                  decs.push({ from: node.from, to: node.to, value: Decoration.replace({}) });
                }
              }
            }
          }
        }
      });
    }

    // Sort decorations by start position ascending, then end position ascending
    decs.sort((a, b) => {
      if (a.from !== b.from) return a.from - b.from;
      return a.to - b.to;
    });

    const builder = new RangeSetBuilder<Decoration>();
    for (const dec of decs) {
      const from = Math.max(0, Math.min(dec.from, view.state.doc.length));
      const to = Math.max(from, Math.min(dec.to, view.state.doc.length));
      if (from < to) {
        builder.add(from, to, dec.value);
      }
    }
    return builder.finish();
  }
}

const livePreviewPlugin = ViewPlugin.fromClass(LivePreviewPlugin, {
  decorations: (v) => v.decorations,
});

export function markdownLivePreview() {
  return [livePreviewTheme, livePreviewPlugin];
}
