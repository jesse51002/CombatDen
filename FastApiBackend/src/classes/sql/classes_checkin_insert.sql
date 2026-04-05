INSERT INTO gym_classes_log (crm_user_id, gym_id, class_id, plan_id, time)
VALUES (:crm_user_id, :gym_id, :class_id, :plan_id, NOW())
RETURNING log_id
