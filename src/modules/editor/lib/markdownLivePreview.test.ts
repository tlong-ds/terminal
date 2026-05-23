import { describe, expect, it } from "vitest";
import { EditorState } from "@codemirror/state";
import { markdown } from "@codemirror/lang-markdown";
import { LivePreviewPlugin } from "./markdownLivePreview";

describe("Markdown Live Preview CodeMirror Extension", () => {
  it("generates decorations for headings and bold text", () => {
    const docText = "# Heading 1\nSome text with **bold** word.";
    const state = EditorState.create({
      doc: docText,
      extensions: [markdown()],
    });

    // Mock EditorView
    const mockView = {
      state,
      visibleRanges: [{ from: 0, to: docText.length }],
    } as any;

    const pluginInstance = new LivePreviewPlugin(mockView);
    const decorations = pluginInstance.buildDecorations(mockView);

    const decsList: { from: number; to: number; class?: string; isReplace?: boolean }[] = [];
    decorations.between(0, docText.length, (from, to, value) => {
      // Log the full decoration object to see its properties
      console.log("Dec value keys:", Object.keys(value), "constructor:", value.constructor.name, "spec:", JSON.stringify(value.spec));
      decsList.push({
        from,
        to,
        class: (value.spec as any).class,
        isReplace: value.constructor.name === "PointDecoration" || (value as any).toDOM === undefined, // replacement decorations collapse ranges and usually don't have toDOM
      });
    });

    // Verify heading decorations exist
    const headingDec = decsList.find((d) => d.class === "cm-md-h1");
    expect(headingDec).toBeDefined();
    expect(headingDec?.from).toBe(0);
    expect(headingDec?.to).toBe(11);

    // Verify bold decorations exist
    const boldDec = decsList.find((d) => d.class === "cm-md-bold");
    expect(boldDec).toBeDefined();
  });
});
