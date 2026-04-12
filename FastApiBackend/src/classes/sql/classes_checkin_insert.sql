INSERT INTO gym_classes_log (crm_user_id, gym_id, class_id, plan_id, item_id, time)
VALUES (:crm_user_id, :gym_id, :class_id, :plan_id, :item_id, NOW())
RETURNING log_id
