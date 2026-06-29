"""Feed-learning spec refiner.

Folds a gym owner's manual curation signals (manual rejects / keeps / re-adds
recorded in ``gym_video_feed.curated_at``) into a new, improved
:class:`~src.videos.schema.video_spec_schema.VideoSpecDraft` (criteria only) via
a single structured LLM call, then commits it via
:class:`~src.videos.service.video_spec_authoring.VideoSpecAuthoring` — which runs
the diff guard, generates queries if the criteria changed, saves, and marks the
TODO for feed-regeneration.

Only signals that arrived AFTER the gym's last ``feed_update`` version are
consumed (unconsumed signals); when there are none, :meth:`refine_from_feed`
returns ``None`` so the caller knows there is nothing new to learn.
"""

from __future__ import annotations

from string import Template
from uuid import UUID

from schema.video import GymVideoSpecSource
from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from src.shared.litellm_client import LiteLLMClient
from src.shared.sql_loader import load_sql
from src.videos import PROMPTS_DIR, SQL_DIR
from src.videos.schema.video_spec_schema import VideoSpecDraft, VideoSpecView
from src.videos.service.video_spec_authoring import VideoSpecAuthoring
from src.videos.service.video_spec_service import VideoSpecService

_PROMPT_PATH = PROMPTS_DIR / "video_feed_refine.md"
_SIGNAL_ENTRY_PATH = PROMPTS_DIR / "video_feed_signal_entry.md"
_SIGNALS_SQL_PATH = SQL_DIR / "video_feed_signals.sql"


class VideoFeedRefiner:
    """Folds unconsumed manual curation signals into a new spec version."""

    def __init__(
        self,
        *,
        db_pool: DirectDatabasePool,
        spec_service: VideoSpecService,
        litellm_client: LiteLLMClient,
        model: str,
        authoring: VideoSpecAuthoring,
    ) -> None:
        self._db = db_pool
        self._spec_service = spec_service
        self._litellm_client = litellm_client
        self._model = model
        self._authoring = authoring
        self._prompt_template = _PROMPT_PATH.read_text(encoding="utf-8")
        self._signal_template = _SIGNAL_ENTRY_PATH.read_text(encoding="utf-8")

    async def refine_from_feed(self, gym_id: UUID) -> VideoSpecView | None:
        """Load unconsumed curation signals and, when any exist, run the LLM to
        produce improved criteria, then commit via the shared authoring path.

        Returns the new :class:`VideoSpecView` when signals were found and the
        criteria changed; ``None`` when there is either no current spec, no new
        signals to learn from, or the refined criteria are identical to the
        current spec (diff guard).
        """
        latest = await self._spec_service.load_latest(gym_id)
        if latest is None:
            return None

        signals = await self._load_signals(gym_id)
        if not signals:
            return None

        prompt = Template(self._prompt_template).safe_substitute(
            current_disciplines=", ".join(latest.disciplines),
            current_videos_desc=latest.videos_desc,
            current_avoid_desc=latest.avoid_desc,
            signals=self._render_signals(signals),
        )
        improved_criteria = await self._litellm_client.complete_structured(
            prompt=prompt,
            schema=VideoSpecDraft,
            model=self._model,
        )
        return await self._authoring.commit(
            gym_id, improved_criteria, source=GymVideoSpecSource.feed_update
        )

    # ── private helpers ─────────────────────────────────────────

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

    # Max characters to include from description / transcript in each signal.
    # Long enough for meaningful context; short enough to keep the prompt lean.
    _DESC_LIMIT = 400
    _TRANSCRIPT_LIMIT = 600

    def _render_signals(self, signals: list[dict]) -> str:
        """Render the curation signal rows into the prompt via the
        ``video_feed_signal_entry.md`` template — no prompt text is built here.

        Each entry fills the template with the video's title/channel, the owner's
        action (``kept`` vs ``rejected``, from scan_status), their stated reason
        (curation_reason), and truncated description/transcript snippets. Absent
        optional fields render as an em-dash. curation_type is always 'manual'
        for rows the signal query returns.
        """
        template = Template(self._signal_template)
        entries: list[str] = []
        for i, s in enumerate(signals, 1):
            description = (s.get("description") or "").strip()
            transcript = (s.get("transcript") or "").strip()
            entries.append(
                template.safe_substitute(
                    index=i,
                    title=s.get("title") or "(unknown title)",
                    channel=s.get("channel_name") or "(unknown channel)",
                    decision="kept"
                    if s.get("scan_status") == "accepted"
                    else "rejected",
                    reason=(s.get("curation_reason") or "").strip() or "—",
                    description=self._truncate(description, self._DESC_LIMIT)
                    if description
                    else "—",
                    transcript=self._truncate(transcript, self._TRANSCRIPT_LIMIT)
                    if transcript
                    else "—",
                )
            )
        return "\n\n".join(entries)

    @staticmethod
    def _truncate(text: str, limit: int) -> str:
        """Return ``text`` truncated to ``limit`` chars with an ellipsis if cut."""
        if len(text) <= limit:
            return text
        return text[:limit].rstrip() + "…"
