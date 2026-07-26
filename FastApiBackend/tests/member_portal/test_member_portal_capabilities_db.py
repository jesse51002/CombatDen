"""Live-DB proof of the identity read's three GYM CAPABILITY flags.

``GET /api/v1/member/members`` tells the app which bottom-nav tabs a gym even
has: ``gym_rank_enabled`` (the stored toggle) plus ``gym_has_rewards`` and
``gym_has_videos``, both DERIVED from data — there is no rewards/videos toggle,
the question is only whether the gym has any.

The derivations are only worth anything if they mean exactly what the screen
behind the tab means, so these run the REAL SQL against the live DB rather than
mocking a session:

* the seeded gym has active rewards and a served feed, so all three read True;
* a throwaway gym with ranks off, no rewards and no feed reads all three False;
* a reward the member could never redeem (inactive) does NOT flip
  ``gym_has_rewards``;
* a feed row the feed would never SERVE — rejected, or accepted but not yet
  enriched — does NOT flip ``gym_has_videos``. This is the whole point: the flag
  means "the feed would return at least one video", not "a row exists".

The last test is a DRIFT GUARD over the shared served-feed predicate.

Prereqs: the local Supabase stack is up and seeded. No backend process and no
Stripe are needed — the service is driven directly.
"""

from collections.abc import AsyncGenerator
from unittest.mock import MagicMock
from uuid import UUID, uuid4

import pytest
from sqlalchemy import text

from src.member_portal import SQL_DIR as MEMBER_PORTAL_SQL_DIR
from src.member_portal.schema.member_portal_schema import MemberPortalIdentity
from src.member_portal.service.member_portal_service import MemberPortalService
from src.videos import SQL_DIR as VIDEOS_SQL_DIR

# The seeded member whose email backs a CONFIRMED Supabase login — the identity
# query requires one, pinned to the caller's own auth.users id.
SEEDED_MEMBER_EMAIL = "member1@test.com"

# A 3072-wide unit vector: video_rag.embedding is vector(3072) NOT NULL and the
# dimension is a cross-service contract. Nothing here ranks, so the direction is
# irrelevant — only that a row EXISTS (the enrichment gate).
_EMBEDDING = "[" + ",".join(["1"] + ["0"] * 3071) + "]"


def _service(db_pool) -> MemberPortalService:
    """The real service on the real pool; the billing dep is unused here."""
    return MemberPortalService(
        db_pool=db_pool,
        billing_detail_service=MagicMock(),
    )


async def _caller_id(db_pool) -> str:
    """The confirmed ``auth.users`` id backing the seeded member's email."""
    async with db_pool.session() as session:
        row = (
            await session.execute(
                text(
                    "SELECT id FROM auth.users "
                    "WHERE lower(email) = :email "
                    "  AND email_confirmed_at IS NOT NULL "
                    "LIMIT 1"
                ),
                {"email": SEEDED_MEMBER_EMAIL},
            )
        ).mappings().fetchone()
    if row is None:
        pytest.fail(
            f"No confirmed auth account for {SEEDED_MEMBER_EMAIL} — reseed the "
            "local Supabase stack before running this module."
        )
    return str(row["id"])


async def _rows_for_gym(db_pool, gym: UUID) -> list[MemberPortalIdentity]:
    """Run the real identity read and keep only ``gym``'s rows."""
    result = await _service(db_pool).list_members_for_email(
        SEEDED_MEMBER_EMAIL, await _caller_id(db_pool)
    )
    return [row for row in result.members if row.gym_id == gym]


