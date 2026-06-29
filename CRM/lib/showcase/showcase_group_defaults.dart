/// Group-aware showcase defaults: one representative gym's classes and rewards
/// per parent group, using the real image URLs from VideoService's
/// gyms/*.yaml files. No runtime dependency on the video service — these
/// are constants extracted from the YAML files at build time.
///
/// Image hosts:
///   • Class photos  — images.pexels.com (Pexels, activity/people-safe)
///   • Reward photos — mix of Pexels (t-shirt) and upload.wikimedia.org
///     (bring-a-friend, group-specific items, PT session)
library;

import 'package:crm/showcase/showcase_content.dart';

/// The fallback group used when no gym is selected (v2 landing page) or
/// when the selected discipline slug is absent from [kDisciplineToGroup].
/// Matches the historical fighting-only bundled fallback.
const String kDefaultShowcaseGroup = 'Fighting';

/// Maps every VideoService discipline slug (the `gym_id` in gyms/*.yaml)
/// to its parent group. Exhaustive over all 76 disciplines.
const Map<String, String> kDisciplineToGroup = {
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
};

/// Returns the parent group for [videoGymId], falling back to
/// [kDefaultShowcaseGroup] when the slug is null or unrecognised.
String showcaseGroupFor(String? videoGymId) =>
    kDisciplineToGroup[videoGymId] ?? kDefaultShowcaseGroup;

// ---------------------------------------------------------------------------
// Per-group default classes
// ---------------------------------------------------------------------------
// Representative gym per group (from VideoService/gyms/*.yaml):
//   Fighting → boxing.yaml   Yoga → vinyasa.yaml
//   Pilates → reformer_classical.yaml   Barre → classic_barre.yaml
//   HIIT → crossfit.yaml   Cardio → indoor_cycling.yaml
//   Dance → dance_fitness.yaml   Wellness → breathwork.yaml
//
// Slot count is 4 (all VideoService gyms have exactly 4 classes).
// Time slots are synthesised by the schedule generator — gym files carry
// no schedule — so only name / instructorName / imageUrl are needed here.

