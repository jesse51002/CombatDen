# Class-Based Gym Types — Done vs. To Build

**Date:** 2026-05-27
**Status:** DRAFT — production prioritization inventory
**Mode:** Theme-library inventory (not a session)

Concepts touched: [[Class_Based_Gym_Market]], [[Combat_Sports_Gym_Market]], [[Template_Marketplace]], [[Gym_Owner]], [[Fighting_Gym]], [[Brand_Is_Product]].

## Why this doc exists

Theme-library production is in motion. The combat sports beachhead is largely covered. This doc maps what's already shipped to the canonical class-based gym types, then lists the next-priority types to build per remaining category. The per-category counts are founder-set targets reflecting how much breadth that category warrants in the v1 library, not market math.

The broader market frame is in `Business/Office_Hours/2026-05-24-18-Office_Hours_Pricing_Axis_Restructure.md` and the pivot `Business/pivots/2026-05-24-19-icp-premium-class-based-gyms-fighting-as-beachhead.md`. The exhaustive universe brainstorm that preceded this prioritization is in the git history of this same file.

---

## DONE — 7 themes shipped (BJJDen below is planned, not yet produced)

| Theme repo | Canonical type | `gym_type` |
| --- | --- | --- |
| `ApexMMA` | MMA gyms (full-service: striking + grappling + cage work) | `Fighting` |
| `SweetScienceBoxing` | Boxing gyms (traditional / sparring-oriented) | `Fighting` |
| `StrikeKickboxing` | Kickboxing / cardio kickboxing studios | `Fighting` |
| `KillerMuayThai` | Muay Thai gyms (fight-team) | `Fighting` |
| `BJJDen` | Brazilian Jiu-Jitsu (modern / no-gi-leaning) | `Fighting` *(planned)* |
| `ZenBJJ` | Brazilian Jiu-Jitsu (gi-focused, traditional academy) | `Fighting` |
| `FrictionGrappling` | No-gi submission grappling / 10th Planet-adjacent | `Fighting` |
| `DuckDancer` | Dance studios (dance-workout / general dance) | `Dance` |

Combat sports is covered across striking, grappling, and mixed. DuckDancer is the first non-combat theme — it counts toward the Dance category's 5-target.

**Theme browser filter buckets** (`design_direction.gym_type` in each theme's `customization.yaml`, mirrored on top-level `gym_type` in `output.yaml`): `Fighting`, `Yoga`, `Pilates`, `Barre`, `HIIT`, `Cardio`, `Dance`, `Wellness`. `Fighting` collapses what this doc still splits into "combat sports" and "traditional martial arts" headings into one bucket.

---

## TO BUILD — prioritized by category

### Traditional martial arts — 3 picks

Adjacent to combat sports but with distinct cultural and visual conventions that warrant their own themes.

1. Karate dojos (traditional adult — Shotokan / Kyokushin / Goju-ryu)
2. Taekwondo academies (adult / competitive)
3. Krav Maga schools (premium positioning common)

### Yoga — 12 picks

Aesthetic and cultural variation across yoga sub-types is wide enough that one "yoga" theme would not cover the market.

1. Vinyasa / flow studios
2. Hatha studios
3. Ashtanga / Mysore-style shalas
4. Iyengar studios
5. Bikram / traditional hot yoga (26-and-2)
6. Modern hot yoga (CorePower-style independents)
7. Yin / restorative studios
8. Power yoga / sculpt studios (yoga + weights hybrid)
9. Aerial yoga studios
10. Acro yoga / partner yoga studios
11. Prenatal / mom & baby yoga studios
12. Yoga + meditation hybrid studios

### Pilates — 10 picks

Reformer dominates the premium end; mat and hybrid formats fill the rest of the category.

1. Reformer pilates — classical (Romana-lineage)
2. Reformer pilates — contemporary (Club Pilates-style independents)
3. Megaformer / Lagree studios (SLT, Solidcore-style independents)
4. Mat pilates studios
5. Hot pilates studios
6. Pilates + sculpt (pilates + weights hybrid)
7. Pilates + barre hybrid studios
8. Pilates + cardio hybrid studios (jumpboard / cardio reformer)
9. Pilates + boxing hybrid studios
10. Pre/postnatal pilates studios

### Barre — 5 picks

1. Classic barre studios (Pure Barre, Bar Method-style independents)
2. Cardio barre studios
3. Barre3-style flow barre
4. Booty barre / dance-barre hybrids
5. Barre + yoga hybrid studios

### HIIT / functional fitness / strength — 15 picks

CRMs are fragmented here; relatively open shelf.

1. CrossFit affiliates
2. Non-affiliate functional fitness boxes
3. HYROX-prep gyms
4. F45 independent operators
5. OrangeTheory-style HIIT studios (independents)
6. BFT (Body Fit Training) independents
7. Burn Boot Camp-style outdoor / hybrid boot camps
8. Olympic weightlifting clubs
9. Powerlifting gyms with class components
10. Strongman gyms with class components
11. Kettlebell-focused gyms (StrongFirst / RKC-style)
12. Calisthenics / bodyweight studios
13. Tactical / military-prep gyms
14. TRX / suspension training studios
15. Group personal training studios with class structure

### Cardio specialty — 15 picks

Heavily boutique — strong branding culture, high theme-fit.

1. Indoor cycling studios (SoulCycle / CycleBar-style independents)
2. Power-class cycling studios (Stages / Schwinn-style)
3. Spin + strength hybrid studios
4. Sprint cycling studios (short-format intensity)
5. Rowing studios (Row House / CityRow-style independents)
6. Treadmill / running studios (STRIDE, Mile High Run Club-style)
7. Treadmill + strength hybrid studios (Barry's-style)
8. Trampoline / rebound cardio studios
9. Dance cardio studios (305 Fitness / Body by Simone-style)
10. Cardio boxing studios (Rumble-style independents, no-contact)
11. VersaClimber studios (Rise Nation-style)
12. Stair-climber cardio studios
13. Cardio circuit studios (multi-machine interval class)
14. Run clubs with structured paid training
15. Aqua cycling / pool-based cardio studios

### Dance — 5 picks (1 done)

✅ **DONE:** `DuckDancer` — dance-workout / general dance

TO BUILD:

2. Hip-hop / urban dance studios
3. Ballet (adult)
4. Pole dance fitness studios
5. Aerial silks / lyra / trapeze studios

### Wellness / mind-body / recovery — 5 picks

1. Meditation studios (Unplug / Inscape-style)
2. Stretch studios (StretchLab-style independents)
3. Mobility / recovery studios with class structure
4. Sauna / cold plunge studios with class booking model
5. Breathwork studios

---

## Tally

- Done: 8 themes (7 combat sports + 1 dance)
- To build: 3 + 12 + 10 + 5 + 15 + 15 + 4 + 5 = **69 themes**
- v1 library total target: **77 themes**
