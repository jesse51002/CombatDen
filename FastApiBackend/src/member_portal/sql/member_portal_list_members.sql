-- Every member row bearing the caller's verified email, across gyms — plus the
-- three GYM CAPABILITY facts the app needs at first paint.
--
-- This is the member portal's ENTRY POINT: the app has a JWT and nothing
-- else, so it asks "who am I, and where?" before any member_id exists to
-- pass. members.email carries NO uniqueness constraint by design (a family
-- shares one inbox), so a parent's address legitimately matches several
-- rows — hence a list, and hence every other member route takes an explicit
-- member_id that is re-checked by verify_member_self.
--
-- The caller has already passed verify_verified_account, but this query
-- carries the confirmed-account predicate itself so it is safe on its own —
-- the codebase rule is that EVERY identity-resolving query proves the
-- account is confirmed. A scalar EXISTS, never a JOIN: auth.users is unique
-- on email only WHERE is_sso_user = false, so a join can fan out and
-- duplicate the member row.
--
-- The bound email is lowercased by the caller and never empty (a missing
-- claim is a 401 before this runs). COALESCE guards a NULL members.email so
-- the comparison is a hard false rather than NULL.
--
-- ── The capability flags ──────────────────────────────────────────
-- gym_rank_enabled / gym_has_rewards / gym_has_videos ride the IDENTITY read,
-- not the profile read, because the client uses them to decide which BOTTOM NAV
-- TABS to render: identity is fetched once at boot and cached, so the tab bar is
-- correct at first paint and survives offline.
--
-- gym_rank_enabled is the stored gyms.is_rank_enabled toggle. The other two are
-- DERIVED FROM DATA (there is no rewards/videos toggle — the question is only
-- whether the gym has any), and each MIRRORS the exact predicate of the
-- member-facing read it gates, so a flag can never disagree with the screen
-- behind the tab:
--
--   gym_has_rewards  mirrors src/rewards/sql/list_rewards.sql as the member
--                    portal calls it (list_rewards with include_inactive
--                    hardwired FALSE) — one gym_rewards row with is_active TRUE.
--
--   gym_has_videos   mirrors src/videos/sql/videos_feed_candidate_source.sql,
--                    the SINGLE source of "what counts as served" shared by the
--                    feed page and the rec. Copied rather than injected because
--                    that file binds one gym id while this query correlates per
--                    gym; it is reproduced line-for-line (the join to video
--                    included, redundant though the FK makes it) so the two read
--                    as an obvious pair, and a drift guard in
--                    tests/member_portal/test_member_portal_capabilities_db.py
--                    fails if the shared predicate changes without this one.
--                    "At least one video the gym's feed would serve" = enriched
--                    (INNER JOIN video_rag) AND accepted, from the owner section
--                    or the gym's latest COMPLETED run.
--
-- EXISTS, never COUNT: only a boolean is needed, so Postgres stops at the first
-- row. gym_capabilities is AS MATERIALIZED on purpose — it holds one row per
-- DISTINCT matching gym, and materializing it pins the flags to ONE evaluation
-- per gym. Inlined, the planner could pull the subquery up into the join and
-- re-run the whole feed predicate once per MEMBER row (a family spanning gyms
-- returns several rows per gym).
WITH matched_members AS (
    SELECT m.member_id,
           m.gym_id,
           m.first_name,
           m.last_name,
           m.photo_url
    FROM members m
    WHERE COALESCE(lower(m.email), '') = :email
      AND EXISTS (
          -- Pinned to the CALLER's own account (u.id = the JWT sub): the
          -- caller's OWN account must be confirmed, not just some account on
          -- this email. Email equality kept as defense in depth.
          SELECT 1
          FROM auth.users u
          WHERE u.id = CAST(:caller_id AS UUID)
            AND lower(u.email) = :email
            AND u.email_confirmed_at IS NOT NULL
      )
),
gym_capabilities AS MATERIALIZED (
    SELECT g.gym_id,
           g.gym_name,
           g.logo_url AS gym_logo_url,
           g.address AS gym_address,
           g.is_rank_enabled AS gym_rank_enabled,
           EXISTS (
               SELECT 1
               FROM gym_rewards r
               WHERE r.gym_id = g.gym_id
                 AND r.is_active = TRUE
           ) AS gym_has_rewards,
           EXISTS (
               SELECT 1
               FROM gym_video_feed f
               JOIN video v ON v.video_id = f.video_id
               JOIN video_rag rg ON rg.video_id = v.video_id
               WHERE f.gym_id = g.gym_id
                 AND f.scan_status
                     = CAST('accepted' AS gym_video_scan_status)
                 AND (
                   f.video_run_id IS NULL
                   -- Serve the latest COMPLETED run only: a mid-flight
                   -- 'running' run must never become "latest" or the feed would
                   -- blank until it finishes.
                   OR f.video_run_id = (
                       SELECT run_id FROM video_run
                       WHERE gym_id = g.gym_id
                         AND status = 'completed'
                       ORDER BY created_at DESC
                       LIMIT 1)
                 )
           ) AS gym_has_videos
    FROM gyms g
    WHERE g.gym_id IN (SELECT gym_id FROM matched_members)
)
SELECT mm.member_id,
       mm.gym_id,
       mm.first_name,
       mm.last_name,
       mm.photo_url,
       gc.gym_name,
       gc.gym_logo_url,
       gc.gym_address,
       gc.gym_rank_enabled,
       gc.gym_has_rewards,
       gc.gym_has_videos
FROM matched_members mm
JOIN gym_capabilities gc ON gc.gym_id = mm.gym_id
ORDER BY gc.gym_name ASC,
         mm.first_name ASC,
         mm.last_name ASC,
         mm.member_id ASC;
