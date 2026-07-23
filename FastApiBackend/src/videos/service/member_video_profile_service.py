"""MemberVideoProfileService — build + read a member's RAG taste profile.

The per-member RAG profile is ONE LLM-written summary plus ONE embedding, stored
directly on the ``members`` row (``video_profile_summary`` /
``video_profile_embedding`` / ``video_profile_embedding_model`` /
``video_profile_built_at``). A small chat model turns the member's facts (rank,
gym disciplines, most-attended classes, recently clicked videos) into a short
video-taste paragraph; that paragraph is embedded once and the summary embedding
is what recommendations rank against.

The profile is (re)built ONLY by ``refresh_if_due`` — the trigger gate that
rebuilds when the profile is missing or older than the refresh cooldown, fired
fire-and-forget by the class-booking / video-click triggers. Reads never build:
``verify_member_in_gym`` is the guard-only ownership check the rec path calls
before its loop, and ``verify_and_load_embedding`` is the GUARDED embedding read
the feed page uses — one row read that both verifies membership and returns the
embedding (None when the profile has not been built yet, so the feed then ranks
without similarity). There is no unguarded embedding read. Every guard first
verifies the member belongs to the gym they were asked about
(``MemberNotInGymError`` otherwise). Embeddings are
stored/read as pgvector text form and every produced vector is length-checked
against the pinned embedding dimension (a cross-service contract with the
VideoService worker that writes ``video_rag.embedding``).
"""

from __future__ import annotations

import json
from datetime import UTC, datetime, timedelta
from string import Template
from uuid import UUID

from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from src.shared.litellm_client import LiteLLMClient
from src.shared.sql_loader import load_sql
from src.videos import PROMPTS_DIR, SQL_DIR
from src.videos.schema.member_profile_schema import MemberProfileSummary

_SUMMARY_PROMPT_PATH = PROMPTS_DIR / "member_profile_summary.md"


class MemberNotInGymError(ValueError):
    """The member does not exist or does not belong to the given gym.

    Raised by the ownership guard so the router can map exactly this case
    to a 404 — any other ``ValueError`` (e.g. an embedding-dimension config
    mismatch) stays a 500 and never leaks internals to the client.
    """


