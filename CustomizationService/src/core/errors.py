"""The pipeline's domain error vocabulary."""

from __future__ import annotations


class PipelineError(Exception):
    """Base for every error this pipeline raises on purpose."""


class ProviderError(PipelineError):
    """A backing provider (an LLM provider, an image model, or PhotoRoom) failed."""


class SchemaValidationError(PipelineError):
    """Constrained generation never produced acceptable output within the retry bound."""


class ValidationFeedback(PipelineError):
    """Raised by a ``validate=`` callback to reject valid-but-unacceptable output;
    the client re-asks, surfacing as ``SchemaValidationError`` if exhausted."""
