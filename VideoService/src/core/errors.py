"""The classification pass's domain error vocabulary.

Mirrors ``CustomizationService/src/core/errors.py`` so the ported
``LiteLLMClient`` raises the same names; trimmed to what this service uses.
"""

from __future__ import annotations


class PipelineError(Exception):
    """Base for every error this service raises on purpose."""


class ProviderError(PipelineError):
    """A backing provider (the LLM provider) failed."""


class SchemaValidationError(PipelineError):
    """Constrained generation never produced acceptable output within the retry bound."""
