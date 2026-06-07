UPDATE members
SET {set_clause}
WHERE member_id = :member_id
RETURNING
    member_id,
    gym_id,
    user_id,
    first_name,
    last_name,
    email,
    points_balance,
    last_class,
    current_rank_id,
    created_at,
    phone,
    address,
    emergency_contact_name,
    emergency_contact_phone,
    emergency_contact_email,
    photo_url
