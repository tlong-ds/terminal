"use client";

import { useState, type ReactNode } from "react";
import { CopyIcon, CheckmarkCircle01Icon } from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";

export function MarkdownCode({
  className,
  children,
  ...rest
}: {
  className?: string;
  children?: ReactNode;
}) {
  const match = className?.match(/language-(\w+)/);
  if (!match) {
    return (
      <code
        className="rounded bg-muted/70 px-1.5 py-0.5 font-mono text-[11px] text-foreground"
        {...rest}
      >
        {children}
      </code>
    );
  }

  const code = String(children ?? "").replace(/\n$/, "");
  return <CodeBlock code={code} lang={match[1] ?? null} />;
}

function CodeBlock({ code, lang }: { code: string; lang: string | null }) {
  const [copied, setCopied] = useState(false);

  const handleCopy = () => {
    navigator.clipboard.writeText(code).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 1200);
    });
  };

  return (
    <div className="group relative my-2 overflow-hidden rounded-md border border-border/50">
      <div className="flex items-center justify-between bg-muted/60 px-3 py-1 text-[11px] text-muted-foreground">
        <span>{lang ?? "code"}</span>
        <button
          type="button"
          onClick={handleCopy}
          className="flex items-center gap-1 opacity-0 transition-opacity group-hover:opacity-100"
          aria-label="Copy code"
        >
          <HugeiconsIcon
            icon={copied ? CheckmarkCircle01Icon : CopyIcon}
            size={12}
            strokeWidth={1.75}
          />
          {copied ? "Copied" : "Copy"}
        </button>
      </div>
      <pre className="overflow-x-auto p-3 text-[12px] leading-relaxed">
        <code>{code}</code>
      </pre>
    </div>
  );
}
