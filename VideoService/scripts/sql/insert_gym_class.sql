INSERT INTO template_gym_class (
    gym_id, name, image_url, description,
    instructor_name, instructor_bio, instructor_image_url
)
VALUES (
    :gym_id, :name, :image_url, :description,
    :instructor_name, :instructor_bio, :instructor_image_url
)
