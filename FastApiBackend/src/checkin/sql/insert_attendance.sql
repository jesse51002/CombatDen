INSERT INTO member_attendance (member_id, gym_id, class_history_id, plan_id, item_id)
VALUES (:member_id, :gym_id, :class_history_id, :plan_id, :item_id)
ON CONFLICT (member_id, class_history_id) DO NOTHING
RETURNING log_id
