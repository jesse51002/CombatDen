"""The template-enrich RAG sidecar — a compact, append-only artifact that carries
the paid enrichment of the template pool so any DB reproduces ``video_rag``
without re-paying the LLM summary pass.

WHY THIS EXISTS. The unified feed gates on a ``video_rag`` row (an embedding)
being present, so a freshly-imported preset/template feed would look empty until
the worker's enrich sweep caught up. The one-time ``scripts/enrich_templates``
run enriches every unique template video ONCE (one multimodal summary call each —
the expensive part) and writes the result here; ``scripts/import_yaml`` then loads
these rows into ``video_rag`` on every ``make sync-gyms``. Because ``video_rag``
is keyed by ``video_id`` and shared across the template pool AND every real gym,
seeding it for template videos enriches every gym that later imports a preset for
free.

FORMAT. One directory ``video_rag/`` (sibling to the untracked-local ``videos/``
pool), holding a single append-only JSONL ``video_rag.jsonl``. Each line is one
enriched video::

    {"video_id": "...", "summary": "...", "tag": "educational",
     "disciplines": ["mma"], "facets": {...},
     "embedding_model": "gemini/gemini-embedding-001",
     "embedding": "<base64 of little-endian float32[3072]>"}

The 3072-d embedding dominates the size, so it is stored as base64-packed
float32 (~16 KB/row) rather than a JSON float array. float32 is the exact width
``video_rag.embedding`` (``vector(3072)``) stores, so the round-trip is lossless
against the DB. At ~18.9k template videos the whole artifact is ~330 MB — far past
a git-trackable size and high-entropy (won't delta-compress), so it lives
untracked-local like ``videos/`` and is distributed to prod the same way (manual
S3 upload + fetch; see VideoService/CLAUDE.md). (The packer is dimension-agnostic —
it reads the length off each vector — so the width follows the model.)

DISTRIBUTION. Both writer (``enrich_templates``) and reader (``import_yaml``)
speak this format only through this module, so the layout has one owner.
"""

from __future__ import annotations

import base64
import json
import logging
import struct
from collections.abc import Iterator, Sequence
from dataclasses import dataclass, field
from pathlib import Path

logger = logging.getLogger(__name__)

# Sibling of the untracked-local ``videos/`` pool; single append-only JSONL.
SIDECAR_DIRNAME = "video_rag"
SIDECAR_FILENAME = "video_rag.jsonl"
# Little-endian float32 — the exact width pgvector stores, pinned byte order so
# the artifact is portable across machines.
_FLOAT_STRUCT = "<%df"


@dataclass(frozen=True)
class VideoRagRecord:
    """One enriched template video: the full enrich output plus its embedding.

    ``tag`` / ``disciplines`` are the enricher's other outputs (written onto
    ``video`` by the live worker); they are persisted here so the artifact is a
    complete record of the paid pass, even though the sidecar LOAD writes only the
    ``video_rag`` half (the pool already carries tags from ``videos/<id>.yaml``)."""

    video_id: str
    summary: str
    tag: str
    disciplines: list[str]
    facets: dict = field(default_factory=dict)
    embedding: list[float] = field(default_factory=list)
    embedding_model: str = ""


class VideoRagSidecar:
    """Append-only reader/writer over ``video_rag/video_rag.jsonl``."""

    def __init__(self, root: Path) -> None:
        self._dir = root / SIDECAR_DIRNAME
        self._path = self._dir / SIDECAR_FILENAME

    @property
    def path(self) -> Path:
        return self._path

    def exists(self) -> bool:
        return self._path.is_file()

    def existing_ids(self) -> set[str]:
        """The ``video_id`` of every record already written — the resumable-skip
        set. A truncated final line from an interrupted run is tolerated (parsed
        best-effort, skipped if unreadable)."""
        if not self._path.is_file():
            return set()
        ids: set[str] = set()
        with self._path.open(encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                try:
                    ids.add(json.loads(line)["video_id"])
                except (json.JSONDecodeError, KeyError, TypeError):
                    # A partial trailing line from a crash — ignore it; its video
                    # is simply re-enriched on the next run.
                    continue
        return ids

    def append(self, records: Sequence[VideoRagRecord]) -> None:
        """Append records as JSONL lines (embedding base64-packed), flushing so a
        later crash loses at most the batch in flight."""
        if not records:
            return
        self._dir.mkdir(parents=True, exist_ok=True)
        with self._path.open("a", encoding="utf-8") as handle:
            for record in records:
                handle.write(json.dumps(self._to_line(record)) + "\n")
            handle.flush()

    def read_all(self) -> Iterator[VideoRagRecord]:
        """Yield every record, decoding each embedding back to a float list. A
        corrupt line is logged and skipped rather than aborting the load."""
        if not self._path.is_file():
            return
        with self._path.open(encoding="utf-8") as handle:
            for number, line in enumerate(handle, start=1):
                line = line.strip()
                if not line:
                    continue
                try:
                    yield self._from_line(json.loads(line))
                except (json.JSONDecodeError, KeyError, TypeError, ValueError) as exc:
                    logger.warning(
                        "skipping unreadable sidecar line %d: %s", number, exc
                    )
                    continue

    @classmethod
    def _to_line(cls, record: VideoRagRecord) -> dict:
        return {
            "video_id": record.video_id,
            "summary": record.summary,
            "tag": record.tag,
            "disciplines": list(record.disciplines),
            "facets": record.facets,
            "embedding_model": record.embedding_model,
            "embedding": cls.encode_embedding(record.embedding),
        }

    @classmethod
    def _from_line(cls, raw: dict) -> VideoRagRecord:
        return VideoRagRecord(
            video_id=raw["video_id"],
            summary=raw["summary"],
            tag=raw["tag"],
            disciplines=list(raw.get("disciplines", [])),
            facets=raw.get("facets", {}),
            embedding=cls.decode_embedding(raw["embedding"]),
            embedding_model=raw.get("embedding_model", ""),
        )

    @staticmethod
    def encode_embedding(vector: Sequence[float]) -> str:
        """Pack a float vector as base64 little-endian float32."""
        packed = struct.pack(_FLOAT_STRUCT % len(vector), *(float(f) for f in vector))
        return base64.b64encode(packed).decode("ascii")

    @staticmethod
    def decode_embedding(encoded: str) -> list[float]:
        """Unpack a base64 little-endian float32 blob back to a float list."""
        raw = base64.b64decode(encoded)
        return list(struct.unpack(_FLOAT_STRUCT % (len(raw) // 4), raw))

    @staticmethod
    def to_pgvector(vector: Sequence[float]) -> str:
        """A float vector as the pgvector text literal ``[f1,f2,...]`` the
        ``video_rag.embedding`` insert casts (mirrors the worker enricher)."""
        return "[" + ",".join(repr(float(f)) for f in vector) + "]"
