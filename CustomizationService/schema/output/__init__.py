"""Public schemas for the produced `output.yaml` artifact."""

from __future__ import annotations

from schema.output.color_output import ColorOutput
from schema.output.image_output import ImageOutput
from schema.output.output import Output

__all__ = ["ColorOutput", "ImageOutput", "Output"]
