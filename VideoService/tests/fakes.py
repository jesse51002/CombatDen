"""In-memory fake of ``VideosService`` for router/transform unit tests.

The real service is a thin SQL layer (covered end-to-end by
``test_integration_db.py``). These fakes let the router + serve-time transform
tests run with no database, exercising the *router's* logic (filters, pagination,
avatar backfill, preview grouping, 404 / projection) against canned data.

It mirrors the real service's read contract faithfully — in particular
``load_gym`` returns a gym's good/rejected ids **filtered to ids present in the
pool and ordered by relevance_index**, exactly like ``load_gym.sql`` (which JOINs
``video`` and ``ORDER BY relevance_index``).
"""

from __future__ import annotations

from collections.abc import Iterable

from schema import Gym, GymCard, GymsPage, VideoOutput
from schema.parent_gym_type import parent_of
from src.api.errors import NotFoundError
from src.api.service.videos_service import _celebration_image_url
from src.shared.util.video_id import video_id_from_url


class FakeVideosService:
    """Holds gyms + a shared pool in memory; implements the read methods the
    router and viewer depend on, with the same return types as the real service."""

    def __init__(self) -> None:
        self.gyms: dict[str, Gym] = {}
        self.pool: dict[str, VideoOutput] = {}

    # --- seeding (test setup) -----------------------------------------------

    def add_gym(self, gym: Gym) -> None:
        self.gyms[gym.gym_id] = gym

    def add_videos(self, videos: list[VideoOutput]) -> None:
        for video in videos:
            self.pool[video_id_from_url(video.url)] = video

    # --- read contract (mirrors VideosService) ------------------------------

    async def list_gyms(self) -> list[str]:
        return sorted(self.gyms)

    def _ordered(self, ids: list[str]) -> list[str]:
        """Drop ids not in the pool and sort by (relevance_index, id) — exactly
        what load_gym.sql's JOIN + ORDER BY produce."""
        present = [i for i in ids if i in self.pool]
        return sorted(present, key=lambda i: (self.pool[i].relevance_index, i))

    async def load_gym(self, gym_id: str) -> Gym:
        if gym_id not in self.gyms:
            raise NotFoundError(f"no gym {gym_id!r}")
        gym = self.gyms[gym_id]
        return gym.model_copy(
            update={
                "videos": gym.videos.model_copy(
                    update={
                        "good_video_ids": self._ordered(gym.videos.good_video_ids),
                        "rejected_video_ids": self._ordered(
                            gym.videos.rejected_video_ids
                        ),
                    }
                )
            }
        )

    async def load_videos(self, video_ids: list[str]) -> list[VideoOutput]:
        return [self.pool[i] for i in video_ids if i in self.pool]

    async def load_videos_by_id(
        self, ids: Iterable[str]
    ) -> dict[str, VideoOutput]:
        return {
            i: self.pool[i] for i in dict.fromkeys(ids) if i in self.pool
        }

    async def list_gyms_page(
        self, *, limit: int, offset: int, query: str | None = None
    ) -> GymsPage:
        gyms = [self.gyms[g] for g in sorted(self.gyms)]
        if query:
            needle = query.strip().lower()
            gyms = [
                g
                for g in gyms
                if needle in g.gym_id.lower()
                or needle in g.theme.lower()
                or any(needle in t.value for t in g.gym_type)
            ]
        total = len(gyms)
        cards = [
            GymCard(
                gym_id=g.gym_id,
                gym_type=g.gym_type,
                parent_gym_type=parent_of(g.gym_type[0]),
                theme=g.theme,
                celebration_image_url=_celebration_image_url(g.theme),
                video_count=len(g.videos.good_video_ids),
                has_classes=g.classes is not None,
                has_rewards=g.rewards is not None,
            )
            for g in gyms[offset : offset + limit]
        ]
        return GymsPage(total=total, limit=limit, offset=offset, gyms=cards)
