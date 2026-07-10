-- Look up a rec by id scoped to member + gym, to tell "rec not found for this
-- member/gym" (404) apart from an already-clicked repeat (idempotent 200).
SELECT video_id, (clicked_at IS NOT NULL) AS already_clicked
FROM member_video_recs
WHERE rec_id = CAST(:rec_id AS UUID)
  AND member_id = CAST(:member_id AS UUID)
  AND gym_id = CAST(:gym_id AS UUID)
