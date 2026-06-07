SELECT log_id, plan_id, item_id
FROM member_attendance
WHERE member_id = :member_id
  AND class_history_id = :class_history_id
