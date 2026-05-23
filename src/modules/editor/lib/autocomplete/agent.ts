import type { LanguageModel } from "ai";
import {
  type AutocompleteProviderId,
  LMSTUDIO_DEFAULT_BASE_URL,
  MLX_DEFAULT_BASE_URL,
  OLLAMA_DEFAULT_BASE_URL,
} from "./config";
import type { ProviderKeys } from "./keyring";

const modelCache = new Map<string, LanguageModel>();

export async function buildLanguageModel(
  provider: AutocompleteProviderId,
  keys: ProviderKeys,
  resolvedModelId: string,
  options: {
    lmstudioBaseURL?: string;
    mlxBaseURL?: string;
    ollamaBaseURL?: string;
    openaiCompatibleBaseURL?: string;
  } = {},
): Promise<LanguageModel> {
  const key = keys[provider] ?? "";
  const lmstudioURL = options.lmstudioBaseURL ?? LMSTUDIO_DEFAULT_BASE_URL;
  const mlxURL = options.mlxBaseURL ?? MLX_DEFAULT_BASE_URL;
  const ollamaURL = options.ollamaBaseURL ?? OLLAMA_DEFAULT_BASE_URL;
  const compatURL = options.openaiCompatibleBaseURL ?? "";
  const cacheKey = `${provider} ${key} ${resolvedModelId} ${lmstudioURL} ${mlxURL} ${ollamaURL} ${compatURL}`;
  const hit = modelCache.get(cacheKey);
  if (hit) return hit;

  let built: LanguageModel;
  switch (provider) {
    case "openai": {
      const { createOpenAI } = await import("@ai-sdk/openai");
      built = createOpenAI({ apiKey: key })(resolvedModelId);
      break;
    }
    case "anthropic": {
      const { createAnthropic } = await import("@ai-sdk/anthropic");
      built = createAnthropic({ apiKey: key })(resolvedModelId);
      break;
    }
    case "google": {
      const { createGoogleGenerativeAI } = await import("@ai-sdk/google");
      built = createGoogleGenerativeAI({ apiKey: key })(resolvedModelId);
      break;
    }
    case "xai": {
      const { createXai } = await import("@ai-sdk/xai");
      built = createXai({ apiKey: key })(resolvedModelId);
      break;
    }
    case "cerebras": {
      const { createCerebras } = await import("@ai-sdk/cerebras");
      built = createCerebras({ apiKey: key })(resolvedModelId);
      break;
    }
    case "deepseek": {
      const { createOpenAICompatible } = await import("@ai-sdk/openai-compatible");
      built = createOpenAICompatible({
        name: "deepseek",
        baseURL: "https://api.deepseek.com",
        apiKey: key,
      })(resolvedModelId);
      break;
    }
    case "mistral": {
      const { createOpenAICompatible } = await import("@ai-sdk/openai-compatible");
      built = createOpenAICompatible({
        name: "mistral",
        baseURL: "https://api.mistral.ai/v1",
        apiKey: key,
      })(resolvedModelId);
      break;
    }
    case "groq": {
      const { createGroq } = await import("@ai-sdk/groq");
      built = createGroq({ apiKey: key })(resolvedModelId);
      break;
    }
    case "openrouter": {
      const { createOpenAICompatible } = await import("@ai-sdk/openai-compatible");
      built = createOpenAICompatible({
        name: "openrouter",
        baseURL: "https://openrouter.ai/api/v1",
        apiKey: key,
        headers: {
          "HTTP-Referer": "https://bunnyshell.ai",
          "X-Title": "Bunnyshell",
        },
      })(resolvedModelId);
      break;
    }
    case "openai-compatible": {
      if (!compatURL) {
        throw new Error("OpenAI-compatible provider has no base URL.");
      }
      const { createOpenAICompatible } = await import("@ai-sdk/openai-compatible");
      built = createOpenAICompatible({
        name: "openai-compatible",
        baseURL: compatURL,
        apiKey: key || undefined,
      })(resolvedModelId);
      break;
    }
    case "lmstudio": {
      const { createOpenAICompatible } = await import("@ai-sdk/openai-compatible");
      built = createOpenAICompatible({
        name: "lmstudio",
        baseURL: lmstudioURL,
      })(resolvedModelId);
      break;
    }
    case "mlx": {
      const { createOpenAICompatible } = await import("@ai-sdk/openai-compatible");
      built = createOpenAICompatible({
        name: "mlx",
        baseURL: mlxURL,
      })(resolvedModelId);
      break;
    }
    case "ollama": {
      const { createOpenAICompatible } = await import("@ai-sdk/openai-compatible");
      built = createOpenAICompatible({
        name: "ollama",
        baseURL: ollamaURL,
      })(resolvedModelId);
      break;
    }
    default: {
      const _exhaustive: never = provider;
      throw new Error(`Unsupported provider: ${_exhaustive}`);
    }
  }
  modelCache.set(cacheKey, built);
  return built;
}