class MemberVideoProfileService:
    """Build (refresh-if-due only) + read a member's video-taste profile."""

    def __init__(
        self,
        *,
        db_pool: DirectDatabasePool,
        litellm_client: LiteLLMClient,
        embedding_model: str,
        embedding_dim: int,
        summary_model: str,
        refresh_cooldown_days: int,
        attendance_window_days: int,
        top_classes_limit: int,
        recent_clicks_limit: int,
    ) -> None:
        self._db = db_pool
        self._litellm = litellm_client
        self._embedding_model = embedding_model
        self._embedding_dim = embedding_dim
        self._summary_model = summary_model
        self._refresh_cooldown_days = refresh_cooldown_days
        self._attendance_window_days = attendance_window_days
        self._top_classes_limit = top_classes_limit
        self._recent_clicks_limit = recent_clicks_limit
        self._prompt_template = _SUMMARY_PROMPT_PATH.read_text(encoding="utf-8")

    # ── public API ────────────────────────────────────────────────

    async def verify_member_in_gym(
        self, member_id: UUID, gym_id: UUID
    ) -> None:
        """Verify the member exists and belongs to ``gym_id`` (READ-ONLY).

        Raises ``MemberNotInGymError`` on a missing member or a gym mismatch,
        and NEVER builds a profile — a read must not have the side effect of
        building. The rec path calls this to 404 a member not in the path gym
        before reading their embedding; the profile itself is (re)built only by
        ``refresh_if_due`` (the click + class-booking triggers).
        """
        row = await self._load_row(member_id)
        self._guard(row, gym_id)

    async def refresh_if_due(self, member_id: UUID, gym_id: UUID) -> None:
        """Rebuild the profile when missing or past the refresh cooldown.

        Verifies membership (``MemberNotInGymError`` otherwise), then rebuilds
        when the embedding is absent or ``video_profile_built_at`` is older than
        the cooldown; a no-op within the cooldown. Safe to call often (the
        class-booking + video-click triggers fire it fire-and-forget).
        """
        row = await self._load_row(member_id)
        self._guard(row, gym_id)
        if self._needs_rebuild(row):
            await self._build(member_id, gym_id)

    async def verify_and_load_embedding(
        self, member_id: UUID, gym_id: UUID
    ) -> str | None:
        """Guard membership, then return the member's profile embedding (or None).

        The GUARDED embedding read the feed page uses: it verifies the member
        belongs to ``gym_id`` (``MemberNotInGymError`` otherwise, so a member_id
        not in the path gym never ranks a DIFFERENT gym's feed) and returns the
        pgvector text embedding in the SAME single row read — None when the
        profile has not been built yet (the feed then ranks without similarity).
        Never triggers a build. There is no unguarded embedding read: every read
        of the embedding goes through this membership guard.
        """
        row = await self._load_row(member_id)
        self._guard(row, gym_id)
        return row["embedding"]  # type: ignore[index]  # _guard ensures non-None

    # ── ownership + rebuild decision ──────────────────────────────

    @staticmethod
    def _guard(row: dict | None, gym_id: UUID) -> None:
        """Reject a missing member or a member of a DIFFERENT gym.

        Stops a caller authorized for a member (``verify_gym_employee_for_member``
        only checks the member, not the path ``gym_id``) from ranking another
        gym's feed against this member by passing a mismatched ``gym_id``.
        """
        if row is None or str(row["gym_id"]) != str(gym_id):
            raise MemberNotInGymError("Member not found in this gym")

    def _needs_rebuild(self, row: dict) -> bool:
        """True when the embedding is missing or older than the cooldown."""
        if row["embedding"] is None:
            return True
        built_at: datetime | None = row["video_profile_built_at"]
        if built_at is None:
            return True
        cutoff = datetime.now(UTC) - timedelta(days=self._refresh_cooldown_days)
        return built_at < cutoff

    # ── build ─────────────────────────────────────────────────────

    async def _build(self, member_id: UUID, gym_id: UUID) -> None:
        """Read the member's facts, summarize + embed them, and persist.

        ``gym_id`` is already verified by the caller's guard; the source read
        and the write are member-keyed.
        """
        source = await self._load_source(member_id)
        prompt = self._render_prompt(source)
        summary = await self._litellm.complete_structured(
            prompt=prompt,
            schema=MemberProfileSummary,
            model=self._summary_model,
        )
        embeddings = await self._litellm.embed(
            texts=[summary.summary], model=self._embedding_model
        )
        embedding = embeddings[0]
        self._assert_dim(embedding)
        await self._update(
            member_id, summary.summary, self._to_vector_literal(embedding)
        )

    async def _load_row(self, member_id: UUID) -> dict | None:
        """The member's profile columns (gym_id, built_at, model, embedding)."""
        sql = load_sql(SQL_DIR / "member_profile_load.sql")
        async with self._db.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql), {"member_id": str(member_id)}
                    )
                )
                .mappings()
                .fetchone()
            )
        return dict(row) if row is not None else None

    async def _load_source(self, member_id: UUID) -> dict:
        """Read the member facts the summary prompt is built from (one query)."""
        sql = load_sql(SQL_DIR / "member_profile_source.sql")
        async with self._db.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "member_id": str(member_id),
                            "window_days": self._attendance_window_days,
                            "class_limit": self._top_classes_limit,
                            "click_limit": self._recent_clicks_limit,
                        },
                    )
                )
                .mappings()
                .fetchone()
            )
        if row is None:
            raise MemberNotInGymError("Member not found in this gym")
        return dict(row)

    async def _update(
        self, member_id: UUID, summary: str, embedding_literal: str
    ) -> None:
        """Persist the rebuilt summary + embedding on the member row."""
        sql = load_sql(SQL_DIR / "member_profile_update.sql")
        params = {
            "member_id": str(member_id),
            "summary": summary,
            "embedding": embedding_literal,
            "embedding_model": self._embedding_model,
        }
        async with self._db.session() as session, session.begin():
            await session.execute(text(sql), params)

    # ── prompt rendering ──────────────────────────────────────────

    def _render_prompt(self, source: dict) -> str:
        """Fill the summary prompt from the member facts, null-safe.

        Empty facts degrade gracefully: no disciplines → "a fitness", no rank →
        "an unranked member", and empty class / clicked lists → "(none yet)".
        """
        disciplines = self._as_list(source.get("disciplines"))
        disciplines_text = ", ".join(disciplines) if disciplines else "a fitness"
        rank_name = source.get("rank_name")
        rank_text = rank_name if rank_name else "an unranked member"
        classes = self._as_list(source.get("attended_classes"))
        classes_text = ", ".join(classes) if classes else "(none yet)"
        clicked_text = self._render_clicked(
            self._as_list(source.get("clicked_videos"))
        )
        return Template(self._prompt_template).safe_substitute(
            disciplines=disciplines_text,
            rank=rank_text,
            attended_classes=classes_text,
            clicked_videos=clicked_text,
        )

    @staticmethod
    def _render_clicked(clicked: list) -> str:
        """Bulleted ``- <title> — <summary>`` lines, or "(none yet)"."""
        lines: list[str] = []
        for item in clicked:
            if not isinstance(item, dict):
                continue
            title = (item.get("title") or "").strip()
            summary = (item.get("summary") or "").strip()
            if not title:
                continue
            lines.append(f"- {title} — {summary}" if summary else f"- {title}")
        return "\n".join(lines) if lines else "(none yet)"

    # ── helpers ───────────────────────────────────────────────────

    def _assert_dim(self, vec: list[float]) -> None:
        """The produced vector must match the pinned embedding dimension.

        The ``vector(3072)`` DDL is a cross-service contract; a mismatch means a
        misconfigured embedding model, so fail loudly rather than write a
        wrong-width vector.
        """
        if len(vec) != self._embedding_dim:
            raise ValueError(
                f"embedding dimension {len(vec)} != expected "
                f"{self._embedding_dim} (model {self._embedding_model})"
            )

    @staticmethod
    def _to_vector_literal(vec: list[float]) -> str:
        """Serialize a vector to pgvector text form ``'[0.1,0.2,...]'``."""
        return "[" + ",".join(str(x) for x in vec) + "]"

    @staticmethod
    def _as_list(value: object) -> list:
        """A JSONB column as a Python list — tolerant of the driver returning a
        decoded list, a raw JSON string, or NULL."""
        if value is None:
            return []
        if isinstance(value, str):
            return json.loads(value)
        return list(value)  # type: ignore[arg-type]
