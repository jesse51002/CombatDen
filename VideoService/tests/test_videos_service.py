"""VideosService filesystem behaviour (single-tenant), driven against a tmp data
root. Uses ``asyncio.run`` so the suite needs only pytest (no pytest-asyncio)."""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from pathlib import Path

import pytest

from schema import (
    ClassImage,
    CostEntry,
    ExecutionType,
    Gym,
    GymSpecifications,
    GymVideos,
    RewardCard,
    VideoOutput,
)
from schema.gym_type import GymType
from src.api.errors import InvalidConfigError, NotFoundError
from src.api.service.videos_service import VideosService


# --- builders ----------------------------------------------------------------


def _video(vid: str, *, relevance: int = 0, **overrides: object) -> VideoOutput:
    fields: dict[str, object] = dict(
        url=f"https://www.youtube.com/watch?v={vid}",
        title=f"Video {vid}",
        description="a description kept for validation",
        thumbnail_url=f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg",
        channel_name="Some Channel",
        channel_url="https://www.youtube.com/channel/c1",
        channel_avatar_url="https://yt3.ggpht.com/pfp",
        view_count=1000,
        like_count=50,
        source_queries=["demo search"],
        relevance_index=relevance,
    )
    fields.update(overrides)
    return VideoOutput(**fields)


def _class_card(i: int) -> ClassImage:
    return ClassImage(
        name=f"Class {i}",
        image_url=f"https://img/{i}.jpg",
        description=f"About class {i}.",
        instructor_name=f"Coach {i}",
        instructor_bio=f"Bio {i}.",
        instructor_image_url=f"https://img/coach{i}.jpg",
    )


def _reward_card(i: int) -> RewardCard:
    return RewardCard(
        title=f"Reward {i}",
        image_url=f"https://img/r{i}.jpg",
        price_label="Free",
        points_cost=500 * (i + 1),
    )


def _gym(
    gym_id: str,
    theme: str,
    *,
    gym_type: list[GymType] | None = None,
    good: list[str] | None = None,
    rejected: list[str] | None = None,
    queries: list[str] | None = None,
    classes: list[ClassImage] | None = None,
    rewards: list[RewardCard] | None = None,
) -> Gym:
    return Gym(
        gym_id=gym_id,
        gym_type=gym_type or [GymType.VINYASA],
        theme=theme,
        videos=GymVideos(
            specification=GymSpecifications(
                videos_desc="flow classes", avoid_desc="no injuries"
            ),
            queries=queries or [],
            good_video_ids=good or [],
            rejected_video_ids=rejected or [],
        ),
        classes=classes,
        rewards=rewards,
    )


def _save_gym(service: VideosService, gym: Gym) -> None:
    asyncio.run(service.save_gym(gym))


# --- gyms --------------------------------------------------------------------


def test_list_gyms_empty_tree(tmp_path: Path) -> None:
    service = VideosService(root=tmp_path / "nope")
    assert asyncio.run(service.list_gyms()) == []


def test_save_gym_then_load_round_trip(tmp_path: Path) -> None:
    service = VideosService(root=tmp_path)
    _save_gym(service, _gym("vinyasa", "ZZUndoneVinyasaFlow", good=["abc", "xyz"]))

    gym = asyncio.run(service.load_gym("vinyasa"))
    assert gym.gym_id == "vinyasa"
    assert [g.value for g in gym.gym_type] == ["vinyasa"]
    assert gym.theme == "ZZUndoneVinyasaFlow"
    assert gym.videos.good_video_ids == ["abc", "xyz"]
    assert asyncio.run(service.list_gyms()) == ["vinyasa"]


def test_load_gym_missing_raises_not_found(tmp_path: Path) -> None:
    service = VideosService(root=tmp_path)
    with pytest.raises(NotFoundError):
        asyncio.run(service.load_gym("ghost"))


def test_load_gym_stale_raises_invalid(tmp_path: Path) -> None:
    (tmp_path / "gyms").mkdir(parents=True)
    (tmp_path / "gyms" / "vinyasa.yaml").write_text("gym_id: only\n")  # missing fields
    service = VideosService(root=tmp_path)
    with pytest.raises(InvalidConfigError):
        asyncio.run(service.load_gym("vinyasa"))


