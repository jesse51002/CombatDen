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
// 4 rewards). Time slots are NOT carried — a gym file has no schedule, so
// ./home/homeScheduleGenerator.ts synthesises them (and the attending counts)
// deterministically.
//
// Each class carries its `description`, `instructor_bio` and
// `instructor_image_url` alongside the three the schedule needs, because the
// class DETAIL screen (./classdetail/) renders all six. The instructor roster
// is deliberately identical across all eight groups — one shared cast of four
// coaches — which is how the gym files themselves are written: all 76 share it.
//
// THE THIRD MAP LIVES NEXT DOOR. The per-group VIDEO feeds are the same kind of
// constant with the same provenance, but there are ~110 of them against 32
// classes and 32 rewards — enough to bury both maps here — so they sit in
// ./showcaseVideoDefaults.ts. `DEFAULT_SHOWCASE_GROUP` and the group set below
// stay the single source of truth for all three; that module imports them.

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
      description:
        'Master the fundamentals of proper stance, footwork, and the four basic punches. Ideal for new boxers building a solid technical foundation.',
      instructorBio:
        'Head coach with over a decade of experience helping members of every level train smarter, move better, and stay consistent.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/6/68/Alec_Penix.jpg',
    },
    {
      name: 'Heavy Bag Power',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl:
        'https://images.pexels.com/photos/6296002/pexels-photo-6296002.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'High-intensity heavy bag training focused on power development and cardio conditioning. Expect explosive combinations and real-world striking intensity.',
      instructorBio:
        'Performance coach focused on building strength, mobility, and confidence through approachable, well-structured sessions.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/8/8b/Athlete_portrait_Marianna_Gillespie.jpg',
    },
    {
      name: 'Defense & Footwork',
      instructorName: 'Coach Daniel Brooks',
      imageUrl:
        'https://images.pexels.com/photos/4761788/pexels-photo-4761788.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Develop defensive movement skills including slips, rolls, and parries. Learn to evade punches while maintaining balance and positioning.',
      instructorBio:
        'Certified instructor who breaks every movement down step by step so newcomers and regulars alike feel supported.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/e/e3/Branden_Loera_Headshot.jpg',
    },
    {
      name: 'Sparring Essentials',
      instructorName: 'Coach Maya Bennett',
      imageUrl:
        'https://images.pexels.com/photos/7991616/pexels-photo-7991616.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Controlled sparring practice with emphasis on distance management, timing, and fight IQ. Build confidence in live exchanges with proper safety protocols.',
      instructorBio:
        'Coach passionate about creating an inclusive, high-energy room where members from all backgrounds can thrive.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/2/2e/Torrie_Lewis_for_Signet_Packaging%2C_headshot.jpg',
    },
  ],
  Yoga: [
    {
      name: 'Sunrise Flow',
      instructorName: 'Coach James Carter',
      imageUrl:
        'https://images.pexels.com/photos/8436589/pexels-photo-8436589.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Start your day energized with a guided flow that builds heat and strength through dynamic sun salutations and standing poses. Perfect for setting intention and awakening the body.',
      instructorBio:
        'Head coach with over a decade of experience helping members of every level train smarter, move better, and stay consistent.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/6/68/Alec_Penix.jpg',
    },
    {
      name: 'Power Vinyasa',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl:
        'https://images.pexels.com/photos/8436587/pexels-photo-8436587.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Challenge yourself with a faster-paced flow that emphasizes strength, balance, and breath control. This intermediate-level class builds power and endurance through sustained holds and transitions.',
      instructorBio:
        'Performance coach focused on building strength, mobility, and confidence through approachable, well-structured sessions.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/8/8b/Athlete_portrait_Marianna_Gillespie.jpg',
    },
    {
      name: 'Slow Flow',
      instructorName: 'Coach Daniel Brooks',
      imageUrl:
        'https://images.pexels.com/photos/8436426/pexels-photo-8436426.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Explore deeper stretches and longer holds in this thoughtful, meditative practice. Each pose becomes a moment for reflection and release, leaving you calm and grounded.',
      instructorBio:
        'Certified instructor who breaks every movement down step by step so newcomers and regulars alike feel supported.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/e/e3/Branden_Loera_Headshot.jpg',
    },
    {
      name: 'Core Flow',
      instructorName: 'Coach Maya Bennett',
      imageUrl:
        'https://images.pexels.com/photos/8436605/pexels-photo-8436605.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Build a strong foundation with this accessible flow designed for all levels. Focus on core engagement, proper alignment, and the breath-to-movement connection that makes vinyasa flow feel effortless.',
      instructorBio:
        'Coach passionate about creating an inclusive, high-energy room where members from all backgrounds can thrive.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/2/2e/Torrie_Lewis_for_Signet_Packaging%2C_headshot.jpg',
    },
  ],
  Pilates: [
    {
      name: 'Foundational Order',
      instructorName: 'Coach James Carter',
      imageUrl:
        'https://images.pexels.com/photos/25599825/pexels-photo-25599825.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Learn the classical reformer sequence from the beginning. This class covers footwork, the hundred, and the frog series with proper spring settings and breath control.',
      instructorBio:
        'Head coach with over a decade of experience helping members of every level train smarter, move better, and stay consistent.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/6/68/Alec_Penix.jpg',
    },
    {
      name: 'Core & Stability',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl:
        'https://images.pexels.com/photos/18136885/pexels-photo-18136885.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Deep dive into stomach massage, leg circles, and side-lying core work. Build precision and functional stability through the classical approach to core conditioning.',
      instructorBio:
        'Performance coach focused on building strength, mobility, and confidence through approachable, well-structured sessions.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/8/8b/Athlete_portrait_Marianna_Gillespie.jpg',
    },
    {
      name: 'Box Series Mastery',
      instructorName: 'Coach Daniel Brooks',
      imageUrl:
        'https://images.pexels.com/photos/18136886/pexels-photo-18136886.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Master the short and long box series with attention to classical form. Develop spinal articulation and controlled movement through this dynamic part of the order.',
      instructorBio:
        'Certified instructor who breaks every movement down step by step so newcomers and regulars alike feel supported.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/e/e3/Branden_Loera_Headshot.jpg',
    },
    {
      name: 'Advanced Stretches',
      instructorName: 'Coach Maya Bennett',
      imageUrl:
        'https://images.pexels.com/photos/18136888/pexels-photo-18136888.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Complete the classical session with long stretch series, knee stretches, and flowing transitions. Perfect for refining technique and gaining strength and flexibility.',
      instructorBio:
        'Coach passionate about creating an inclusive, high-energy room where members from all backgrounds can thrive.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/2/2e/Torrie_Lewis_for_Signet_Packaging%2C_headshot.jpg',
    },
  ],
  Barre: [
    {
      name: 'Barre Essentials',
      instructorName: 'Coach James Carter',
      imageUrl:
        'https://images.pexels.com/photos/7319689/pexels-photo-7319689.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Master the fundamentals of pure barre technique, from proper alignment to foundational pulses and holds. Perfect for building strength and confidence at the barre.',
      instructorBio:
        'Head coach with over a decade of experience helping members of every level train smarter, move better, and stay consistent.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/6/68/Alec_Penix.jpg',
    },
    {
      name: 'Rhythmic Fusion',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl:
        'https://images.pexels.com/photos/7319749/pexels-photo-7319749.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Blend traditional barre with contemporary musicality and flowing movement. Build lean strength while enjoying the artistry and rhythm of dance.',
      instructorBio:
        'Performance coach focused on building strength, mobility, and confidence through approachable, well-structured sessions.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/8/8b/Athlete_portrait_Marianna_Gillespie.jpg',
    },
    {
      name: 'Mindful Endurance',
      instructorName: 'Coach Daniel Brooks',
      imageUrl:
        'https://images.pexels.com/photos/6311672/pexels-photo-6311672.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Develop long, lean muscles through sustained, intentional holds and subtle micro-movements that transform your body from within. A class for lasting results.',
      instructorBio:
        'Certified instructor who breaks every movement down step by step so newcomers and regulars alike feel supported.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/e/e3/Branden_Loera_Headshot.jpg',
    },
    {
      name: 'Precision Performance',
      instructorName: 'Coach Maya Bennett',
      imageUrl:
        'https://images.pexels.com/photos/6311718/pexels-photo-6311718.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Experience theatrical energy and exacting form cues as you execute every movement with precision. A high-energy class that refines technique and ignites passion.',
      instructorBio:
        'Coach passionate about creating an inclusive, high-energy room where members from all backgrounds can thrive.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/2/2e/Torrie_Lewis_for_Signet_Packaging%2C_headshot.jpg',
    },
  ],
  HIIT: [
    {
      name: 'Olympic Lifting Fundamentals',
      instructorName: 'Coach James Carter',
      imageUrl:
        'https://images.pexels.com/photos/4662333/pexels-photo-4662333.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Master the essential Olympic lifts — snatch and clean & jerk — with Marcus\'s step-by-step breakdowns. Perfect for building strong technique from the ground up.',
      instructorBio:
        'Head coach with over a decade of experience helping members of every level train smarter, move better, and stay consistent.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/6/68/Alec_Penix.jpg',
    },
    {
      name: 'Core & Gymnastics Strength',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl:
        'https://images.pexels.com/photos/9958667/pexels-photo-9958667.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Build the core strength and body control needed for pull-ups, muscle-ups, and handstand skills. Progressive exercises tailored to your current level.',
      instructorBio:
        'Performance coach focused on building strength, mobility, and confidence through approachable, well-structured sessions.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/8/8b/Athlete_portrait_Marianna_Gillespie.jpg',
    },
    {
      name: 'Metabolic Conditioning',
      instructorName: 'Coach Daniel Brooks',
      imageUrl:
        'https://images.pexels.com/photos/4720230/pexels-photo-4720230.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'High-energy workouts designed to maximize cardio endurance and functional strength. Leave every session feeling accomplished and ready for the next challenge.',
      instructorBio:
        'Certified instructor who breaks every movement down step by step so newcomers and regulars alike feel supported.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/e/e3/Branden_Loera_Headshot.jpg',
    },
    {
      name: 'Strength & Injury Prevention',
      instructorName: 'Coach Maya Bennett',
      imageUrl:
        'https://images.pexels.com/photos/8381747/pexels-photo-8381747.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Train smart with Derek\'s biomechanics-focused approach to sustainable strength building. Learn proper form and injury-prevention strategies for long-term athletic growth.',
      instructorBio:
        'Coach passionate about creating an inclusive, high-energy room where members from all backgrounds can thrive.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/2/2e/Torrie_Lewis_for_Signet_Packaging%2C_headshot.jpg',
    },
  ],
  Cardio: [
    {
      name: 'Beat Drop Power',
      instructorName: 'Coach James Carter',
      imageUrl:
        'https://images.pexels.com/photos/264084/pexels-photo-264084.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'High-energy sprint-focused rides where climbs and explosive bursts are choreographed to track drops. Build raw leg power and cardiovascular capacity in a club-like atmosphere.',
      instructorBio:
        'Head coach with over a decade of experience helping members of every level train smarter, move better, and stay consistent.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/6/68/Alec_Penix.jpg',
    },
    {
      name: 'Endurance Flow',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl:
        'https://images.pexels.com/photos/4162595/pexels-photo-4162595.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Steady-paced, longer rides that build aerobic capacity and mental toughness. Expect rolling hills, sustained climbs, and rhythmic cadence work set to motivational music.',
      instructorBio:
        'Performance coach focused on building strength, mobility, and confidence through approachable, well-structured sessions.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/8/8b/Athlete_portrait_Marianna_Gillespie.jpg',
    },
    {
      name: 'Interval Ignite',
      instructorName: 'Coach Daniel Brooks',
      imageUrl:
        'https://images.pexels.com/photos/5851030/pexels-photo-5851030.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Structured high-intensity intervals mixed with recovery sections. Perfect for riders looking to maximize calorie burn and train like a racer with precision timing and intensity control.',
      instructorBio:
        'Certified instructor who breaks every movement down step by step so newcomers and regulars alike feel supported.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/e/e3/Branden_Loera_Headshot.jpg',
    },
    {
      name: 'Fundamentals Ride',
      instructorName: 'Coach Maya Bennett',
      imageUrl:
        'https://images.pexels.com/photos/26655637/pexels-photo-26655637.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Beginner-friendly class focused on proper bike setup, posture, cadence and resistance control. Learn the foundation of efficient indoor cycling in a welcoming, no-judgment environment.',
      instructorBio:
        'Coach passionate about creating an inclusive, high-energy room where members from all backgrounds can thrive.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/2/2e/Torrie_Lewis_for_Signet_Packaging%2C_headshot.jpg',
    },
  ],
  Dance: [
    {
      name: 'Barre Foundations',
      instructorName: 'Coach James Carter',
      imageUrl:
        'https://images.pexels.com/photos/12312/pexels-photo-12312.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Master proper barre technique and posture alignment with a classically trained instructor. This foundational class builds strength and grace through sustained, controlled movements.',
      instructorBio:
        'Head coach with over a decade of experience helping members of every level train smarter, move better, and stay consistent.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/6/68/Alec_Penix.jpg',
    },
    {
      name: 'Rhythm & Movement',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl:
        'https://images.pexels.com/photos/3775566/pexels-photo-3775566.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Blend barre strength with contemporary choreography in this upbeat, music-driven class. Feel the rhythm while building flexibility and confidence in a supportive studio environment.',
      instructorBio:
        'Performance coach focused on building strength, mobility, and confidence through approachable, well-structured sessions.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/8/8b/Athlete_portrait_Marianna_Gillespie.jpg',
    },
    {
      name: 'High Energy Cardio',
      instructorName: 'Coach Daniel Brooks',
      imageUrl:
        'https://images.pexels.com/photos/8957645/pexels-photo-8957645.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Pump your heart and endurance with fast-paced, sustained barre choreography. This energetic class builds cardiovascular fitness while maintaining beautiful, mindful movement.',
      instructorBio:
        'Certified instructor who breaks every movement down step by step so newcomers and regulars alike feel supported.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/e/e3/Branden_Loera_Headshot.jpg',
    },
    {
      name: 'Groove & Flow',
      instructorName: 'Coach Maya Bennett',
      imageUrl:
        'https://images.pexels.com/photos/12086690/pexels-photo-12086690.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Dance with theatrical energy and precision in this joyful blend of ballet technique and fluid movement. Feel the music and celebrate your body\'s natural rhythm.',
      instructorBio:
        'Coach passionate about creating an inclusive, high-energy room where members from all backgrounds can thrive.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/2/2e/Torrie_Lewis_for_Signet_Packaging%2C_headshot.jpg',
    },
  ],
  Wellness: [
    {
      name: 'Foundational Breathing',
      instructorName: 'Coach James Carter',
      imageUrl:
        'https://images.pexels.com/photos/7596956/pexels-photo-7596956.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Learn core breathing techniques including box breathing, diaphragmatic breathing, and coherent breathing. Perfect for building a solid foundation before exploring advanced practices.',
      instructorBio:
        'Head coach with over a decade of experience helping members of every level train smarter, move better, and stay consistent.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/6/68/Alec_Penix.jpg',
    },
    {
      name: 'Nervous System Reset',
      instructorName: 'Coach Sarah Mitchell',
      imageUrl:
        'https://images.pexels.com/photos/8436490/pexels-photo-8436490.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Guided downregulation practice using extended-exhale and somatic breathing to calm anxiety, reduce stress, and prepare your nervous system for rest and recovery.',
      instructorBio:
        'Performance coach focused on building strength, mobility, and confidence through approachable, well-structured sessions.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/8/8b/Athlete_portrait_Marianna_Gillespie.jpg',
    },
    {
      name: 'Performance Breathing',
      instructorName: 'Coach Daniel Brooks',
      imageUrl:
        'https://images.pexels.com/photos/8436587/pexels-photo-8436587.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Harness your breath for focus, energy, and pre-performance confidence. Explore breathing patterns that activate and energize your system when you need it most.',
      instructorBio:
        'Certified instructor who breaks every movement down step by step so newcomers and regulars alike feel supported.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/e/e3/Branden_Loera_Headshot.jpg',
    },
    {
      name: 'Sleep & Recovery',
      instructorName: 'Coach Maya Bennett',
      imageUrl:
        'https://images.pexels.com/photos/8436426/pexels-photo-8436426.jpeg?auto=compress&cs=tinysrgb&w=1200',
      description:
        'Unwind with gentle breathing and relaxation techniques designed to ease you into deep rest. Ideal for evening practice and winding down before bed.',
      instructorBio:
        'Coach passionate about creating an inclusive, high-energy room where members from all backgrounds can thrive.',
      instructorImageUrl:
        'https://upload.wikimedia.org/wikipedia/commons/2/2e/Torrie_Lewis_for_Signet_Packaging%2C_headshot.jpg',
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
