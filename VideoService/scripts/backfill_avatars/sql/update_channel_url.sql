-- PASS 1 write: rewrite a channel's legacy `@handle`-form URL to the canonical
-- `/channel/UC…` id form, across every pool row of that channel.
--
-- This is the permanent removal of the legacy handle data, and it is what keeps a
-- `channel_id` COLUMN unnecessary: once the URL carries the id, any later pass
-- (the worker's avatar refresh, a re-run of this backfill) recovers the id from
-- the stored row by regex (`worker_transforms.channel_id_from_url`) with no second
-- column to migrate, backfill and keep in sync.
--
-- Safe to re-run: after the rewrite the old handle matches nothing.
UPDATE video
SET channel_url = :id_form_url
WHERE channel_url = :handle_url;
