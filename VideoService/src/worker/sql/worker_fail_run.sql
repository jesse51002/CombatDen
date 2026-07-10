-- Mark ONE run failed by id — the scrape step's cleanup when its scrape / funnel /
-- feed-write raised after the run row was already opened. Without this a transient
-- scrape error would strand a zero-row 'running' run: the finalizer's zero-row
-- grace would eventually fail it, but until then the gym can't be re-selected (a
-- gym with a 'running' run is excluded from the due-gym query), so the owner's
-- edited criteria go un-scraped. Failing the run here removes the phantom 'running'
-- run immediately so the gym is re-selectable on the next tick (bounded by the
-- rolling run caps). Guarded on status='running' so a run that somehow already
-- finished is never clobbered; setting finished_at with status='failed' satisfies
-- the video_run (status='running') = (finished_at IS NULL) CHECK.
UPDATE video_run
   SET status = 'failed',
       finished_at = now(),
       error = :error
 WHERE run_id = CAST(:run_id AS UUID)
   AND status = 'running';