const Map<String, List<ShowcaseClassInfo>> kShowcaseClassesByGroup = {
  'Fighting': [
    ShowcaseClassInfo(
      name: 'Foundation',
      instructorName: 'Coach James Carter',
      imageUrl: 'https://images.pexels.com/photos/7991668/pexels-photo-7991668.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'Heavy Bag Power',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl: 'https://images.pexels.com/photos/6296002/pexels-photo-6296002.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'Defense & Footwork',
      instructorName: 'Coach Daniel Brooks',
      imageUrl: 'https://images.pexels.com/photos/4761788/pexels-photo-4761788.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'Sparring Essentials',
      instructorName: 'Coach Maya Bennett',
      imageUrl: 'https://images.pexels.com/photos/7991616/pexels-photo-7991616.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
  ],
  'Yoga': [
    ShowcaseClassInfo(
      name: 'Sunrise Flow',
      instructorName: 'Coach James Carter',
      imageUrl: 'https://images.pexels.com/photos/8436589/pexels-photo-8436589.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'Power Vinyasa',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl: 'https://images.pexels.com/photos/8436587/pexels-photo-8436587.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'Slow Flow',
      instructorName: 'Coach Daniel Brooks',
      imageUrl: 'https://images.pexels.com/photos/8436426/pexels-photo-8436426.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'Core Flow',
      instructorName: 'Coach Maya Bennett',
      imageUrl: 'https://images.pexels.com/photos/8436605/pexels-photo-8436605.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
  ],
  'Pilates': [
    ShowcaseClassInfo(
      name: 'Foundational Order',
      instructorName: 'Coach James Carter',
      imageUrl: 'https://images.pexels.com/photos/25599825/pexels-photo-25599825.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'Core & Stability',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl: 'https://images.pexels.com/photos/18136885/pexels-photo-18136885.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'Box Series Mastery',
      instructorName: 'Coach Daniel Brooks',
      imageUrl: 'https://images.pexels.com/photos/18136886/pexels-photo-18136886.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'Advanced Stretches',
      instructorName: 'Coach Maya Bennett',
      imageUrl: 'https://images.pexels.com/photos/18136888/pexels-photo-18136888.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
  ],
  'Barre': [
    ShowcaseClassInfo(
      name: 'Barre Essentials',
      instructorName: 'Coach James Carter',
      imageUrl: 'https://images.pexels.com/photos/7319689/pexels-photo-7319689.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'Rhythmic Fusion',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl: 'https://images.pexels.com/photos/7319749/pexels-photo-7319749.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'Mindful Endurance',
      instructorName: 'Coach Daniel Brooks',
      imageUrl: 'https://images.pexels.com/photos/6311672/pexels-photo-6311672.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'Precision Performance',
      instructorName: 'Coach Maya Bennett',
      imageUrl: 'https://images.pexels.com/photos/6311718/pexels-photo-6311718.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
  ],
  'HIIT': [
    ShowcaseClassInfo(
      name: 'Olympic Lifting Fundamentals',
      instructorName: 'Coach James Carter',
      imageUrl: 'https://images.pexels.com/photos/4662333/pexels-photo-4662333.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'Core & Gymnastics Strength',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl: 'https://images.pexels.com/photos/9958667/pexels-photo-9958667.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'Metabolic Conditioning',
      instructorName: 'Coach Daniel Brooks',
      imageUrl: 'https://images.pexels.com/photos/4720230/pexels-photo-4720230.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'Strength & Injury Prevention',
      instructorName: 'Coach Maya Bennett',
      imageUrl: 'https://images.pexels.com/photos/8381747/pexels-photo-8381747.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
  ],
  'Cardio': [
    ShowcaseClassInfo(
      name: 'Beat Drop Power',
      instructorName: 'Coach James Carter',
      imageUrl: 'https://images.pexels.com/photos/264084/pexels-photo-264084.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'Endurance Flow',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl: 'https://images.pexels.com/photos/4162595/pexels-photo-4162595.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'Interval Ignite',
      instructorName: 'Coach Daniel Brooks',
      imageUrl: 'https://images.pexels.com/photos/5851030/pexels-photo-5851030.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'Fundamentals Ride',
      instructorName: 'Coach Maya Bennett',
      imageUrl: 'https://images.pexels.com/photos/26655637/pexels-photo-26655637.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
  ],
  'Dance': [
    ShowcaseClassInfo(
      name: 'Barre Foundations',
      instructorName: 'Coach James Carter',
      imageUrl: 'https://images.pexels.com/photos/12312/pexels-photo-12312.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'Rhythm & Movement',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl: 'https://images.pexels.com/photos/3775566/pexels-photo-3775566.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'High Energy Cardio',
      instructorName: 'Coach Daniel Brooks',
      imageUrl: 'https://images.pexels.com/photos/8957645/pexels-photo-8957645.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'Groove & Flow',
      instructorName: 'Coach Maya Bennett',
      imageUrl: 'https://images.pexels.com/photos/12086690/pexels-photo-12086690.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
  ],
  'Wellness': [
    ShowcaseClassInfo(
      name: 'Foundational Breathing',
      instructorName: 'Coach James Carter',
      imageUrl: 'https://images.pexels.com/photos/7596956/pexels-photo-7596956.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'Nervous System Reset',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl: 'https://images.pexels.com/photos/8436490/pexels-photo-8436490.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'Performance Breathing',
      instructorName: 'Coach Daniel Brooks',
      imageUrl: 'https://images.pexels.com/photos/8436587/pexels-photo-8436587.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseClassInfo(
      name: 'Sleep & Recovery',
      instructorName: 'Coach Maya Bennett',
      imageUrl: 'https://images.pexels.com/photos/8436426/pexels-photo-8436426.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
  ],
};

// ---------------------------------------------------------------------------
// Per-group default rewards
// ---------------------------------------------------------------------------
// 4 items per group — matching the VideoService 4-reward standard.
// Bring-a-friend and club t-shirt are shared across all groups; the
// third item is group-specific gear; the fourth is a PT session.

const Map<String, List<ShowcaseReward>> kShowcaseRewardsByGroup = {
  'Fighting': [
    ShowcaseReward(
      title: 'Bring a friend',
      priceLabel: 'Free',
      pointsCost: 1000,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/3/38/Two_people_in_a_gym_using_BOSU_balls.jpg',
    ),
    ShowcaseReward(
      title: 'Club t-shirt',
      priceLabel: 'Free',
      pointsCost: 1500,
      imageUrl: 'https://images.pexels.com/photos/5746087/pexels-photo-5746087.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseReward(
      title: 'Boxing gloves',
      priceLabel: '25% off',
      pointsCost: 2000,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/c/c8/Boxing_gloves_Bail_10-OZ_%281%29.jpg',
    ),
    ShowcaseReward(
      title: '1-on-1 PT session',
      priceLabel: '50% off',
      pointsCost: 2500,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/0/01/Personal_trainer_monitoring_a_client%27s_movement_during_a_fitball_exercise.JPG',
    ),
  ],
  'Yoga': [
    ShowcaseReward(
      title: 'Bring a friend',
      priceLabel: 'Free',
      pointsCost: 1000,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/3/38/Two_people_in_a_gym_using_BOSU_balls.jpg',
    ),
    ShowcaseReward(
      title: 'Club t-shirt',
      priceLabel: 'Free',
      pointsCost: 1500,
      imageUrl: 'https://images.pexels.com/photos/5746087/pexels-photo-5746087.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseReward(
      title: 'Yoga mat',
      priceLabel: '25% off',
      pointsCost: 2000,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/6/68/Fitness_mats_%2851543374690%29.jpg',
    ),
    ShowcaseReward(
      title: '1-on-1 PT session',
      priceLabel: '50% off',
      pointsCost: 2500,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/0/01/Personal_trainer_monitoring_a_client%27s_movement_during_a_fitball_exercise.JPG',
    ),
  ],
  'Pilates': [
    ShowcaseReward(
      title: 'Bring a friend',
      priceLabel: 'Free',
      pointsCost: 1000,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/3/38/Two_people_in_a_gym_using_BOSU_balls.jpg',
    ),
    ShowcaseReward(
      title: 'Club t-shirt',
      priceLabel: 'Free',
      pointsCost: 1500,
      imageUrl: 'https://images.pexels.com/photos/5746087/pexels-photo-5746087.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseReward(
      title: 'Grip socks',
      priceLabel: '25% off',
      pointsCost: 2000,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/8/81/Halksockar.JPG',
    ),
    ShowcaseReward(
      title: '1-on-1 PT session',
      priceLabel: '50% off',
      pointsCost: 2500,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/0/01/Personal_trainer_monitoring_a_client%27s_movement_during_a_fitball_exercise.JPG',
    ),
  ],
  'Barre': [
    ShowcaseReward(
      title: 'Bring a friend',
      priceLabel: 'Free',
      pointsCost: 1000,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/3/38/Two_people_in_a_gym_using_BOSU_balls.jpg',
    ),
    ShowcaseReward(
      title: 'Club t-shirt',
      priceLabel: 'Free',
      pointsCost: 1500,
      imageUrl: 'https://images.pexels.com/photos/5746087/pexels-photo-5746087.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseReward(
      title: 'Grip socks',
      priceLabel: '25% off',
      pointsCost: 2000,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/8/81/Halksockar.JPG',
    ),
    ShowcaseReward(
      title: '1-on-1 PT session',
      priceLabel: '50% off',
      pointsCost: 2500,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/0/01/Personal_trainer_monitoring_a_client%27s_movement_during_a_fitball_exercise.JPG',
    ),
  ],
  'HIIT': [
    ShowcaseReward(
      title: 'Bring a friend',
      priceLabel: 'Free',
      pointsCost: 1000,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/3/38/Two_people_in_a_gym_using_BOSU_balls.jpg',
    ),
    ShowcaseReward(
      title: 'Club t-shirt',
      priceLabel: 'Free',
      pointsCost: 1500,
      imageUrl: 'https://images.pexels.com/photos/5746087/pexels-photo-5746087.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseReward(
      title: 'Jump rope',
      priceLabel: '25% off',
      pointsCost: 2000,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/f/fd/BeadedRope.jpg',
    ),
    ShowcaseReward(
      title: '1-on-1 PT session',
      priceLabel: '50% off',
      pointsCost: 2500,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/0/01/Personal_trainer_monitoring_a_client%27s_movement_during_a_fitball_exercise.JPG',
    ),
  ],
  'Cardio': [
    ShowcaseReward(
      title: 'Bring a friend',
      priceLabel: 'Free',
      pointsCost: 1000,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/3/38/Two_people_in_a_gym_using_BOSU_balls.jpg',
    ),
    ShowcaseReward(
      title: 'Club t-shirt',
      priceLabel: 'Free',
      pointsCost: 1500,
      imageUrl: 'https://images.pexels.com/photos/5746087/pexels-photo-5746087.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseReward(
      title: 'Cycling shoes',
      priceLabel: '25% off',
      pointsCost: 2000,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/4/4d/Paar_wielerschoenen%2C_S-Phyre%2C_Annemiek_Van_Vleuten%2C_2020_-_overzicht-1_%28WU3762_-_collectie_KOERS._Museum_van_de_Wielersport%29.jpg',
    ),
    ShowcaseReward(
      title: '1-on-1 PT session',
      priceLabel: '50% off',
      pointsCost: 2500,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/0/01/Personal_trainer_monitoring_a_client%27s_movement_during_a_fitball_exercise.JPG',
    ),
  ],
  'Dance': [
    ShowcaseReward(
      title: 'Bring a friend',
      priceLabel: 'Free',
      pointsCost: 1000,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/3/38/Two_people_in_a_gym_using_BOSU_balls.jpg',
    ),
    ShowcaseReward(
      title: 'Club t-shirt',
      priceLabel: 'Free',
      pointsCost: 1500,
      imageUrl: 'https://images.pexels.com/photos/5746087/pexels-photo-5746087.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseReward(
      title: 'Water bottle',
      priceLabel: '25% off',
      pointsCost: 2000,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/4/45/Metal_Water_Bottles.jpeg',
    ),
    ShowcaseReward(
      title: '1-on-1 PT session',
      priceLabel: '50% off',
      pointsCost: 2500,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/0/01/Personal_trainer_monitoring_a_client%27s_movement_during_a_fitball_exercise.JPG',
    ),
  ],
  'Wellness': [
    ShowcaseReward(
      title: 'Bring a friend',
      priceLabel: 'Free',
      pointsCost: 1000,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/3/38/Two_people_in_a_gym_using_BOSU_balls.jpg',
    ),
    ShowcaseReward(
      title: 'Club t-shirt',
      priceLabel: 'Free',
      pointsCost: 1500,
      imageUrl: 'https://images.pexels.com/photos/5746087/pexels-photo-5746087.jpeg?auto=compress&cs=tinysrgb&w=1200',
    ),
    ShowcaseReward(
      title: 'Yoga mat',
      priceLabel: '25% off',
      pointsCost: 2000,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/6/68/Fitness_mats_%2851543374690%29.jpg',
    ),
    ShowcaseReward(
      title: '1-on-1 PT session',
      priceLabel: '50% off',
      pointsCost: 2500,
      imageUrl: 'https://upload.wikimedia.org/wikipedia/commons/0/01/Personal_trainer_monitoring_a_client%27s_movement_during_a_fitball_exercise.JPG',
    ),
  ],
};