@pytest.fixture
async def bare_gym(db_pool) -> AsyncGenerator[UUID]:
    """A throwaway gym with ranks OFF, no rewards and no video feed.

    It holds one member carrying the seeded member's email, so the SAME
    identity call returns rows for both this gym and the seeded one — which
    also exercises the multi-gym shape the flags are grouped by. Teardown
    removes exactly what it inserts.
    """
    async with db_pool.session() as session:
        gym = UUID(
            str(
                (
                    await session.execute(
                        text(
                            "INSERT INTO gyms (gym_name, is_rank_enabled) "
                            "VALUES (:name, FALSE) RETURNING gym_id"
                        ),
                        {"name": f"ZZ Capability Gym {uuid4().hex[:8]}"},
                    )
                ).mappings().fetchone()["gym_id"]
            )
        )
        await session.execute(
            text(
                "INSERT INTO members (gym_id, first_name, last_name, email) "
                "VALUES (:g, 'ZZ', 'Capability', :e)"
            ),
            {"g": str(gym), "e": SEEDED_MEMBER_EMAIL},
        )
        await session.commit()

    try:
        yield gym
    finally:
        async with db_pool.session() as session:
            # gym_video_feed and video (custom rows) both cascade from gyms,
            # but delete explicitly so a failure here is loud rather than
            # leaving orphans behind a silent cascade.
            await session.execute(
                text("DELETE FROM gym_video_feed WHERE gym_id = :g"),
                {"g": str(gym)},
            )
            await session.execute(
                text("DELETE FROM video WHERE gym_id = :g"), {"g": str(gym)}
            )
            await session.execute(
                text("DELETE FROM gym_rewards WHERE gym_id = :g"),
                {"g": str(gym)},
            )
            await session.execute(
                text("DELETE FROM members WHERE gym_id = :g"), {"g": str(gym)}
            )
            await session.execute(
                text("DELETE FROM gyms WHERE gym_id = :g"), {"g": str(gym)}
            )
            await session.commit()


async def _add_reward(db_pool, gym: UUID, *, active: bool) -> None:
    async with db_pool.session() as session:
        await session.execute(
            text(
                "INSERT INTO gym_rewards "
                "(gym_id, title, point_cost, is_active) "
                "VALUES (:g, 'ZZ Capability Reward', 10, :a)"
            ),
            {"g": str(gym), "a": active},
        )
        await session.commit()


async def _add_feed_video(
    db_pool,
    gym: UUID,
    *,
    accepted: bool,
    enriched: bool,
) -> str:
    """Put one video in ``gym``'s OWNER section (run-independent) feed.

    Owner rows always serve, so the only things this varies are the two gates
    the flag is supposed to respect: the accept verdict and enrichment.
    """
    video_id = f"zzcap{uuid4().hex[:6]}"
    async with db_pool.session() as session:
        await session.execute(
            text(
                "INSERT INTO video (video_id, url, title, thumbnail_url, "
                "channel_name, channel_url, relevance_index, gym_id, "
                "added_via) VALUES (:v, 'https://x/', 'ZZ', 'https://x/t', "
                "'ZZ', 'https://x/c', 0, :g, 'manual')"
            ),
            {"v": video_id, "g": str(gym)},
        )
        if enriched:
            await session.execute(
                text(
                    "INSERT INTO video_rag "
                    "(video_id, summary, embedding, embedding_model) "
                    "VALUES (:v, 'ZZ', CAST(:e AS vector), 'zz-test')"
                ),
                {"v": video_id, "e": _EMBEDDING},
            )
        await session.execute(
            text(
                "INSERT INTO gym_video_feed (gym_id, video_id, scan_status) "
                "VALUES (:g, :v, CAST(:s AS gym_video_scan_status))"
            ),
            {
                "g": str(gym),
                "v": video_id,
                "s": "accepted" if accepted else "rejected",
            },
        )
        await session.commit()
    return video_id


# ── the flags ─────────────────────────────────────────────────────


async def test_seeded_gym_reports_every_capability_on(db_pool, gym_id) -> None:
    """The seeded gym runs ranks, has active rewards and a served feed."""
    rows = await _rows_for_gym(db_pool, gym_id)

    assert rows, "the seeded member should resolve to rows at the seeded gym"
    for row in rows:
        assert row.gym_rank_enabled is True
        assert row.gym_has_rewards is True
        assert row.gym_has_videos is True


async def test_bare_gym_reports_every_capability_off(
    db_pool, bare_gym
) -> None:
    """Ranks off, no rewards, no feed — every tab hidden, in ONE call."""
    rows = await _rows_for_gym(db_pool, bare_gym)

    assert len(rows) == 1
    assert rows[0].gym_rank_enabled is False
    assert rows[0].gym_has_rewards is False
    assert rows[0].gym_has_videos is False


