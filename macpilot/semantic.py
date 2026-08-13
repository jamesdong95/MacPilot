"""Opt-in local AI helpers backed by a running Ollama server.

This module is intentionally dependency-free (stdlib ``urllib`` + ``json``)
and degrades gracefully: when Ollama is not reachable, callers get a clear
:class:`OllamaUnavailableError` instead of a crash. The core never requires
Ollama to run.
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from pathlib import Path

DEFAULT_OLLAMA_URL = "http://localhost:11434"
DEFAULT_MODEL = "qwen2.5:7b"
REQUEST_TIMEOUT = 180
_MAX_SUMMARY_CHARS = 8000


class OllamaUnavailableError(RuntimeError):
    """Raised when the local Ollama server cannot be reached or responds badly."""


def ollama_base_url() -> str:
    return os.environ.get("MACPILOT_OLLAMA_URL", DEFAULT_OLLAMA_URL).rstrip("/")


def _post(path: str, payload: dict, timeout: int = REQUEST_TIMEOUT) -> dict:
    url = f"{ollama_base_url()}{path}"
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url, data=data, headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, OSError, json.JSONDecodeError) as exc:
        raise OllamaUnavailableError(
            f"Ollama is not reachable at {ollama_base_url()}: {exc}"
        ) from exc


def ollama_available(timeout: int = 3) -> bool:
    """Return True if a local Ollama server answers on the configured URL."""
    try:
        _post("/api/tags", {}, timeout=timeout)
        return True
    except OllamaUnavailableError:
        return False


def summarize_text(text: str, model: str = DEFAULT_MODEL) -> str:
    """Summarize `text` with the local model, returning a short summary."""
    payload = {
        "model": model,
        "prompt": (
            "Summarize the following text in 2-3 concise sentences, "
            "preserving key facts, names, dates and numbers:\n\n" + text
        ),
        "stream": False,
    }
    response = _post("/api/generate", payload)
    return str(response.get("response", "")).strip()


def summarize_file(path: Path | str, model: str = DEFAULT_MODEL) -> str:
    """Read a text file and summarize its leading content locally."""
    file_path = Path(path).expanduser().resolve()
    data = file_path.read_text(encoding="utf-8", errors="replace")
    return summarize_text(data[:_MAX_SUMMARY_CHARS], model=model)
