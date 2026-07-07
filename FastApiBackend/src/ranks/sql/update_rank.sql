-- The SET clause is assembled in Python (ranks_service.update_rank) with
-- PER-COLUMN casts: the JSONB overrides column binds through a functional
-- CAST(... AS JSONB) and every other column as a plain bind. It always
-- uses the functional CAST form, never a bind followed by a double-colon
-- type cast, which the asyncpg bind path cannot parse. sub_rank_count is
-- user-writable; shrinking it clamps members in the same transaction but
-- never prunes the overrides map.
--
-- NOTE: keep this comment free of any bind-style token (a colon directly
-- followed by a word, e.g. the literal param placeholders) — text() scans
-- the whole statement, comments included, and would demand a value for it.
UPDATE gym_ranks
SET {set_clause}
WHERE rank_id = CAST(:rank_id AS UUID)
RETURNING
    rank_id,
    gym_id,
    main_rank_num_order,
    name,
    image_url,
    classes_to_next_major,
    sub_rank_count,
    sub_rank_image_overrides,
    created_at
