import { invoke } from "@tauri-apps/api/core";
import type { AutocompleteProviderId } from "./config";

const KEYRING_SERVICE = "bunnyshell-ai";

const KEYRING_ACCOUNTS: Record<AutocompleteProviderId, string> = {
  openai: "openai-api-key",
  anthropic: "anthropic-api-key",
  google: "google-api-key",
  xai: "xai-api-key",
  cerebras: "cerebras-api-key",
  groq: "groq-api-key",
  deepseek: "deepseek-api-key",
  mistral: "mistral-api-key",
  openrouter: "openrouter-api-key",
  "openai-compatible": "openai-compatible-api-key",
  lmstudio: "",
  mlx: "",
  ollama: "",
};

export type ProviderKeys = Record<AutocompleteProviderId, string | null>;

export const EMPTY_PROVIDER_KEYS: ProviderKeys = {
  openai: null,
  anthropic: null,
  google: null,
  xai: null,
  cerebras: null,
  groq: null,
  deepseek: null,
  mistral: null,
  openrouter: null,
  "openai-compatible": null,
  lmstudio: null,
  mlx: null,
  ollama: null,
};

function providerSupportsKey(id: AutocompleteProviderId): boolean {
  return !["lmstudio", "mlx", "ollama"].includes(id);
}

export async function getKey(provider: AutocompleteProviderId): Promise<string | null> {
  const account = KEYRING_ACCOUNTS[provider];
  if (!account) return null;
  if (!providerSupportsKey(provider)) return null;
  try {
    const v = await invoke<string | null>("secrets_get", {
      service: KEYRING_SERVICE,
      account,
    });
    return v && v.length > 0 ? v : null;
  } catch {
    return null;
  }
}
