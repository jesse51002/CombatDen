-- Stamp a served rec as clicked (first click only -- idempotent via
-- clicked_at IS NULL). Scoped to the member + gym so a caller cannot stamp
-- another member's rec. Returns the clicked video_id on the first stamp;
-- returns no row on a repeat click or when the rec does not belong to this
-- member + gym.
UPDATE member_video_recs
SET clicked_at = now()
WHERE rec_id = CAST(:rec_id AS UUID)
  AND member_id = CAST(:member_id AS UUID)
  AND gym_id = CAST(:gym_id AS UUID)
  AND clicked_at IS NULL
RETURNING video_id
