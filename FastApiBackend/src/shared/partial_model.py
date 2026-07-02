"""Build an all-optional "partial" version of a Pydantic model.

Lets a *create* request and its *update* (PATCH) counterpart share ONE field
definition instead of duplicating a long field list (which drifts). Define the
fields once on a base model with their real required-ness, use the base for
create, and derive the update model with :func:`partial_model` — every field
becomes optional (``T | None``, default ``None``) with its validation
constraints (``Field(gt=...)``, ``min_length=...`` etc.) preserved.
"""

from copy import deepcopy
from typing import Any

from pydantic import BaseModel, create_model


def partial_model(
    name: str,
    base: type[BaseModel],
    *,
    extra: dict[str, Any] | None = None,
) -> type[BaseModel]:
    """Return a new model with every field of ``base`` made optional.

    Each field's annotation becomes ``Optional[...]``, its default becomes
    ``None`` (so it is no longer required), and its constraints are preserved.
    ``extra`` adds fields that are not on the base, each as
    ``name -> (annotation, default)`` (the standard ``create_model`` form).

    Args:
        name: Class name for the generated model.
        base: The model whose fields are copied and made optional.
        extra: Optional extra fields to add (e.g. update-only status flags).

    Returns:
        A new ``BaseModel`` subclass with all-optional fields.
    """
    fields: dict[str, Any] = {}
    for field_name, field_info in base.model_fields.items():
        optional_info = deepcopy(field_info)
        optional_info.default = None
        optional_info.default_factory = None
        fields[field_name] = (field_info.annotation | None, optional_info)
    if extra:
        fields.update(extra)
    return create_model(name, **fields)
