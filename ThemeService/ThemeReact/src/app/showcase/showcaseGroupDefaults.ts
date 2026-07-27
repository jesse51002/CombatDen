// Ports ../../../../../CRM/lib/showcase/showcase_group_defaults.dart.
//
// Group-aware showcase defaults: one representative gym's classes and rewards
// per parent group, using the real image URLs from VideoService's `gyms/*.yaml`
// files. There is NO runtime dependency on the video service — these are
// constants extracted from the YAML at build time, and they are the LAST-RESORT
// offline fallback beneath ../data/showcaseDefaults.ts's live fetch.
//
// Image hosts:
//   * Class photos  — images.pexels.com (Pexels, activity/people-safe)
//   * Reward photos — a mix of Pexels (t-shirt) and upload.wikimedia.org
//     (bring-a-friend, group-specific gear, PT session)
//
// Representative gym per group (from VideoService/gyms/*.yaml):
//   Fighting -> boxing.yaml            Yoga     -> vinyasa.yaml
//   Pilates  -> reformer_classical.yaml Barre   -> classic_barre.yaml
//   HIIT     -> crossfit.yaml          Cardio   -> indoor_cycling.yaml
//   Dance    -> dance_fitness.yaml     Wellness -> breathwork.yaml
//
// Slot count is 4 everywhere (every VideoService gym has exactly 4 classes and
// 4 rewards). Time slots are synthesised by ./home/homeScheduleGenerator.ts, so
// only name / instructorName / imageUrl are carried here.

import type { ShowcaseClassInfo, ShowcaseReward } from './showcaseContent';

/**
 * The fallback group used when no gym is selected (always, in this public
 * browser) or when a discipline slug is absent from `DISCIPLINE_TO_GROUP`.
 * Matches the historical fighting-only bundled fallback.
 */
export const DEFAULT_SHOWCASE_GROUP = 'Fighting';

/**
 * Every VideoService discipline slug (the `gym_id` in `gyms/*.yaml`) mapped to
 * its parent group. Exhaustive over all 76 disciplines.
 */
export const DISCIPLINE_TO_GROUP: Readonly<Record<string, string>> = Object.freeze({
  // Fighting
  'mma': 'Fighting',
  'boxing': 'Fighting',
  'muay_thai': 'Fighting',
  'kickboxing': 'Fighting',
  'bjj_gi': 'Fighting',
  'no_gi_grappling': 'Fighting',
  'karate': 'Fighting',
  'taekwondo': 'Fighting',
  'krav_maga': 'Fighting',
  // Yoga
  'vinyasa': 'Yoga',
  'hatha': 'Yoga',
  'ashtanga': 'Yoga',
  'iyengar': 'Yoga',
  'bikram_hot': 'Yoga',
  'modern_hot': 'Yoga',
  'power_yoga': 'Yoga',
  'yin_restorative': 'Yoga',
  'yoga_meditation': 'Yoga',
  'aerial_yoga': 'Yoga',
  'acro_yoga': 'Yoga',
  'prenatal_yoga': 'Yoga',
  // Pilates
  'reformer_classical': 'Pilates',
  'reformer_contemporary': 'Pilates',
  'pilates_cardio': 'Pilates',
  'mat_pilates': 'Pilates',
  'lagree_megaformer': 'Pilates',
  'hot_pilates': 'Pilates',
  'pilates_boxing': 'Pilates',
  'pilates_barre': 'Pilates',
  'pilates_sculpt': 'Pilates',
  'prenatal_pilates': 'Pilates',
  // Barre
  'classic_barre': 'Barre',
  'flow_barre': 'Barre',
  'cardio_barre': 'Barre',
  'dance_barre': 'Barre',
  'barre_yoga': 'Barre',
  // HIIT
  'crossfit': 'HIIT',
  'functional_fitness': 'HIIT',
  'group_pt': 'HIIT',
  'bootcamp': 'HIIT',
  'f45': 'HIIT',
  'bft': 'HIIT',
  'orangetheory': 'HIIT',
  'hyrox': 'HIIT',
  'calisthenics': 'HIIT',
  'kettlebell': 'HIIT',
  'powerlifting': 'HIIT',
  'olympic_weightlifting': 'HIIT',
  'strongman': 'HIIT',
  'tactical_fitness': 'HIIT',
  'trx_suspension': 'HIIT',
  // Cardio
  'indoor_cycling': 'Cardio',
  'sprint_cycling': 'Cardio',
  'power_cycling': 'Cardio',
  'spin_strength': 'Cardio',
  'aqua_cycling': 'Cardio',
  'rowing': 'Cardio',
  'running': 'Cardio',
  'treadmill': 'Cardio',
  'tread_strength': 'Cardio',
  'stair_climber': 'Cardio',
  'versaclimber': 'Cardio',
  'trampoline': 'Cardio',
  'cardio_boxing': 'Cardio',
  'cardio_circuit': 'Cardio',
  'dance_cardio': 'Cardio',
  // Dance
  'dance_fitness': 'Dance',
  'ballet': 'Dance',
  'hip_hop': 'Dance',
  'pole': 'Dance',
  'aerial_silks': 'Dance',
  // Wellness
  'breathwork': 'Wellness',
  'meditation': 'Wellness',
  'mobility_recovery': 'Wellness',
  'stretch': 'Wellness',
  'sauna_cold_plunge': 'Wellness',
});

