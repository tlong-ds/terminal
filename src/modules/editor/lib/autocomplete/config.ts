export type AutocompleteProviderId =
  | "openai"
  | "anthropic"
  | "google"
  | "xai"
  | "cerebras"
  | "groq"
  | "deepseek"
  | "mistral"
  | "openrouter"
  | "openai-compatible"
  | "lmstudio"
  | "mlx"
  | "ollama";

export const DEFAULT_AUTOCOMPLETE_MODEL: Partial<Record<AutocompleteProviderId, string>> = {
  cerebras: "gpt-oss-120b",
  groq: "openai/gpt-oss-20b",
  lmstudio: "qwen2.5-coder-7b-instruct",
  openai: "gpt-5.4-nano",
  anthropic: "claude-haiku-4-5",
  google: "gemini-2.5-flash",
  xai: "grok-4-fast-reasoning",
  deepseek: "deepseek-v4-flash",
  openrouter: "openai/gpt-5.4-mini",
  "openai-compatible": "",
};

export const LMSTUDIO_DEFAULT_BASE_URL = "http://localhost:1234/v1";
export const MLX_DEFAULT_BASE_URL = "http://127.0.0.1:8080/v1";
export const OLLAMA_DEFAULT_BASE_URL = "http://localhost:11434/v1";
export const OPENAI_COMPATIBLE_DEFAULT_BASE_URL = "";
