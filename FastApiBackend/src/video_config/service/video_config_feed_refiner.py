"""Feed-learning spec refiner.

Folds a gym owner's manual curation signals (manual rejects / keeps / re-adds
recorded in ``gym_video_feed.curated_at``) into a new, improved
:class:`~src.video_config.schema.video_config_schema.VideoConfigDraft` via a
single structured LLM call.

The refiner is triggered on-demand (before the agent view opens, or before a
worker run) and writes nothing itself — the caller
(:meth:`VideoConfigService.refine_from_feed`) saves the resulting draft as a new
``feed_update`` spec version.

Only signals that arrived AFTER the gym's last ``feed_update`` version are
consumed (unconsumed signals); when there are none, :meth:`propose` returns
``None`` so the caller knows there is nothing new to learn.
"""

from __future__ import annotations

from string import Template
from uuid import UUID

from pydantic_ai import Agent
from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.video_config import PROMPTS_DIR, SQL_DIR
from src.video_config.schema.video_config_schema import (
    VideoConfigDraft,
    VideoConfigView,
)

_PROMPT_PATH = PROMPTS_DIR / "video_config_feed_refine.md"
_SIGNALS_SQL_PATH = SQL_DIR / "video_config_load_feed_signals.sql"


class VideoConfigFeedRefiner:
    """Proposes an improved spec version by learning from manual curation signals.

    ``agent`` is a Pydantic AI :class:`~pydantic_ai.Agent` with
    ``output_type=VideoConfigDraft``, built with ``defer_model_check=True`` so
    the backend boots even before the provider key is configured.
    """

    def __init__(
        self,
        *,
        db_pool: DirectDatabasePool,
        agent: Agent[None, VideoConfigDraft],
    ) -> None:
        self._db = db_pool
        self._agent = agent
        self._prompt_template = _PROMPT_PATH.read_text(encoding="utf-8")

    async def propose(
        self,
        gym_id: UUID,
        *,
        current: VideoConfigView,
    ) -> VideoConfigDraft | None:
        """Load unconsumed curation signals and, when any exist, run the LLM to
        produce an improved :class:`VideoConfigDraft`.

        Returns ``None`` when there are no new signals — the caller should skip
        the save and surface a "nothing new to learn" response.
        """
        signals = await self._load_signals(gym_id)
        if not signals:
            return None

        prompt = Template(self._prompt_template).safe_substitute(
            current_disciplines=", ".join(current.disciplines),
            current_videos_desc=current.videos_desc,
            current_avoid_desc=current.avoid_desc,
            current_queries="\n".join(
                f"- {q}" for q in current.queries
            ),
            signals=self._render_signals(signals),
        )
        result = await self._agent.run(prompt)
        return result.output

    # ── private helpers ─────────────────────────────────────────────────────

    async def _load_signals(self, gym_id: UUID) -> list[dict]:
        """Fetch unconsumed manual curation rows for this gym."""
        sql = load_sql(_SIGNALS_SQL_PATH)
        async with self._db.session() as session:
            rows = (
                (await session.execute(text(sql), {"gym_id": str(gym_id)}))
                .mappings()
                .all()
            )
        return [dict(row) for row in rows]

    @staticmethod
    def _render_signals(signals: list[dict]) -> str:
        """Render the curation signal rows as a readable numbered list."""
        lines: list[str] = []
        for i, s in enumerate(signals, 1):
            title = s.get("title") or "(unknown title)"
            channel = s.get("channel_name") or "(unknown channel)"
            scan_status = s.get("scan_status", "")
            rejection_type = s.get("rejection_type") or ""
            reason = s.get("reject_reason") or ""

            if scan_status == "rejected" and rejection_type == "manual":
                action = "MANUALLY REJECTED (was scan-accepted; owner rejected it)"
            else:
                action = "MANUALLY KEPT / RE-ADDED (was scan-rejected; owner kept it)"

            line = f"{i}. {title!r} by {channel!r} — {action}"
            if reason:
                line += f"\n   Reason: {reason}"
            lines.append(line)
        return "\n".join(lines)