/** The parent group for `videoGymId`, falling back to `DEFAULT_SHOWCASE_GROUP`. */
export function showcaseGroupFor(videoGymId: string | null | undefined): string {
  if (videoGymId === null || videoGymId === undefined) return DEFAULT_SHOWCASE_GROUP;
  return DISCIPLINE_TO_GROUP[videoGymId] ?? DEFAULT_SHOWCASE_GROUP;
}

// ---------------------------------------------------------------------------
// Per-group default classes
// ---------------------------------------------------------------------------

export const SHOWCASE_CLASSES_BY_GROUP: Readonly<
  Record<string, readonly ShowcaseClassInfo[]>
> = Object.freeze({
  Fighting: [
    {
      name: 'Foundation',
      instructorName: 'Coach James Carter',
      imageUrl:
        'https://images.pexels.com/photos/7991668/pexels-photo-7991668.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'Heavy Bag Power',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl:
        'https://images.pexels.com/photos/6296002/pexels-photo-6296002.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'Defense & Footwork',
      instructorName: 'Coach Daniel Brooks',
      imageUrl:
        'https://images.pexels.com/photos/4761788/pexels-photo-4761788.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'Sparring Essentials',
      instructorName: 'Coach Maya Bennett',
      imageUrl:
        'https://images.pexels.com/photos/7991616/pexels-photo-7991616.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
  ],
  Yoga: [
    {
      name: 'Sunrise Flow',
      instructorName: 'Coach James Carter',
      imageUrl:
        'https://images.pexels.com/photos/8436589/pexels-photo-8436589.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'Power Vinyasa',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl:
        'https://images.pexels.com/photos/8436587/pexels-photo-8436587.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'Slow Flow',
      instructorName: 'Coach Daniel Brooks',
      imageUrl:
        'https://images.pexels.com/photos/8436426/pexels-photo-8436426.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'Core Flow',
      instructorName: 'Coach Maya Bennett',
      imageUrl:
        'https://images.pexels.com/photos/8436605/pexels-photo-8436605.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
  ],
  Pilates: [
    {
      name: 'Foundational Order',
      instructorName: 'Coach James Carter',
      imageUrl:
        'https://images.pexels.com/photos/25599825/pexels-photo-25599825.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'Core & Stability',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl:
        'https://images.pexels.com/photos/18136885/pexels-photo-18136885.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'Box Series Mastery',
      instructorName: 'Coach Daniel Brooks',
      imageUrl:
        'https://images.pexels.com/photos/18136886/pexels-photo-18136886.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'Advanced Stretches',
      instructorName: 'Coach Maya Bennett',
      imageUrl:
        'https://images.pexels.com/photos/18136888/pexels-photo-18136888.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
  ],
  Barre: [
    {
      name: 'Barre Essentials',
      instructorName: 'Coach James Carter',
      imageUrl:
        'https://images.pexels.com/photos/7319689/pexels-photo-7319689.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'Rhythmic Fusion',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl:
        'https://images.pexels.com/photos/7319749/pexels-photo-7319749.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'Mindful Endurance',
      instructorName: 'Coach Daniel Brooks',
      imageUrl:
        'https://images.pexels.com/photos/6311672/pexels-photo-6311672.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'Precision Performance',
      instructorName: 'Coach Maya Bennett',
      imageUrl:
        'https://images.pexels.com/photos/6311718/pexels-photo-6311718.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
  ],
  HIIT: [
    {
      name: 'Olympic Lifting Fundamentals',
      instructorName: 'Coach James Carter',
      imageUrl:
        'https://images.pexels.com/photos/4662333/pexels-photo-4662333.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'Core & Gymnastics Strength',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl:
        'https://images.pexels.com/photos/9958667/pexels-photo-9958667.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'Metabolic Conditioning',
      instructorName: 'Coach Daniel Brooks',
      imageUrl:
        'https://images.pexels.com/photos/4720230/pexels-photo-4720230.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'Strength & Injury Prevention',
      instructorName: 'Coach Maya Bennett',
      imageUrl:
        'https://images.pexels.com/photos/8381747/pexels-photo-8381747.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
  ],
  Cardio: [
    {
      name: 'Beat Drop Power',
      instructorName: 'Coach James Carter',
      imageUrl:
        'https://images.pexels.com/photos/264084/pexels-photo-264084.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'Endurance Flow',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl:
        'https://images.pexels.com/photos/4162595/pexels-photo-4162595.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'Interval Ignite',
      instructorName: 'Coach Daniel Brooks',
      imageUrl:
        'https://images.pexels.com/photos/5851030/pexels-photo-5851030.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'Fundamentals Ride',
      instructorName: 'Coach Maya Bennett',
      imageUrl:
        'https://images.pexels.com/photos/26655637/pexels-photo-26655637.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
  ],
  Dance: [
    {
      name: 'Barre Foundations',
      instructorName: 'Coach James Carter',
      imageUrl:
        'https://images.pexels.com/photos/12312/pexels-photo-12312.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'Rhythm & Movement',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl:
        'https://images.pexels.com/photos/3775566/pexels-photo-3775566.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'High Energy Cardio',
      instructorName: 'Coach Daniel Brooks',
      imageUrl:
        'https://images.pexels.com/photos/8957645/pexels-photo-8957645.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'Groove & Flow',
      instructorName: 'Coach Maya Bennett',
      imageUrl:
        'https://images.pexels.com/photos/12086690/pexels-photo-12086690.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
  ],
  Wellness: [
    {
      name: 'Foundational Breathing',
      instructorName: 'Coach James Carter',
      imageUrl:
        'https://images.pexels.com/photos/7596956/pexels-photo-7596956.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'Nervous System Reset',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl:
        'https://images.pexels.com/photos/8436490/pexels-photo-8436490.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'Performance Breathing',
      instructorName: 'Coach Daniel Brooks',
      imageUrl:
        'https://images.pexels.com/photos/8436587/pexels-photo-8436587.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      name: 'Sleep & Recovery',
      instructorName: 'Coach Maya Bennett',
      imageUrl:
        'https://images.pexels.com/photos/8436426/pexels-photo-8436426.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
  ],
});

// ---------------------------------------------------------------------------
// Per-group default rewards
// ---------------------------------------------------------------------------
// 4 items per group, matching the VideoService 4-reward standard.
// Bring-a-friend and the club t-shirt are shared across every group; the third
// item is group-specific gear; the fourth is a PT session.

export const SHOWCASE_REWARDS_BY_GROUP: Readonly<
  Record<string, readonly ShowcaseReward[]>
> = Object.freeze({
  Fighting: [
    {
      title: 'Bring a friend',
      priceLabel: 'Free',
      pointsCost: 1000,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/3/38/Two_people_in_a_gym_using_BOSU_balls.jpg',
    },
    {
      title: 'Club t-shirt',
      priceLabel: 'Free',
      pointsCost: 1500,
      imageUrl:
        'https://images.pexels.com/photos/5746087/pexels-photo-5746087.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      title: 'Boxing gloves',
      priceLabel: '25% off',
      pointsCost: 2000,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/c/c8/Boxing_gloves_Bail_10-OZ_%281%29.jpg',
    },
    {
      title: '1-on-1 PT session',
      priceLabel: '50% off',
      pointsCost: 2500,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/0/01/Personal_trainer_monitoring_a_client%27s_movement_during_a_fitball_exercise.JPG',
    },
  ],
  Yoga: [
    {
      title: 'Bring a friend',
      priceLabel: 'Free',
      pointsCost: 1000,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/3/38/Two_people_in_a_gym_using_BOSU_balls.jpg',
    },
    {
      title: 'Club t-shirt',
      priceLabel: 'Free',
      pointsCost: 1500,
      imageUrl:
        'https://images.pexels.com/photos/5746087/pexels-photo-5746087.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      title: 'Yoga mat',
      priceLabel: '25% off',
      pointsCost: 2000,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/6/68/Fitness_mats_%2851543374690%29.jpg',
    },
    {
      title: '1-on-1 PT session',
      priceLabel: '50% off',
      pointsCost: 2500,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/0/01/Personal_trainer_monitoring_a_client%27s_movement_during_a_fitball_exercise.JPG',
    },
  ],
  Pilates: [
    {
      title: 'Bring a friend',
      priceLabel: 'Free',
      pointsCost: 1000,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/3/38/Two_people_in_a_gym_using_BOSU_balls.jpg',
    },
    {
      title: 'Club t-shirt',
      priceLabel: 'Free',
      pointsCost: 1500,
      imageUrl:
        'https://images.pexels.com/photos/5746087/pexels-photo-5746087.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      title: 'Grip socks',
      priceLabel: '25% off',
      pointsCost: 2000,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/8/81/Halksockar.JPG',
    },
    {
      title: '1-on-1 PT session',
      priceLabel: '50% off',
      pointsCost: 2500,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/0/01/Personal_trainer_monitoring_a_client%27s_movement_during_a_fitball_exercise.JPG',
    },
  ],
  Barre: [
    {
      title: 'Bring a friend',
      priceLabel: 'Free',
      pointsCost: 1000,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/3/38/Two_people_in_a_gym_using_BOSU_balls.jpg',
    },
    {
      title: 'Club t-shirt',
      priceLabel: 'Free',
      pointsCost: 1500,
      imageUrl:
        'https://images.pexels.com/photos/5746087/pexels-photo-5746087.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      title: 'Grip socks',
      priceLabel: '25% off',
      pointsCost: 2000,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/8/81/Halksockar.JPG',
    },
    {
      title: '1-on-1 PT session',
      priceLabel: '50% off',
      pointsCost: 2500,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/0/01/Personal_trainer_monitoring_a_client%27s_movement_during_a_fitball_exercise.JPG',
    },
  ],
  HIIT: [
    {
      title: 'Bring a friend',
      priceLabel: 'Free',
      pointsCost: 1000,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/3/38/Two_people_in_a_gym_using_BOSU_balls.jpg',
    },
    {
      title: 'Club t-shirt',
      priceLabel: 'Free',
      pointsCost: 1500,
      imageUrl:
        'https://images.pexels.com/photos/5746087/pexels-photo-5746087.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      title: 'Jump rope',
      priceLabel: '25% off',
      pointsCost: 2000,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/f/fd/BeadedRope.jpg',
    },
    {
      title: '1-on-1 PT session',
      priceLabel: '50% off',
      pointsCost: 2500,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/0/01/Personal_trainer_monitoring_a_client%27s_movement_during_a_fitball_exercise.JPG',
    },
  ],
  Cardio: [
    {
      title: 'Bring a friend',
      priceLabel: 'Free',
      pointsCost: 1000,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/3/38/Two_people_in_a_gym_using_BOSU_balls.jpg',
    },
    {
      title: 'Club t-shirt',
      priceLabel: 'Free',
      pointsCost: 1500,
      imageUrl:
        'https://images.pexels.com/photos/5746087/pexels-photo-5746087.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      title: 'Cycling shoes',
      priceLabel: '25% off',
      pointsCost: 2000,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/4/4d/Paar_wielerschoenen%2C_S-Phyre%2C_Annemiek_Van_Vleuten%2C_2020_-_overzicht-1_%28WU3762_-_collectie_KOERS._Museum_van_de_Wielersport%29.jpg',
    },
    {
      title: '1-on-1 PT session',
      priceLabel: '50% off',
      pointsCost: 2500,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/0/01/Personal_trainer_monitoring_a_client%27s_movement_during_a_fitball_exercise.JPG',
    },
  ],
  Dance: [
    {
      title: 'Bring a friend',
      priceLabel: 'Free',
      pointsCost: 1000,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/3/38/Two_people_in_a_gym_using_BOSU_balls.jpg',
    },
    {
      title: 'Club t-shirt',
      priceLabel: 'Free',
      pointsCost: 1500,
      imageUrl:
        'https://images.pexels.com/photos/5746087/pexels-photo-5746087.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      title: 'Water bottle',
      priceLabel: '25% off',
      pointsCost: 2000,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/4/45/Metal_Water_Bottles.jpeg',
    },
    {
      title: '1-on-1 PT session',
      priceLabel: '50% off',
      pointsCost: 2500,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/0/01/Personal_trainer_monitoring_a_client%27s_movement_during_a_fitball_exercise.JPG',
    },
  ],
  Wellness: [
    {
      title: 'Bring a friend',
      priceLabel: 'Free',
      pointsCost: 1000,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/3/38/Two_people_in_a_gym_using_BOSU_balls.jpg',
    },
    {
      title: 'Club t-shirt',
      priceLabel: 'Free',
      pointsCost: 1500,
      imageUrl:
        'https://images.pexels.com/photos/5746087/pexels-photo-5746087.jpeg?auto=compress&cs=tinysrgb&w=1200',
    },
    {
      title: 'Yoga mat',
      priceLabel: '25% off',
      pointsCost: 2000,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/6/68/Fitness_mats_%2851543374690%29.jpg',
    },
    {
      title: '1-on-1 PT session',
      priceLabel: '50% off',
      pointsCost: 2500,
      imageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/0/01/Personal_trainer_monitoring_a_client%27s_movement_during_a_fitball_exercise.JPG',
    },
  ],
});

/**
 * The bundled classes for `category`, falling back to the default group. Never
 * empty: every group carries four.
 */
export function bundledClasses(category: string | null): readonly ShowcaseClassInfo[] {
  const key = category ?? DEFAULT_SHOWCASE_GROUP;
  return (
    SHOWCASE_CLASSES_BY_GROUP[key] ??
    SHOWCASE_CLASSES_BY_GROUP[DEFAULT_SHOWCASE_GROUP] ??
    []
  );
}

/** The bundled rewards for `category`, falling back to the default group. */
export function bundledRewards(category: string | null): readonly ShowcaseReward[] {
  const key = category ?? DEFAULT_SHOWCASE_GROUP;
  return (
    SHOWCASE_REWARDS_BY_GROUP[key] ??
    SHOWCASE_REWARDS_BY_GROUP[DEFAULT_SHOWCASE_GROUP] ??
    []
  );
}
