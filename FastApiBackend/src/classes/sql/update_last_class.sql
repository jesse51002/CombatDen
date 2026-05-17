UPDATE members
SET last_class = ch.occurred_at
FROM class_history ch
WHERE members.member_id = :member_id
  AND ch.class_history_id = :class_history_id
  AND (members.last_class IS NULL OR ch.occurred_at > members.last_class)