@pytest.mark.parametrize("bad_id", ["../escape", "Bad", "a/b", ".hidden"])
def test_malformed_gym_id_raises_not_found(tmp_path: Path, bad_id: str) -> None:
    service = VideosService(root=tmp_path)
    with pytest.raises(NotFoundError):
        asyncio.run(service.load_gym(bad_id))


def test_gym_for_theme_resolves_and_unmapped_raises(tmp_path: Path) -> None:
    service = VideosService(root=tmp_path)
    _save_gym(service, _gym("vinyasa", "ZZUndoneVinyasaFlow"))

    gym = asyncio.run(service.gym_for_theme("ZZUndoneVinyasaFlow"))
    assert gym.gym_id == "vinyasa"
    with pytest.raises(NotFoundError):
        asyncio.run(service.gym_for_theme("ZZUndoneNope"))


def test_classes_for_theme_resolves_and_missing_raises(tmp_path: Path) -> None:
    service = VideosService(root=tmp_path)
    _save_gym(
        service,
        _gym("vinyasa", "ZZUndoneVinyasaFlow", classes=[_class_card(i) for i in range(4)]),
    )
    out = asyncio.run(service.classes_for_theme("ZZUndoneVinyasaFlow"))
    assert len(out) == 4

    _save_gym(service, _gym("bare", "ApexMMA"))  # no classes
    with pytest.raises(NotFoundError):
        asyncio.run(service.classes_for_theme("ApexMMA"))


def test_rewards_for_theme_resolves_and_missing_raises(tmp_path: Path) -> None:
    service = VideosService(root=tmp_path)
    _save_gym(
        service,
        _gym("vinyasa", "ZZUndoneVinyasaFlow", rewards=[_reward_card(i) for i in range(3)]),
    )
    out = asyncio.run(service.rewards_for_theme("ZZUndoneVinyasaFlow"))
    assert len(out) == 3
    assert out[0].price_label == "Free"

    _save_gym(service, _gym("bare", "ApexMMA"))  # no rewards
    with pytest.raises(NotFoundError):
        asyncio.run(service.rewards_for_theme("ApexMMA"))


# --- gym browser page --------------------------------------------------------


def test_list_gyms_page_builds_cards(tmp_path: Path) -> None:
    service = VideosService(root=tmp_path)
    _save_gym(
        service,
        _gym(
            "vinyasa",
            "ZZUndoneVinyasaFlow",
            good=["abc", "xyz"],
            classes=[_class_card(0)],
        ),
    )
    page = asyncio.run(service.list_gyms_page(limit=20, offset=0))
    assert page.total == 1
    card = page.gyms[0]
    assert card.gym_id == "vinyasa"
    assert card.theme == "ZZUndoneVinyasaFlow"
    assert card.parent_gym_type.value == "Yoga"  # coarse bucket from vinyasa
    assert (
        card.celebration_image_url
        == "/apps/combatden/ZZUndoneVinyasaFlow/images/celebration_image"
    )
    assert card.video_count == 2  # len(good_video_ids)
    assert card.has_classes is True
    assert card.has_rewards is False


def test_list_gyms_page_paginates_sorted_by_id(tmp_path: Path) -> None:
    service = VideosService(root=tmp_path)
    for gid, theme in [("vinyasa", "T1"), ("mma", "T2"), ("boxing", "T3")]:
        _save_gym(service, _gym(gid, theme))
    first = asyncio.run(service.list_gyms_page(limit=2, offset=0))
    assert first.total == 3 and len(first.gyms) == 2
    second = asyncio.run(service.list_gyms_page(limit=2, offset=2))
    assert second.total == 3 and len(second.gyms) == 1
    # sorted by gym_id: boxing, mma, vinyasa -> offset 2 is vinyasa
    assert second.gyms[0].gym_id == "vinyasa"


