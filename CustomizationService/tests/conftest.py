"""Shared pytest configuration."""

from __future__ import annotations

import pytest


def pytest_configure(config: pytest.Config) -> None:
    config.addinivalue_line(
        "markers",
        "golden: live, paid cutout-validator eval against the hand-labeled "
        "corpus. Excluded from the default suite; run via `make test-golden`.",
    )
