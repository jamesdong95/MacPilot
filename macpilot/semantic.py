"""Opt-in local/cloud LLM helpers for summarization.

This module is intentionally dependency-free (stdlib ``urllib`` + ``json``)
and degrades gracefully: when a provider is unreachable, callers get a clear
:class:`LLMUnavailableError` instead of a crash. The core never requires a
model to run.

Two providers are supported:

* ``ollama`` (default) — a local Ollama server (``MACPILOT_OLLAMA_URL``).
* ``cloud`` — any OpenAI-compatible chat-completions endpoint, configured via
  ``MACPILOT_CLOUD_BASE_URL`` / ``MACPILOT_CLOUD_MODEL`` /
  ``MACPILOT_CLOUD_API_KEY``. Works with OpenAI, Anthropic-compatible gateways,
  OpenRouter, LM Studio, vLLM, etc.

The provider is selected with ``MACPILOT_LLM_PROVIDER``.
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from pathlib import Path

DEFAULT_OLLAMA_URL = "http://localhost:11434"
DEFAULT_MODEL = "qwen2.5:7b"
DEFAULT_CLOUD_MODEL = "gpt-4o-mini"
DEFAULT_EMBED_MODEL = "nomic-embed-text"
DEFAULT_CLOUD_EMBED_MODEL = "text-embedding-3-small"
REQUEST_TIMEOUT = 180
_MAX_SUMMARY_CHARS = 8000

# Semantic tags for auto-classification. Each value is a short description that
# is embedded and compared against a file's content embedding.
TAG_DEFINITIONS = {
    "invoice": "an invoice or bill requesting payment with amounts, line items, and due dates",
    "contract": "a legal contract or agreement with terms, parties, and signatures",
    "receipt": "a receipt or proof-of-purchase transaction record",
    "resume": "a resume or CV listing work experience, skills, and education",
    "report": "a report or analysis document with findings, data, and conclusions",
    "notes": "personal notes, meeting notes, or a short memo",
    "screenshot": "a screenshot or screen capture image",
    "photo": "a photograph or picture",
}
_TAG_THRESHOLD = 0.30


class LLMUnavailableError(RuntimeError):
    """Raised when the selected LLM provider cannot be reached or responds badly."""


# Backwards-compatible alias so existing callers keep working.
OllamaUnavailableError = LLMUnavailableError


def ollama_base_url() -> str:
    return os.environ.get("MACPILOT_OLLAMA_URL", DEFAULT_OLLAMA_URL).rstrip("/")


def _post_json(
    url: str,
    payload: dict,
    *,
    timeout: int = REQUEST_TIMEOUT,
    api_key: str | None = None,
) -> dict:
    data = json.dumps(payload).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    request = urllib.request.Request(url, data=data, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, OSError, json.JSONDecodeError) as exc:
        raise LLMUnavailableError(f"LLM provider is not reachable at {url}: {exc}") from exc


def ollama_available(timeout: int = 3) -> bool:
    """Return True if a local Ollama server answers on the configured URL."""
    try:
        _post_json(f"{ollama_base_url()}/api/tags", {}, timeout=timeout)
        return True
    except LLMUnavailableError:
        return False


def _ollama_summarize(text: str, model: str) -> str:
    payload = {
        "model": model,
        "prompt": (
            "Summarize the following text in 2-3 concise sentences, "
            "preserving key facts, names, dates and numbers:\n\n" + text
        ),
        "stream": False,
    }
    response = _post_json(f"{ollama_base_url()}/api/generate", payload)
    return str(response.get("response", "")).strip()


def _cloud_summarize(text: str, base_url: str, api_key: str, model: str) -> str:
    url = base_url.rstrip("/") + "/v1/chat/completions"
    payload = {
        "model": model,
        "messages": [
            {
                "role": "system",
                "content": "You summarize text concisely, preserving key facts.",
            },
            {
                "role": "user",
                "content": "Summarize this in 2-3 sentences:\n\n" + text,
            },
        ],
        "stream": False,
    }
    response = _post_json(url, payload, api_key=api_key or None)
    choices = response.get("choices") or []
    if not choices:
        raise LLMUnavailableError(f"Cloud LLM returned no choices: {url}")
    message = choices[0].get("message") or {}
    return str(message.get("content", "")).strip()


def summarize_text(
    text: str,
    model: str | None = None,
    provider: str | None = None,
) -> str:
    """Summarize `text` using the selected provider (env or explicit)."""
    selected = provider or os.environ.get("MACPILOT_LLM_PROVIDER", "ollama")
    if selected == "cloud":
        base_url = os.environ.get("MACPILOT_CLOUD_BASE_URL", "")
        if not base_url:
            raise LLMUnavailableError(
                "Cloud provider needs MACPILOT_CLOUD_BASE_URL (or configure it in Settings)"
            )
        api_key = os.environ.get("MACPILOT_CLOUD_API_KEY", "")
        cloud_model = model or os.environ.get("MACPILOT_CLOUD_MODEL", DEFAULT_CLOUD_MODEL)
        return _cloud_summarize(text, base_url, api_key, cloud_model)
    return _ollama_summarize(text, model or DEFAULT_MODEL)


def summarize_file(
    path: Path | str,
    model: str | None = None,
    provider: str | None = None,
) -> str:
    """Read a text file and summarize its leading content via the selected provider."""
    file_path = Path(path).expanduser().resolve()
    data = file_path.read_text(encoding="utf-8", errors="replace")
    return summarize_text(data[:_MAX_SUMMARY_CHARS], model=model, provider=provider)


def _ollama_embed(text: str, model: str) -> list[float]:
    url = f"{ollama_base_url()}/api/embeddings"
    response = _post_json(url, {"model": model, "prompt": text})
    embedding = response.get("embedding")
    if not embedding:
        raise LLMUnavailableError(f"Ollama returned no embedding at {url}")
    return [float(value) for value in embedding]


def _cloud_embed(
    texts: list[str],
    base_url: str,
    api_key: str,
    model: str,
) -> list[list[float]]:
    url = base_url.rstrip("/") + "/v1/embeddings"
    response = _post_json(
        url,
        {"model": model, "input": texts},
        api_key=api_key or None,
    )
    data = response.get("data") or []
    if not data:
        raise LLMUnavailableError(f"Cloud LLM returned no embeddings at {url}")
    return [[float(value) for value in item["embedding"]] for item in data]


def embed_texts(
    texts: list[str],
    *,
    provider: str | None = None,
    model: str | None = None,
) -> list[list[float]]:
    """Embed a list of texts with the selected provider (env or explicit).

    Returns one vector per input text, in order. The local provider uses the
    Ollama embeddings endpoint; the cloud provider uses any OpenAI-compatible
    ``/v1/embeddings`` endpoint.
    """
    selected = provider or os.environ.get("MACPILOT_LLM_PROVIDER", "ollama")
    if selected == "cloud":
        base_url = os.environ.get("MACPILOT_CLOUD_BASE_URL", "")
        if not base_url:
            raise LLMUnavailableError(
                "Cloud provider needs MACPILOT_CLOUD_BASE_URL (or configure it in Settings)"
            )
        api_key = os.environ.get("MACPILOT_CLOUD_API_KEY", "")
        embed_model = model or os.environ.get(
            "MACPILOT_CLOUD_EMBED_MODEL", DEFAULT_CLOUD_EMBED_MODEL
        )
        return _cloud_embed(texts, base_url, api_key, embed_model)
    embed_model = model or os.environ.get("MACPILOT_EMBED_MODEL", DEFAULT_EMBED_MODEL)
    return [_ollama_embed(text, embed_model) for text in texts]


def _cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    norm_a = sum(x * x for x in a) ** 0.5
    norm_b = sum(y * y for y in b) ** 0.5
    if norm_a == 0 or norm_b == 0:
        return 0.0
    return dot / (norm_a * norm_b)


def classify_tag(
    text: str,
    *,
    provider: str | None = None,
    model: str | None = None,
) -> str | None:
    """Classify `text` into the closest predefined tag, or None if unsure.

    Embeds the text and every tag description in one batch, then returns the
    highest-similarity tag above a threshold. Best-effort: never raises for
    provider failures (the caller treats it as optional enrichment).
    """
    if not text.strip():
        return None
    try:
        vectors = embed_texts(
            [text] + list(TAG_DEFINITIONS.values()),
            provider=provider,
            model=model,
        )
    except LLMUnavailableError:
        return None
    if len(vectors) != 1 + len(TAG_DEFINITIONS):
        return None
    text_vector = vectors[0]
    best_tag: str | None = None
    best_score = -1.0
    for (tag, _), vector in zip(TAG_DEFINITIONS.items(), vectors[1:]):
        score = _cosine(text_vector, vector)
        if score > best_score:
            best_score = score
            best_tag = tag
    return best_tag if best_score >= _TAG_THRESHOLD else None
