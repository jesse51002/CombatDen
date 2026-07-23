-- Every gym the hourly growth compute iterates. No filter: a gym with no
-- members still gets well-formed empty payloads, so the CRM never renders a
-- half-populated page.
SELECT gym_id
FROM gyms
ORDER BY gym_id
