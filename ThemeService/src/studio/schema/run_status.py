"""RunStatus — where one studio-launched run stands."""

from __future__ import annotations

import enum


class RunStatus(str, enum.Enum):
    """The four states a launched run can be reported in.

    ``CRASHED`` is the one that is never *written*: it is what a reader
    concludes from a durable log whose last line is not a terminal record.
    Without it, done-ness would be inferred purely from ``output.yaml``
    presence (``src/executor/seed.py``), which cannot tell "still going"
    from "the process died half way".
    """

    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    CRASHED = "crashed"