async def test_rank_enabled_tracks_the_gyms_toggle(db_pool, bare_gym) -> None:
    """``gym_rank_enabled`` is the stored column, read per gym."""
    assert (await _rows_for_gym(db_pool, bare_gym))[0].gym_rank_enabled is False

    async with db_pool.session() as session:
        await session.execute(
            text("UPDATE gyms SET is_rank_enabled = TRUE WHERE gym_id = :g"),
            {"g": str(bare_gym)},
        )
        await session.commit()

    assert (await _rows_for_gym(db_pool, bare_gym))[0].gym_rank_enabled is True


async def test_only_an_active_reward_flips_has_rewards(
    db_pool, bare_gym
) -> None:
    """An INACTIVE reward is invisible to the member, so it must not count.

    The member route lists rewards with ``include_inactive=False`` hardwired —
    a flag that counted a retired reward would light a tab onto an empty
    screen.
    """
    await _add_reward(db_pool, bare_gym, active=False)
    assert (await _rows_for_gym(db_pool, bare_gym))[0].gym_has_rewards is False

    await _add_reward(db_pool, bare_gym, active=True)
    assert (await _rows_for_gym(db_pool, bare_gym))[0].gym_has_rewards is True


async def test_only_a_served_video_flips_has_videos(db_pool, bare_gym) -> None:
    """"A row exists" is NOT the question — "would the feed serve one?" is.

    A rejected row and an accepted-but-un-enriched row are both invisible to
    the member's feed (it INNER JOINs ``video_rag``), so neither may light the
    videos tab; only the enriched-AND-accepted row does.
    """
    await _add_feed_video(db_pool, bare_gym, accepted=False, enriched=True)
    assert (await _rows_for_gym(db_pool, bare_gym))[0].gym_has_videos is False

    await _add_feed_video(db_pool, bare_gym, accepted=True, enriched=False)
    assert (await _rows_for_gym(db_pool, bare_gym))[0].gym_has_videos is False

    await _add_feed_video(db_pool, bare_gym, accepted=True, enriched=True)
    assert (await _rows_for_gym(db_pool, bare_gym))[0].gym_has_videos is True


# ── drift guard ───────────────────────────────────────────────────


def test_has_videos_mirrors_the_shared_served_predicate() -> None:
    """The served-feed predicate is COPIED here; keep the copies honest.

    ``videos_feed_candidate_source.sql`` is the single source of "what counts
    as served", injected into the feed page and the preview. It cannot be
    injected here — it binds ONE gym id while the identity read correlates per
    gym — so the predicate is reproduced instead, and this guard reads both
    files off disk so a change to the shared one fails loudly rather than
    leaving the tab flag quietly describing an older feed.
    """
    shared = (VIDEOS_SQL_DIR / "videos_feed_candidate_source.sql").read_text()
    mirror = (
        MEMBER_PORTAL_SQL_DIR / "member_portal_list_members.sql"
    ).read_text()

    # The load-bearing clauses of the served predicate, normalised to a single
    # line so a re-wrap in either file doesn't false-positive.
    for clause in (
        "FROM gym_video_feed",
        "JOIN video_rag",
        "f.video_run_id IS NULL",
        "FROM video_run",
        "AND status = 'completed'",
        "ORDER BY created_at DESC",
    ):
        assert clause in " ".join(shared.split()), (
            f"{clause!r} vanished from the shared served predicate — update "
            "member_portal_list_members.sql's gym_has_videos EXISTS in the "
            "same change, then fix this guard."
        )
        assert clause in " ".join(mirror.split()), (
            f"{clause!r} is missing from member_portal_list_members.sql — its "
            "gym_has_videos no longer mirrors the served feed, so the videos "
            "tab can disagree with the screen behind it."
        )

    # Both must select the ACCEPTED slice: the member never sees the rejected
    # pile, so a flag built on it would be meaningless.
    assert "scan_status" in mirror
    assert "'accepted'" in mirror


def test_has_rewards_mirrors_the_member_reward_listing() -> None:
    """``gym_has_rewards`` means what ``GET …/rewards`` shows a member."""
    mirror = " ".join(
        (MEMBER_PORTAL_SQL_DIR / "member_portal_list_members.sql")
        .read_text()
        .split()
    )

    assert "FROM gym_rewards r" in mirror
    # include_inactive is hardwired FALSE on the member route, so the flag must
    # count only active rewards.
    assert "r.is_active = TRUE" in mirror
