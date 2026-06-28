"""VideoConfigService — the facade for a gym's video-config authoring.

Orchestrates the conversational agent, the single-call query generator, and the
append-only spec read/write. It is the sole writer of ``gym_video_spec`` on the
authed path (each save/refine appends a version; readers take the latest via the
``gym_video_spec_latest`` view).
"""

from __future__ import annotations

import json
from uuid import UUID

from pydantic_ai import Agent
from pydantic_ai.messages import ModelMessagesTypeAdapter
from schema.video import GymVideoSpecSource
from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.video_config import SQL_DIR
from src.video_config.schema.video_config_schema import (
    DEFAULT_QUERY_COUNT,
    GenerateQueriesRequest,
    VideoConfigAgentRequest,
    VideoConfigAgentResponse,
    VideoConfigDraft,
    VideoConfigView,
)
from src.video_config.service.video_config_agent import (
    VideoConfigAgentOutput,
    VideoConfigDeps,
)
from src.video_config.service.video_config_feed_refiner import (
    VideoConfigFeedRefiner,
)
from src.video_config.service.video_config_query_generator import (
    VideoConfigQueryGenerator,
)
from src.videos.schema.videos_gym_type import GymType


class VideoConfigInputError(ValueError):
    """The request can't be fulfilled — e.g. generate-queries was called with no
    disciplines/criteria and the gym has no existing spec to default from."""


class VideoConfigService:
    """Authoring surface for a gym's append-only video config."""

    def __init__(
        self,
        *,
        db_pool: DirectDatabasePool,
        agent: Agent[VideoConfigDeps, VideoConfigAgentOutput],
        query_generator: VideoConfigQueryGenerator,
        feed_refiner: VideoConfigFeedRefiner,
    ) -> None:
        self._db = db_pool
        self._agent = agent
        self._query_generator = query_generator
        self._feed_refiner = feed_refiner

    # ── reads ────────────────────────────────────────────────────

    async def load_latest(self, gym_id: UUID) -> VideoConfigView | None:
        """The gym's latest spec version, or None when none exists yet."""
        sql = load_sql(SQL_DIR / "video_config_load_latest.sql")
        async with self._db.session() as session:
            row = (
                (await session.execute(text(sql), {"gym_id": str(gym_id)}))
                .mappings()
                .fetchone()
            )
        return self._row_to_view(row) if row is not None else None

    # ── query generator ─────────────────────────────────────────

    async def generate_queries(
        self, gym_id: UUID, request: GenerateQueriesRequest
    ) -> list[str]:
        """Generate search queries — omitted inputs default to the gym's spec."""
        current: VideoConfigView | None = None
        if (
            request.disciplines is None
            or request.videos_desc is None
            or request.avoid_desc is None
        ):
            current = await self.load_latest(gym_id)

        disciplines = request.disciplines
        if disciplines is None and current is not None:
            disciplines = [GymType(d) for d in current.disciplines]
        videos_desc = request.videos_desc
        if videos_desc is None and current is not None:
            videos_desc = current.videos_desc
        avoid_desc = request.avoid_desc
        if avoid_desc is None and current is not None:
            avoid_desc = current.avoid_desc

        if not disciplines or videos_desc is None or avoid_desc is None:
            raise VideoConfigInputError(
                "disciplines, videos_desc and avoid_desc are required when the "
                "gym has no existing spec to default from"
            )

        return await self._query_generator.generate(
            disciplines=disciplines,
            videos_desc=videos_desc,
            avoid_desc=avoid_desc,
            count=request.count or DEFAULT_QUERY_COUNT,
        )

    # ── confirm / save ──────────────────────────────────────────

    async def save_draft(
        self,
        gym_id: UUID,
        draft: VideoConfigDraft,
        *,
        source: GymVideoSpecSource = GymVideoSpecSource.admin_update,
    ) -> VideoConfigView:
        """Append a new spec version from a confirmed draft; return it."""
        sql = load_sql(SQL_DIR / "video_config_insert_version.sql")
        params = {
            "gym_id": str(gym_id),
            "gym_type": json.dumps([d.value for d in draft.disciplines]),
            "short_videos_desc": draft.short_videos_desc,
            "short_avoid_desc": draft.short_avoid_desc,
            "videos_desc": draft.videos_desc,
            "avoid_desc": draft.avoid_desc,
            "queries": json.dumps(draft.queries),
            "source": source.value,
            "imported_from": None,
        }
        async with self._db.session() as session, session.begin():
            row = (
                (await session.execute(text(sql), params)).mappings().fetchone()
            )
        return self._row_to_view(row)

    # ── feed-learning refiner ───────────────────────────────────

    async def refine_from_feed(self, gym_id: UUID) -> VideoConfigView | None:
        """Fold unconsumed manual curation signals into a new spec version.

        Returns the new :class:`VideoConfigView` (tagged ``feed_update``) when
        signals were found and a draft was produced; ``None`` when there is
        either no current spec or no new signals to learn from.
        """
        latest = await self.load_latest(gym_id)
        if latest is None:
            return None
        draft = await self._feed_refiner.propose(gym_id, current=latest)
        if draft is None:
            return None
        return await self.save_draft(
            gym_id, draft, source=GymVideoSpecSource.feed_update
        )

    # ── conversational agent ────────────────────────────────────

    async def agent_turn(
        self, gym_id: UUID, request: VideoConfigAgentRequest
    ) -> VideoConfigAgentResponse:
        """Run one conversational turn; return the reply or a finished draft."""
        history = (
            ModelMessagesTypeAdapter.validate_python(request.history)
            if request.history
            else None
        )
        deps = VideoConfigDeps(
            gym_id=gym_id,
            query_generator=self._query_generator,
            load_current_config=self.load_latest,
        )
        result = await self._agent.run(
            request.message, message_history=history, deps=deps
        )
        new_history = ModelMessagesTypeAdapter.dump_python(
            result.all_messages(), mode="json"
        )
        output = result.output
        draft = output if isinstance(output, VideoConfigDraft) else None
        reply = output if isinstance(output, str) else None
        return VideoConfigAgentResponse(
            reply=reply,
            draft=draft,
            history=new_history,
            usage=self._usage_dict(result.usage),
        )

    # ── helpers ─────────────────────────────────────────────────

    def _row_to_view(self, row: object) -> VideoConfigView:
        data = dict(row)  # type: ignore[arg-type]
        data["disciplines"] = self._as_list(data.pop("gym_type"))
        data["queries"] = self._as_list(data.get("queries"))
        return VideoConfigView.model_validate(data)

    @staticmethod
    def _as_list(value: object) -> list:
        """A JSONB column as a Python list — tolerant of the driver returning
        either a decoded list or the raw JSON string."""
        if value is None:
            return []
        if isinstance(value, str):
            return json.loads(value)
        return value

    @staticmethod
    def _usage_dict(usage: object) -> dict[str, int]:
        return {
            key: getattr(usage, key)
            for key in ("requests", "input_tokens", "output_tokens", "total_tokens")
            if getattr(usage, key, None) is not None
        }