def test_list_gyms_page_query_filters(tmp_path: Path) -> None:
    service = VideosService(root=tmp_path)
    _save_gym(service, _gym("vinyasa", "ZZUndoneVinyasaFlow"))
    _save_gym(service, _gym("mma", "ApexMMA", gym_type=[GymType.MMA]))
    page = asyncio.run(service.list_gyms_page(limit=20, offset=0, query="mma"))
    assert page.total == 1
    assert page.gyms[0].gym_id == "mma"


def test_list_gyms_page_empty(tmp_path: Path) -> None:
    service = VideosService(root=tmp_path)
    page = asyncio.run(service.list_gyms_page(limit=20, offset=0))
    assert page.total == 0 and page.gyms == []


# --- the shared video pool ---------------------------------------------------


def test_save_pool_then_load_round_trip_sorted(tmp_path: Path) -> None:
    service = VideosService(root=tmp_path)
    asyncio.run(
        service.save_pool(
            [
                _video("zzz", relevance=2),
                _video("aaa", relevance=0),
                _video("mmm", relevance=0),
            ]
        )
    )
    ids = [v.url.split("v=")[1] for v in asyncio.run(service.load_pool())]
    assert ids == ["aaa", "mmm", "zzz"]  # (relevance, id) order


def test_save_pool_replaces_stale_video_files(tmp_path: Path) -> None:
    service = VideosService(root=tmp_path)
    asyncio.run(service.save_pool([_video("abc"), _video("xyz", relevance=1)]))
    asyncio.run(service.save_pool([_video("abc")]))  # xyz dropped on a full replace
    assert asyncio.run(service.list_video_ids()) == ["abc"]


def test_save_video_upsert_leaves_others(tmp_path: Path) -> None:
    service = VideosService(root=tmp_path)
    asyncio.run(service.save_pool([_video("abc"), _video("xyz", relevance=1)]))

    asyncio.run(service.save_video(_video("abc", transcript="full transcript text")))
    by_id = {v.url.split("v=")[1]: v for v in asyncio.run(service.load_pool())}
    assert by_id["abc"].transcript == "full transcript text"
    assert by_id["xyz"].transcript is None  # untouched


def test_save_video_writes_transcript_last(tmp_path: Path) -> None:
    service = VideosService(root=tmp_path)
    asyncio.run(service.save_video(_video("abc", transcript="tx")))
    text = (tmp_path / "videos" / "abc.yaml").read_text()
    assert text.rstrip().splitlines()[-1].startswith("transcript:")


def test_delete_video_removes_file(tmp_path: Path) -> None:
    service = VideosService(root=tmp_path)
    asyncio.run(service.save_pool([_video("abc"), _video("xyz", relevance=1)]))
    assert asyncio.run(service.delete_video("xyz")) is True
    assert asyncio.run(service.delete_video("nope")) is False
    assert asyncio.run(service.list_video_ids()) == ["abc"]


def test_load_pool_empty_when_no_dir(tmp_path: Path) -> None:
    service = VideosService(root=tmp_path / "nope")
    assert asyncio.run(service.load_pool()) == []


# --- cost ledger -------------------------------------------------------------


def test_append_cost_is_append_only(tmp_path: Path) -> None:
    service = VideosService(root=tmp_path)
    asyncio.run(
        service.append_cost(
            CostEntry(
                execution_type=ExecutionType.SEARCH,
                at=datetime(2026, 5, 28, tzinfo=timezone.utc),
                breakdown={"apify_usd": 0.18},
            )
        )
    )
    asyncio.run(
        service.append_cost(
            CostEntry(
                execution_type=ExecutionType.TAG,
                at=datetime(2026, 5, 28, tzinfo=timezone.utc),
                breakdown={"llm_usd": 0.0123},
            )
        )
    )
    log = asyncio.run(service.load_cost_log())
    assert [e.execution_type.value for e in log] == ["search", "tag"]
    assert log[0].total_usd == 0.18
    assert log[1].total_usd == 0.0123


def test_load_cost_log_empty_when_absent(tmp_path: Path) -> None:
    service = VideosService(root=tmp_path)
    assert asyncio.run(service.load_cost_log()) == []
