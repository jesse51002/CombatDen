SELECT
    crm_user_id,
    first_name,
    last_name,
    photo_url
FROM user_gym_profiles
WHERE gym_id = :gym_id
