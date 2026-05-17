"""``python -m src`` entrypoint: run the async CLI, propagate its exit code."""

from __future__ import annotations

import asyncio

from src.cli import main

if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
