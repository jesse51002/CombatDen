SELECT
    ms.crm_user_id,
    ms.plan_id,
    ms.gym_id,
    ms.last_paid_date,
    ms.next_due_date,
    ms.status,
    mp.plan_type,
    mp.class_count,
    COALESCE(counts.classes_used, 0) AS classes_used
FROM member_memberships_status ms
JOIN membership_plans mp ON mp.plan_id = ms.plan_id
LEFT JOIN (
    SELECT
        gl.crm_user_id,
        gl.plan_id,
        gl.gym_id,
        COUNT(*) AS classes_used
    FROM gym_classes_log gl
    JOIN member_memberships mm
        ON  mm.crm_user_id = gl.crm_user_id
        AND mm.gym_id      = gl.gym_id
        AND mm.plan_id     = gl.plan_id
    WHERE gl.gym_id = :gym_id
      AND gl.crm_user_id = ANY(CAST(:crm_user_ids AS uuid[]))
      AND gl.time >= COALESCE(mm.last_paid_date, mm.start_date)
      AND gl.time <  COALESCE(mm.next_due_date, CURRENT_DATE + INTERVAL '1 day')
    GROUP BY gl.crm_user_id, gl.plan_id, gl.gym_id
) counts
    ON  counts.crm_user_id = ms.crm_user_id
    AND counts.plan_id     = ms.plan_id
    AND counts.gym_id      = ms.gym_id
WHERE ms.gym_id = :gym_id
  AND ms.crm_user_id = ANY(CAST(:crm_user_ids AS uuid[]))
