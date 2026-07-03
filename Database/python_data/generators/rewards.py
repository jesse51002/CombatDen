import random
import uuid

from schema.gym_reward import GymRewardCreate

REWARD_TEMPLATES = [
    {
        "title": "Free T-Shirt",
        "price_label": "Official gym branded tee",
        "point_cost": 200,
        # Club t-shirt image family (reused across VideoService gym templates).
        "image_url": "https://images.pexels.com/photos/5746087/pexels-photo-5746087.jpeg?auto=compress&cs=tinysrgb&w=1200",
    },
    {
        "title": "Private Lesson",
        "price_label": "1-on-1 with an instructor",
        "point_cost": 500,
        # 1-on-1 PT session image family.
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/0/01/Personal_trainer_monitoring_a_client%27s_movement_during_a_fitball_exercise.JPG",
    },
    {
        "title": "Guest Pass",
        "price_label": "Bring a friend for free",
        "point_cost": 100,
        # Bring-a-friend image family.
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/3/38/Two_people_in_a_gym_using_BOSU_balls.jpg",
    },
    {
        "title": "Protein Shake",
        "price_label": "Post-workout recovery",
        "point_cost": 50,
        # No exact drink match in the shared pool; water bottle is the
        # closest hydration/recovery image family.
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/4/45/Metal_Water_Bottles.jpeg",
    },
    {
        "title": "Gym Bag",
        "price_label": "Branded duffel bag",
        "point_cost": 350,
        # No exact bag match; lifting belt is the closest branded-gear image
        # family.
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/5/57/LiftingBeltBrown.png",
    },
    {
        "title": "Competition Entry",
        "price_label": "Free entry to next tournament",
        "point_cost": 400,
        # No exact competition match; running shoes evoke race/competition
        # entry across the shared gym templates.
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/9/98/On_Cloud_Running_Shoes.jpg",
    },
    {
        "title": "Month Extension",
        "price_label": "Add 1 week to membership",
        "point_cost": 300,
        # No physical item to depict; yoga mat is a neutral generic-gym
        # stand-in image family.
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/6/68/Fitness_mats_%2851543374690%29.jpg",
    },
]


def generate(gym_id: uuid.UUID, count: int) -> list[GymRewardCreate]:
    templates = random.sample(REWARD_TEMPLATES, min(count, len(REWARD_TEMPLATES)))
    return [
        GymRewardCreate(
            reward_id=uuid.uuid4(),
            gym_id=gym_id,
            is_active=random.random() > 0.2,
            **t,
        )
        for t in templates
    ]
