"""provider_api_key — resolve the provider key for a litellm model id.

The LLM client (``LiteLLMClient``) routes by the provider prefix on the model
id ("anthropic/…", "gemini/…", "openai/…") and hands litellm that provider's
key. This is the single source of that mapping. Gemma routes on ``gemini``.
"""

from __future__ import annotations

from src.core.config import settings
from src.core.errors import ProviderError

# Provider prefix → the ``settings`` attribute holding its key. New
# providers: add the prefix here (and the key field in ``config.py``).
PROVIDER_KEY_ATTR: dict[str, str] = {
    "anthropic": "anthropic_api_key",
    "gemini": "gemini_api_key",
    "openai": "openai_api_key",
}


def provider_api_key(model: str) -> str:
    """Resolve the configured key for a provider-routed model id.

    Raises:
        ProviderError: the model's provider prefix has no configured key.
    """
    provider = model.split("/", 1)[0]
    try:
        return getattr(settings, PROVIDER_KEY_ATTR[provider])
    except KeyError as exc:
        raise ProviderError(
            f"no API key configured for provider {provider!r} "
            f"(model {model!r})"
        ) from exc
