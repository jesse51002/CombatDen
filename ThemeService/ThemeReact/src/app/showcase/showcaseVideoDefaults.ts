// The VIDEO half of ./showcaseGroupDefaults.ts, split into its own module
// because the eight feeds are ~110 cards and would bury the class / reward maps
// they sit beside. Same rule, same provenance: group-aware bundled constants,
// the LAST-RESORT offline fallback beneath any live content, with NO runtime
// dependency on VideoService.
//
// These are REAL rows from VideoService's shared pool (`VideoService/videos/
// *.yaml`), extracted at build time exactly as the class / reward photos in
// ./showcaseGroupDefaults.ts were — same representative gym per group, so a
// Yoga theme previews a yoga feed:
//
//   Fighting -> boxing.yaml            Yoga     -> vinyasa.yaml
//   Pilates  -> reformer_classical.yaml Barre   -> classic_barre.yaml
//   HIIT     -> crossfit.yaml          Cardio   -> indoor_cycling.yaml
//   Dance    -> dance_fitness.yaml     Wellness -> breathwork.yaml
//
// Per group: the four genres the discipline's pool actually carries most of,
// ranked by the pool's own `relevance_index`, capped at two cards per channel
// so a feed is never one creator. Educational leads every group because the
// Profile screen's "Videos to level up" carousel filters to it.
//
// Thumbnails are YouTube's own (`i.ytimg.com`) and avatars are the channels'
// (`yt3.ggpht.com`) — the same hosts the real member app renders. Every URL
// here was HEAD-verified 200 at extraction time; a channel that later rotates
// its avatar simply drops the circle (./videos/CreatorAvatar.tsx), which is the
// documented behaviour on the Dart side too.

import type { ShowcaseVideo } from './showcaseContent';
import { DEFAULT_SHOWCASE_GROUP } from './showcaseGroupDefaults';

export const SHOWCASE_VIDEOS_BY_GROUP: Readonly<
  Record<string, readonly ShowcaseVideo[]>
> = Object.freeze({
  // Fighting — boxing.yaml
  Fighting: [
    {
      videoId: 'EERMNeTfHaY',
      title:
        'HOW to FINISH a FIGHT in 3 SECONDS || Nick Drossos',
      genre: 'educational',
      channelName: 'Nick Drossos Defensive Tactics',
      viewCount: 3776111,
      thumbnailUrl:
        'https://i.ytimg.com/vi/EERMNeTfHaY/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/w_8pmXpB1iSACj-zxlOiCn553uTxoGXGi3uZsxiXf-Peyd0MXuyQu6GaSegBvbkCCfmJOIhOUw=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'tSNybMUpMKk',
      title:
        'Shadow Box Workout | Let me Coach You for 11 Minutes',
      genre: 'educational',
      channelName: 'Precision Striking',
      viewCount: 2738521,
      thumbnailUrl:
        'https://i.ytimg.com/vi/tSNybMUpMKk/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_lJ2rr_1B4KmmyqV9NWF3zXYbWQZG6Q20OrwYUfsMyjNQ=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'JhkqSCahsNY',
      title:
        'Boxing Punches 1-6 Explained: Perfect Techniques',
      genre: 'educational',
      channelName: 'Oracle Boxing',
      viewCount: 1941274,
      thumbnailUrl:
        'https://i.ytimg.com/vi/JhkqSCahsNY/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/VE1mTZHRP8LM3gIXFoQQjPUIcaq7LR_UBFoza3lH00ZzJkxfMVHwbGiHNebDmwWfcLN9P817Ug=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'oZOXsO_LN7M',
      title:
        'Beginner to Boxer in 25 Minutes (#1 on YouTube)',
      genre: 'educational',
      channelName: 'Oracle Boxing',
      viewCount: 1359471,
      thumbnailUrl:
        'https://i.ytimg.com/vi/oZOXsO_LN7M/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/VE1mTZHRP8LM3gIXFoQQjPUIcaq7LR_UBFoza3lH00ZzJkxfMVHwbGiHNebDmwWfcLN9P817Ug=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'rgvPJsygNyo',
      title:
        '10 Advanced Footwork Movements for MMA',
      genre: 'educational',
      channelName: 'fightTIPS',
      viewCount: 1176427,
      thumbnailUrl:
        'https://i.ytimg.com/vi/rgvPJsygNyo/hqdefault.jpg?sqp=-oaymwEnCOADEI4CSFryq4qpAxkIARUAAIhCGAHYAQHiAQoIGBACGAY4AUAB&rs=AOn4CLDLE00mrgc5mj2aQlF-2P9cahJJUg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_nYKfkgaERvCmOGSjDDHXmK7oRdEVmfup14dGDWK5KmY1w=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'sUaebEVwXJw',
      title:
        'Training Camp Day 1: Sparring at Canelo Álvarez\'s Gym | Ryan Garcia Vlogs',
      genre: 'vlog',
      channelName: 'Ryan Garcia',
      viewCount: 9066117,
      thumbnailUrl:
        'https://i.ytimg.com/vi/sUaebEVwXJw/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_noD5sEu4gXQb0nSF1uw9B-o9oz-VlnOSToVeewH0lfMg=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: '4Ihf7brjDh8',
      title:
        'I Tried Boxing for 90 DAYS, It Changed My Life [Part 1]',
      genre: 'vlog',
      channelName: 'Logan Jacobson',
      viewCount: 682939,
      thumbnailUrl:
        'https://i.ytimg.com/vi/4Ihf7brjDh8/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/NPdSbHiGsmxyfLCnokdfNDOZzwwOnBCo5j7Dye_Om79ilyeG6WlikzGgKfiLJMB3D-5XhWaSxCI=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'eDW5pZc3bMU',
      title:
        'VLOG: Productive Days, Trying Kick Boxing, New Camera Set-up',
      genre: 'vlog',
      channelName: 'Chelsea Trevor',
      viewCount: 31575,
      thumbnailUrl:
        'https://i.ytimg.com/vi/eDW5pZc3bMU/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/4a0ovd5m9WddbdoAFNH6UnXLZJHu9rehcbyj0JE6Ca8vVg2-z0s4A1lTJFw1fVzMcIyVITu9BA=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: '_F3C4chBuo0',
      title:
        '60 Minutes Of Legendary Boxing Knockouts',
      genre: 'entertainment',
      channelName: 'The Boxing Round Up',
      viewCount: 817899,
      thumbnailUrl:
        'https://i.ytimg.com/vi/_F3C4chBuo0/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/T81ol1ZfeyJmXQLUoO5SJrVPLk4pRq3HxsqcINuoqXTOQrMsaAYHNNl3DAe2RXHkiSfgd4CQyg=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'Fz_Z8Tc8abs',
      title:
        'Epic Moments of Instant Karma in Boxing and MMA',
      genre: 'entertainment',
      channelName: 'Cheeky Boxing',
      viewCount: 509545,
      thumbnailUrl:
        'https://i.ytimg.com/vi/Fz_Z8Tc8abs/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/hxQm819n-ed_jdn3woVRjPTV_dAkEkeGAeUy5-wzVtEPJBnW6MBFHu1vu5EL1_mqRJR8uN_oHA=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'KWuXI6ZYgJI',
      title:
        '25 MINUTE BOXING CARDIO | No Equipment Follow Along Workout',
      genre: 'entertainment',
      channelName: 'Jessica Cobus',
      viewCount: 696,
      thumbnailUrl:
        'https://i.ytimg.com/vi/KWuXI6ZYgJI/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_lVOi9JzS-h_-Cb1wC3URT3wcbYvhVJqnVBQvZpZkus1xQ=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'kgMFbh8tmrw',
      title:
        'So Faaast! The Greatest EVER Combo Knockout Machine - Ray Leonard',
      genre: 'professional',
      channelName: 'VoteSport',
      viewCount: 3827259,
      thumbnailUrl:
        'https://i.ytimg.com/vi/kgMFbh8tmrw/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ETY9me0_67IwFOjUxulgUI8qndENSxrZOa1TtnGHfq3AQETis1OEn079rK3yIOXlyAMDEYaFTQ=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: '0puXApDI4yg',
      title:
        'Wild KO\'s! The Best Of BKFC 34!',
      genre: 'professional',
      channelName: 'Bare Knuckle Fighting Championship',
      viewCount: 2781841,
      thumbnailUrl:
        'https://i.ytimg.com/vi/0puXApDI4yg/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/Wpu2R8QP_s23v1nCzSurQkAlZjuu24GAv4Li1POPZktMXY3dINmw-Mo8TlXlUahvq_q9fGuOow=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'GrmfHRIPsEU',
      title:
        'Behind the Scenes Of An MMA Camp!',
      genre: 'professional',
      channelName: 'THE DOLCE DIET',
      viewCount: 2886,
      thumbnailUrl:
        'https://i.ytimg.com/vi/GrmfHRIPsEU/maxresdefault.jpg?sqp=-oaymwEmCIAKENAF8quKqQMa8AEB-AH-CYAC0AWKAgwIABABGGUgTihFMA8=&rs=AOn4CLC_w0Badd_kA_iEaUDGu8UkGLCgfQ',
      channelAvatarUrl:
        'https://yt3.ggpht.com/OhiNrK6eujHZqZ21BojRL9j2GqBT1c7iCq6QxdUto-mbkhROjCK2kAlQeTX0dw0KKgKVRqdcVg=s800-c-k-c0x00ffffff-no-rj',
    },
  ],
  // Yoga — vinyasa.yaml
  Yoga: [
    {
      videoId: 'v7AYKMP6rOE',
      title:
        'Yoga For Complete Beginners - 20 Minute Home Yoga Workout!',
      genre: 'educational',
      channelName: 'Yoga With Adriene',
      viewCount: 55465002,
      thumbnailUrl:
        'https://i.ytimg.com/vi/v7AYKMP6rOE/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_mdu0iCuAlmM7YcPB1yjYaHZrf9H1ytA71saLX1VJnR0NA=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'JoDKbXEUrvQ',
      title:
        '15 Mins Pranayama Practice | 5 Deep Breathing Exercises you should do Daily',
      genre: 'educational',
      channelName: 'Bharti Yoga',
      viewCount: 7820263,
      thumbnailUrl:
        'https://i.ytimg.com/vi/JoDKbXEUrvQ/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_k1nXnOWy3ZB35GQeH0SGEJMA98VEX1qVXOJLXXPtmM6Q=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'S9p5yhE6_fk',
      title:
        '30-Minute Power Yoga Flow For Tight Abs and a Toned Butt',
      genre: 'educational',
      channelName: 'PS Fit ',
      viewCount: 7030115,
      thumbnailUrl:
        'https://i.ytimg.com/vi/S9p5yhE6_fk/hqdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/iSduH0DyhWHWhPA1FAhSMqN4Sw490I4jo_LugPbvUp6jLQs6iMUcONK67qhacryz96odHggJpQ=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'P8uHMMmWMHQ',
      title:
        'Yoga Joy  |  20-Minute Full Body Vinyasa Flow',
      genre: 'educational',
      channelName: 'Yoga With Adriene',
      viewCount: 5092297,
      thumbnailUrl:
        'https://i.ytimg.com/vi/P8uHMMmWMHQ/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_mdu0iCuAlmM7YcPB1yjYaHZrf9H1ytA71saLX1VJnR0NA=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'zEOkI3xkF4U',
      title:
        'How Stretching REALLY Works',
      genre: 'educational',
      channelName: 'Institute of Human Anatomy',
      viewCount: 3737555,
      thumbnailUrl:
        'https://i.ytimg.com/vi/zEOkI3xkF4U/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/oQIUnDRGO1gKQM4efucuScxgxnU47ITHlHkviMFH-MfNJxg9zOiS_WkAkKByAiTdFlP-qk78O5E=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'Cv-GBnsHiyI',
      title:
        'I did 365 days of yoga, here\'s what happened.',
      genre: 'vlog',
      channelName: 'Corinne Dutil',
      viewCount: 3361853,
      thumbnailUrl:
        'https://i.ytimg.com/vi/Cv-GBnsHiyI/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/TH6edDDub7lv__Ve7jkE9j0FC-fDya2s4Al_GzYnpV37THZutrCFdZGJKBJ2faVANL3eVk6pyNo=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'jvUej9iVQyQ',
      title:
        'I tried yoga every day for 30 days.',
      genre: 'vlog',
      channelName: 'Matt D\'Avella',
      viewCount: 2014237,
      thumbnailUrl:
        'https://i.ytimg.com/vi/jvUej9iVQyQ/hq720.jpg?sqp=-oaymwEnCOgCEMoBSFryq4qpAxkIARUAAIhCGAHYAQHiAQoIGBACGAY4AUAB&rs=AOn4CLBm_8-P6t6Ev2pNaXWxmV6T4SGlNQ',
      channelAvatarUrl:
        'https://yt3.ggpht.com/Ldpkcur-En5Qn8rcowaWiU6xbNt_yMrs1mAVcSRBIOdq0tSyTmGGIALRcgfm1a8aGKgYiYDEIQ=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'db07NY83-Pg',
      title:
        'I did yoga everyday for 3 years, This is what happened',
      genre: 'vlog',
      channelName: 'Caro Arevalo',
      viewCount: 533616,
      thumbnailUrl:
        'https://i.ytimg.com/vi/db07NY83-Pg/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/x0mGOEuIfd7_NvD_oGkgJA8W4VKzN6FHJr0sLW2fhD4zJZ086BK3vbrLhQv9xNCloVOrq1f67w=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'a4ZpSs195I4',
      title:
        'Ekhart Yoga Bloopers, Fail Compilation',
      genre: 'entertainment',
      channelName: 'YogaEasy',
      viewCount: 51352,
      thumbnailUrl:
        'https://i.ytimg.com/vi/a4ZpSs195I4/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/5kI4Vd8tUgds-UTL8e9LZrOJR699OLhWKkkjZjG8Q3dVGipNtRfsDDWpx7jwQxArJ0jbSh7ehA=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'RR9iyrrMddM',
      title:
        'COUPLE\'S YOGA CHALLENGE!!',
      genre: 'entertainment',
      channelName: 'ATventure Vlogs',
      viewCount: 437,
      thumbnailUrl:
        'https://i.ytimg.com/vi/RR9iyrrMddM/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_mLcpYLZIAlBqOXyVI4_TfcmwQbS0nSaBa-_XHs5xSTnQ=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: '96WjC49dagg',
      title:
        'couples yoga challenge!',
      genre: 'entertainment',
      channelName: 'Aaliyah Kashyap',
      viewCount: 66638,
      thumbnailUrl:
        'https://i.ytimg.com/vi/96WjC49dagg/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/SK1ptu7ms6Ackyrn63SsNUs5VT-D58XQXOqsSdPXUJcjREj6wFe0ixW9KkK8uzOSzpz1qcR5fw=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: '_gOBlF47mrU',
      title:
        'Joe Rogan Talks Bikram Yoga',
      genre: 'interview',
      channelName: 'Bikram Choudhury',
      viewCount: 10298,
      thumbnailUrl:
        'https://i.ytimg.com/vi/_gOBlF47mrU/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/GSv0DskLW20h9woKjt-Z029vadgTdAIRR5UI3XhNd66VabjT74jBcoLeH0jX8JOfp_Ey1z2DA4w=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'Nq-qifMPAfk',
      title:
        'Interview with Yoga teacher David Garrigues',
      genre: 'interview',
      channelName: 'Asana Kitchen with David Garrigues',
      viewCount: 1550,
      thumbnailUrl:
        'https://i.ytimg.com/vi/Nq-qifMPAfk/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/S4YO4jG8JMqA3eXNkgyaDjbcP2FQLWphUfLpOEgnuFCnkKbRsgt5Oeqv7g4WkpoWJPHMGp9PVg=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'C6vqi7RHOEc',
      title:
        'Feeling Connected: Adrianne Nightingale on Flow State, Yoga, and Healing',
      genre: 'interview',
      channelName: 'Momoyoga',
      viewCount: 90,
      thumbnailUrl:
        'https://i.ytimg.com/vi/C6vqi7RHOEc/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/GXvaM8fh72_T0Rta6Jxe9wxKF8858FYlfn4kTAs-EowTxYBGPL5s3MwgfoqfMTKytsXqunjF_w=s800-c-k-c0x00ffffff-no-rj',
    },
  ],
  // Pilates — reformer_classical.yaml
  Pilates: [
    {
      videoId: 'nfMALE8WdoE',
      title:
        'WHY YOU SHOULD BE DOING PILATES | health benefits of pilates exercise',
      genre: 'educational',
      channelName: 'Justina Ercole',
      viewCount: 688920,
      thumbnailUrl:
        'https://i.ytimg.com/vi/nfMALE8WdoE/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/cDHOH-sV7qXRntPjSr5RcmqxgZo75kPxO6UihNVAxmEj17c0LmY1vshBo_nrae9HXZn9agaY=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'czoUHKFCOyQ',
      title:
        'I Did Pilates & Weightlifting for 5+ Years  *Which Gave Better Results?*',
      genre: 'educational',
      channelName: 'Keltie O\'Connor',
      viewCount: 497480,
      thumbnailUrl:
        'https://i.ytimg.com/vi/czoUHKFCOyQ/hq720.jpg?sqp=-oaymwEnCOgCEMoBSFryq4qpAxkIARUAAIhCGAHYAQHiAQoIGBACGAY4AUAB&rs=AOn4CLAHNZY5DrxoJjvoiG1ikgJ6xWRpYA',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_nP0czJxqtFZB28G1clVx39xbDaqh0cOXx9SpUuEO1R1Q=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'M43CvYO3EOw',
      title:
        'Pilates Reformer: Beginner Class',
      genre: 'educational',
      channelName: 'Saran Pilates',
      viewCount: 341380,
      thumbnailUrl:
        'https://i.ytimg.com/vi/M43CvYO3EOw/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/zp6BNLotS-0HAOb6Rqus2UsSY2iBDu8SgkkSxyLyaX994BlPt4DZW-ikAY6m5XuubK0INDmiBfo=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'n5WJYBtTPXg',
      title:
        'FUNdamental Beginner Reformer Workout 1',
      genre: 'educational',
      channelName: 'Pilates & Fitness TV',
      viewCount: 288292,
      thumbnailUrl:
        'https://i.ytimg.com/vi/n5WJYBtTPXg/hq720.jpg?sqp=-oaymwEnCOgCEMoBSFryq4qpAxkIARUAAIhCGAHYAQHiAQoIGBACGAY4AUAB&rs=AOn4CLCgi9onnRrMnznigoQHeQmzbu1uiQ',
      channelAvatarUrl:
        'https://yt3.ggpht.com/4ldOG-ALVANoh8-cm-L_wVI0royAh7XxVBrfBNJnqMOFiHQ8AxGQjAO8dBjohALXoxx3AqXs_Q=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'XUqNRbeKErI',
      title:
        'Can Pilates help with weight loss? *honest* Pilates Q&A from an Instructor!',
      genre: 'educational',
      channelName: 'Rachel’s Fit Pilates',
      viewCount: 120743,
      thumbnailUrl:
        'https://i.ytimg.com/vi/XUqNRbeKErI/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/46oCAtJ22iKl8UxLVC8979t5vrmPAR4y_5ujacy9XsLVLE3OhRa6TfVctWsxt1HBp3t6BiSqd34=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: '0a1TTJeazwg',
      title:
        '30 DAYS OF PILATES CHALLENGE.. *the internet is lying to you*',
      genre: 'vlog',
      channelName: 'morgans vlogs',
      viewCount: 341724,
      thumbnailUrl:
        'https://i.ytimg.com/vi/0a1TTJeazwg/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/Vd8wdW1LHAn_6dbYW2_zcgTGQtPWr4DTYUMvNHhnh497wLaUoPPnQmJzR6_4vY-CdNCLEJujgQ=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'jZ8xZaAw5xE',
      title:
        'What to expect CLUB PILATES',
      genre: 'vlog',
      channelName: 'Dr A Jhoy',
      viewCount: 37957,
      thumbnailUrl:
        'https://i.ytimg.com/vi/jZ8xZaAw5xE/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/oSkk80SQ-O5zLTETW1XABoGJkFDJrhOmIqxLQuSP21DmIDRF7vk2oVzQkIU3y-JJzXAIWo9YXGQ=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'UsxKxMzo3yo',
      title:
        'what REALLY happens when you do pilates EVERYDAY (before & after results!)',
      genre: 'vlog',
      channelName: 'Strawbecky',
      viewCount: 14392,
      thumbnailUrl:
        'https://i.ytimg.com/vi/UsxKxMzo3yo/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/SegSAWAwrk_c801fkayUeoCJ5mYwrgZUrQzQzHNPEN5SC2JHtS3mtZ_1akOH9G8QHXLw3qmeFGY=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'HN34nV9Z0wE',
      title:
        'Sebastien Lagree - The Man Behind The Machine',
      genre: 'interview',
      channelName: 'TheStudioMDR',
      viewCount: 4750,
      thumbnailUrl:
        'https://i.ytimg.com/vi/HN34nV9Z0wE/maxresdefault.jpg?sqp=-oaymwEmCIAKENAF8quKqQMa8AEB-AH-CYAC0AWKAgwIABABGF4gXiheMA8=&rs=AOn4CLDq_YQXqorPInuCrBJG3R8Nul4AHQ',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_kP34jR8NGVitRyATgRSyg_Hhreo2ERkvAzuiQ4ZT_2ag=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'HbB7yhXOVFo',
      title:
        'Interview with Michelle Meth regarding Pilates for Undisputed MMA',
      genre: 'interview',
      channelName: 'The Scuffle is Real',
      viewCount: 65,
      thumbnailUrl:
        'https://i.ytimg.com/vi/HbB7yhXOVFo/maxresdefault.jpg?sqp=-oaymwEmCIAKENAF8quKqQMa8AEB-AH-CYAC0AWKAgwIABABGGUgZShlMA8=&rs=AOn4CLDuvG_7eOMnRk_Odx4DRpJlW5kQOQ',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_mcTZkuyb1gBcLm2Y0veVGJtShImrJ_v-V743FTM1HeBg=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'e_j47PUJkXc',
      title:
        'The Pilates Suspension Method - Interview with Rebecca Beckler',
      genre: 'interview',
      channelName: 'Pilates Bridge',
      viewCount: 2599,
      thumbnailUrl:
        'https://i.ytimg.com/vi/e_j47PUJkXc/hqdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/R0LlOuz_ILKU7pKvb_LGF3spTTmLAunRPXWa7bAQW187yvrs9OenZZ5xoluhC7G5Inv_7OT7sdo=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'qT9XWi5z9Zo',
      title:
        'The Movement Movement a Pilates Studio in Melbourne offering Pilates Classes',
      genre: 'entertainment',
      channelName: 'Big Review TV',
      viewCount: 145,
      thumbnailUrl:
        'https://i.ytimg.com/vi/qT9XWi5z9Zo/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_l1zVwYpDd17spNzKQ2InlkCBsPb9e3oAxFH-A_ucg9suw=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'wOMf4ytECJA',
      title:
        'Supreme Pilates Pro w/Barre (Folding) Toning Tower  SPP089',
      genre: 'entertainment',
      channelName: 'Supreme Pilates Pro',
      viewCount: 6708,
      thumbnailUrl:
        'https://i.ytimg.com/vi/wOMf4ytECJA/maxresdefault.jpg?sqp=-oaymwEmCIAKENAF8quKqQMa8AEB-AH-CYAC0AWKAgwIABABGGUgVChHMA8=&rs=AOn4CLAngt4v59o70KE5SZCuQTRhjrrBag',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_lXw___yA6kMWk2V5faZdT-qlUdfjoefT5ZfofpqdzW7A=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'lvokR_VO8vY',
      title:
        'Unlimited Barre, Pilates, and Yoga classes. Start feeling good again!',
      genre: 'entertainment',
      channelName: 'Caya New York',
      viewCount: 253,
      thumbnailUrl:
        'https://i.ytimg.com/vi/lvokR_VO8vY/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_mncwKYWXNZNeU000DiG1PcH8Tw3KfEtmCWLYAWTOy-FQ=s800-c-k-c0x00ffffff-no-rj',
    },
  ],
  // Barre — classic_barre.yaml
  Barre: [
    {
      videoId: 'SQlH_pHSa24',
      title:
        'Ballet Barre Workout | 40 Min Total Body Workout with Sleek Technique',
      genre: 'educational',
      channelName: 'SweatyBetty',
      viewCount: 3212189,
      thumbnailUrl:
        'https://i.ytimg.com/vi/SQlH_pHSa24/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_lu1foBUq4g7-yxwv8GPlKlh7D1G8EjM3O90fKuZw7fShf7=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'X40Emh1fko0',
      title:
        '30 MIN Full Body Definition | Barre Sculpt At-Home Workout',
      genre: 'educational',
      channelName: 'Action Jacquelyn',
      viewCount: 1474356,
      thumbnailUrl:
        'https://i.ytimg.com/vi/X40Emh1fko0/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/1L5gJfpleNV3b7wHXljtuGKiyIkfZ3bniSB1STVO5J4IzCM4ZiiegO9-zBQQMsqcTaCc1UWYwg=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'gaQ3v5I3_i4',
      title:
        'BARRE WORKOUT | Full Body| 20 min | No equipment!',
      genre: 'educational',
      channelName: 'Coach Kel',
      viewCount: 1442254,
      thumbnailUrl:
        'https://i.ytimg.com/vi/gaQ3v5I3_i4/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/vy2-BKmhGBnh1XG13ZKmB-0A7-mtfmBhQmY0Q6H1j5Inopg-mLXYFI8_XqAcpOgSpf7jijUHIg=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: '8JWZehPF9_k',
      title:
        '35 MIN BARRE & PILATES WORKOUT || Full Body Sculpt',
      genre: 'educational',
      channelName: 'Move With Nicole',
      viewCount: 782441,
      thumbnailUrl:
        'https://i.ytimg.com/vi/8JWZehPF9_k/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/nXwNMBGCfXg4kiyspcLs-PzgK1uWiy18Ft1nAb89eJsmwwnHD6KXTFubQCLsTMhDxxQObHz7CQ=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'BUqe8uCbzeY',
      title:
        '40 MIN FULL BODY BARRE & PILATES WORKOUT || Sculpt & Strengthen',
      genre: 'educational',
      channelName: 'Move With Nicole',
      viewCount: 622048,
      thumbnailUrl:
        'https://i.ytimg.com/vi/BUqe8uCbzeY/hq720.jpg?sqp=-oaymwEnCOgCEMoBSFryq4qpAxkIARUAAIhCGAHYAQHiAQoIGBACGAY4AUAB&rs=AOn4CLBiIGJC6crTulZRte7OGL9HpCITfA',
      channelAvatarUrl:
        'https://yt3.ggpht.com/nXwNMBGCfXg4kiyspcLs-PzgK1uWiy18Ft1nAb89eJsmwwnHD6KXTFubQCLsTMhDxxQObHz7CQ=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'c2wK8jMhd4Q',
      title:
        'I Did Pilates, Yoga, & Barre for 3 Years *How Did Each Change me Differently*',
      genre: 'vlog',
      channelName: 'Keltie O\'Connor',
      viewCount: 296447,
      thumbnailUrl:
        'https://i.ytimg.com/vi/c2wK8jMhd4Q/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_nP0czJxqtFZB28G1clVx39xbDaqh0cOXx9SpUuEO1R1Q=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'p6m7gpFS6Oc',
      title:
        'Yoga Barre Dance Flow - Princeton dance room // ♫ High - JPB',
      genre: 'vlog',
      channelName: 'Vivian Tang',
      viewCount: 2351,
      thumbnailUrl:
        'https://i.ytimg.com/vi/p6m7gpFS6Oc/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/IRfCRJj64coVru5q7adgHwsDRJASUlx3HlB2BOg0z_0rZTEkOdgJQWrwxJwrjl-MI901pIlVtPw=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: '_mLcZOezgYA',
      title:
        'Fit in 60 Pilates and Barre - Testimonials Stacey',
      genre: 'vlog',
      channelName: 'fitinsixty',
      viewCount: 1614,
      thumbnailUrl:
        'https://i.ytimg.com/vi/_mLcZOezgYA/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_m8liqnQlduFBO6Os3uGVHkGqmN0_p_AhCM9JWiLfqebw=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'yas3-S2rq5Y',
      title:
        'Why Our Barre Class Is So Popular?  | Jal-Talk #3',
      genre: 'entertainment',
      channelName: 'Jal Yoga',
      viewCount: 2495,
      thumbnailUrl:
        'https://i.ytimg.com/vi/yas3-S2rq5Y/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_ksd4GYcfgiA7fbzZkzuNIeeTpj_CQfyntC7HFGg_9D8g=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'z51QcFCPDUE',
      title:
        'Some say Pure Barre is just for women, so we sent a man to a class',
      genre: 'entertainment',
      channelName: 'TheNowDenver Weekdays4pm',
      viewCount: 79212,
      thumbnailUrl:
        'https://i.ytimg.com/vi/z51QcFCPDUE/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_kyxffYKMdvyCvo50AHHD7kbMS_T4g1TLY7mlz_Y4rm=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'UnpBG_Xq7h0',
      title:
        'Final Behind The Scenes Video of Total New Body Booty Barre™ Shoot',
      genre: 'entertainment',
      channelName: 'TheBootyBarreTV',
      viewCount: 5118,
      thumbnailUrl:
        'https://i.ytimg.com/vi/UnpBG_Xq7h0/maxresdefault.jpg?sqp=-oaymwEmCIAKENAF8quKqQMa8AEB-AH-CYAC0AWKAgwIABABGGUgVShPMA8=&rs=AOn4CLBafv5yY_LHzBzDrY-m-Jnve8alYQ',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_mDBR_QOpDDSsXdRqxKtx5hKGcPGoAtG446MBhbYsuHYA=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'J-wCl9IVBnw',
      title:
        'Andrea Lincoln with the Barre Studio',
      genre: 'interview',
      channelName: 'Khanna House Studios',
      viewCount: 224,
      thumbnailUrl:
        'https://i.ytimg.com/vi/J-wCl9IVBnw/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/J1juLWlU3g-Yff3LferYh3xm71J2KnchOjMyLlErYa3_oOuPdEqB-BXXnueL5ofLA1j5YLxlJQ=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'Ztf9tb9pkro',
      title:
        'Jaime Sweeney, Pure Barre Cranston',
      genre: 'interview',
      channelName: 'GoLocal LIVE',
      viewCount: 406,
      thumbnailUrl:
        'https://i.ytimg.com/vi/Ztf9tb9pkro/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_lJXZURAwbQHUp_h4OLQ87A2wh4I7LJ3g1Sau7XZhUHxKo=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: '46j_liQZJDM',
      title:
        '#044: The Benefits of Barre Exercise with Joanna Amelio',
      genre: 'interview',
      channelName: 'A Whole New You Podcast',
      viewCount: 371,
      thumbnailUrl:
        'https://i.ytimg.com/vi/46j_liQZJDM/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_kR6Opmg2oIRzoWtriJk86nE5RqkxqO_9ZDJ_kuezCofA=s800-c-k-c0x00ffffff-no-rj',
    },
  ],
  // HIIT — crossfit.yaml
  HIIT: [
    {
      videoId: 'ptpmRrzRtWQ',
      title:
        'The Fastest Way To Blow Up Your Bench Press (4 Science-Based Steps) + Sample Program',
      genre: 'educational',
      channelName: 'Jeff Nippard',
      viewCount: 9480497,
      thumbnailUrl:
        'https://i.ytimg.com/vi/ptpmRrzRtWQ/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_k3d_sCJXZcQk5KQTlFzdGMIJwJpZ9g2W07Z616E5DENGI=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'eFmjckKXEoA',
      title:
        'Workout Series: How to Master the Handstand',
      genre: 'educational',
      channelName: 'Fabletics',
      viewCount: 9163725,
      thumbnailUrl:
        'https://i.ytimg.com/vi/eFmjckKXEoA/maxresdefault.jpg?sqp=-oaymwEmCIAKENAF8quKqQMa8AEB-AH-CYAC0AWKAgwIABABGGUgWShVMA8=&rs=AOn4CLDFxM6OS3q2NRbxjWBMaDJUTZadFA',
      channelAvatarUrl:
        'https://yt3.ggpht.com/GtzpXdFmnmqFwKJ5cGSm7wQ1oaD5SJF5PUedN0M-FG39Lm7q-AeymPBpe4azt7mu7km4sUSBJQ=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: '4Y2ZdHCOXok',
      title:
        'How to PROPERLY Bench Press for Growth (5 Easy Steps)',
      genre: 'educational',
      channelName: 'Jeremy Ethier',
      viewCount: 5570198,
      thumbnailUrl:
        'https://i.ytimg.com/vi/4Y2ZdHCOXok/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_lgPUjjOwxY-qWIYhqSzQlS_ncT-zL0MHVgKnxxnfJ59QQ=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'ImI63BUUPwU',
      title:
        '30 Min CARDIO WORKOUT at Home [LOW IMPACT STEADY STATE] LISS',
      genre: 'educational',
      channelName: 'Caroline Girvan',
      viewCount: 5329274,
      thumbnailUrl:
        'https://i.ytimg.com/vi/ImI63BUUPwU/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/SFOuP_iRJrdGFfXu67IAO-EcWJPUhePfh6E9WAUs3N7PdWhYsctmXQHEvmHPUHNgVaJajj6i=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'bEv6CCg2BC8',
      title:
        'How To Get A Huge Squat With Perfect Technique (Fix Mistakes)',
      genre: 'educational',
      channelName: 'Jeff Nippard',
      viewCount: 5250520,
      thumbnailUrl:
        'https://i.ytimg.com/vi/bEv6CCg2BC8/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_k3d_sCJXZcQk5KQTlFzdGMIJwJpZ9g2W07Z616E5DENGI=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'RX2gyBvhzAE',
      title:
        'FULL DAY of training with CROSSFIT GAMES ATHLETE ALESSANDRA PICHELLI | Episode 1',
      genre: 'vlog',
      channelName: 'Stephen Stover',
      viewCount: 5711,
      thumbnailUrl:
        'https://i.ytimg.com/vi/RX2gyBvhzAE/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_n3lGRsJhbjYcWAT4jaa46BzCwNqQoJJXxE0KSOgaWxtg=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'KPnuRvSb0hE',
      title:
        'One Year with Crossfit Vitality',
      genre: 'vlog',
      channelName: 'amber herlocker',
      viewCount: 1238,
      thumbnailUrl:
        'https://i.ytimg.com/vi/KPnuRvSb0hE/maxresdefault.jpg?sqp=-oaymwEmCIAKENAF8quKqQMa8AEB-AH-CYAC0AWKAgwIABABGFUgXChlMA8=&rs=AOn4CLCVFXM6X7e4ob1pOJOq4v5GLBd6fA',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_nynbpBgF6dhqq1oCbh3qcw7-ydXkg1wP1KtRNNfuzBJg=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'x5oyuxXixxU',
      title:
        'Will I Compete in the Tactical Games in 2025? Athlete Camp: Day 3',
      genre: 'vlog',
      channelName: 'Lauren Kalil',
      viewCount: 770,
      thumbnailUrl:
        'https://i.ytimg.com/vi/x5oyuxXixxU/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/VAHgDHoMymEUwVgjVOXFYBFpks8_TX5S5rwqSlOAm-iIbJFMR_kdeqel27TNiYIh6It1yB90=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'mL40wGiWbCo',
      title:
        'Best HIIT Workout Music 2018 | HIIT MUSIC 30/15 | 20 rounds | 2018 Mix',
      genre: 'entertainment',
      channelName: 'HIIT MUSIC',
      viewCount: 2197313,
      thumbnailUrl:
        'https://i.ytimg.com/vi/mL40wGiWbCo/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_l50dPQ8KIEWwiRLWJDivQ6M9jRv1U39FAVj0wVEuyRU6s=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'jmL3vG-2zhQ',
      title:
        'Myles Garrett Put @RDCworld1 Through a NFL Players\' Workout',
      genre: 'entertainment',
      channelName: 'NFL',
      viewCount: 2083518,
      thumbnailUrl:
        'https://i.ytimg.com/vi/jmL3vG-2zhQ/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/mTNz2WARw0gLIz_BM5cuB6oRAQCTapuIwiiAAHd-IeWMCfE_zNcRVOXt4N6c4YxJbQ_kibWOFg=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'Cmsr0n0Gd3I',
      title:
        'Bloopers - HIIT Workout',
      genre: 'entertainment',
      channelName: '4D Training',
      viewCount: 300,
      thumbnailUrl:
        'https://i.ytimg.com/vi/Cmsr0n0Gd3I/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_lR54ZTW9xdTxmQVp96p_oZ8UpWOZJkVO9ezw9WZY14xg=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'jYV2JjadtWg',
      title:
        '10 Iconic CrossFit Games Moments',
      genre: 'professional',
      channelName: 'CrossFit Games',
      viewCount: 3248353,
      thumbnailUrl:
        'https://i.ytimg.com/vi/jYV2JjadtWg/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/qXUMmAuSG-NY4DazmbcsioWkWikmTw_2L1lp6vh7tvJ7gDYUhH9-0yi41Py9OD4BaeVeLhYmDQ=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'NBY6bKUCfcs',
      title:
        'Mathew Fraser Turns on the Afterburners in Suicide Sprint at the 2016 Games',
      genre: 'professional',
      channelName: 'CrossFit Games',
      viewCount: 646351,
      thumbnailUrl:
        'https://i.ytimg.com/vi/NBY6bKUCfcs/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/qXUMmAuSG-NY4DazmbcsioWkWikmTw_2L1lp6vh7tvJ7gDYUhH9-0yi41Py9OD4BaeVeLhYmDQ=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'cBrf_ecT64c',
      title:
        'MURPH with Elite CrossFit Athletes',
      genre: 'professional',
      channelName: '1st Phorm',
      viewCount: 69508,
      thumbnailUrl:
        'https://i.ytimg.com/vi/cBrf_ecT64c/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/bqlpyk2u6ppXJwmTHgiJqxLcqhaKKIctZA12pM7-XhJ_iW3oetekV3ua8CAXACypnI2hdmtOuA=s800-c-k-c0x00ffffff-no-rj',
    },
  ],
  // Cardio — indoor_cycling.yaml
  Cardio: [
    {
      videoId: '4Hl1WAGKjMc',
      title:
        'Burn Fat Fast: 20 Minute Bike Workout',
      genre: 'educational',
      channelName: 'Global Cycling Network',
      viewCount: 19411125,
      thumbnailUrl:
        'https://i.ytimg.com/vi/4Hl1WAGKjMc/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_m6Gu1EsNl3jLk5aVcpS8u0fBMfElFz-Rback2e3Y2RLDM=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'ImI63BUUPwU',
      title:
        '30 Min CARDIO WORKOUT at Home [LOW IMPACT STEADY STATE] LISS',
      genre: 'educational',
      channelName: 'Caroline Girvan',
      viewCount: 5329274,
      thumbnailUrl:
        'https://i.ytimg.com/vi/ImI63BUUPwU/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/SFOuP_iRJrdGFfXu67IAO-EcWJPUhePfh6E9WAUs3N7PdWhYsctmXQHEvmHPUHNgVaJajj6i=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: '0MLnC3bzXgQ',
      title:
        'What Happens to Your Body When You Cycle Every Day',
      genre: 'educational',
      channelName: 'Big Muscles',
      viewCount: 2066984,
      thumbnailUrl:
        'https://i.ytimg.com/vi/0MLnC3bzXgQ/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/H_DETnmHOgrZSth2Mc9U8SF1POKM9lfhbS2YTPbO7tXXz4-1FhakdaWxKJZ0zmELyvx0Rw2HnZk=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'QB69Pwl6GI8',
      title:
        'Indoor Cycling Workout | 60 Minute Endurance Intervals: Fitness Training',
      genre: 'educational',
      channelName: 'Global Cycling Network',
      viewCount: 1833224,
      thumbnailUrl:
        'https://i.ytimg.com/vi/QB69Pwl6GI8/hq720.jpg?sqp=-oaymwEnCOgCEMoBSFryq4qpAxkIARUAAIhCGAHYAQHiAQoIGBACGAY4AUAB&rs=AOn4CLBZVq-5rHyclfC_ab4tSjBG4rBSDw',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_m6Gu1EsNl3jLk5aVcpS8u0fBMfElFz-Rback2e3Y2RLDM=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: '7fzWHow-3zc',
      title:
        'How To: Setup your bike',
      genre: 'educational',
      channelName: 'Spinning',
      viewCount: 820322,
      thumbnailUrl:
        'https://i.ytimg.com/vi/7fzWHow-3zc/hqdefault.jpg?sqp=-oaymwEmCOADEOgC8quKqQMa8AEB-AGMBYAC4AOKAgwIABABGGUgZShlMA8=&rs=AOn4CLCGh-VeqbZ9E-p1WKQ6TvHUPDuRdQ',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_kFskj_FokaeSl0dSpDr7ggf-H7YoJNbAvbITIUSoxoI9c=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'CsF-bpdNJvA',
      title:
        '30 Minute FAT BURNING Pop Themed Indoor Cycling Class',
      genre: 'entertainment',
      channelName: 'Kaleigh Cohen Cycling',
      viewCount: 950698,
      thumbnailUrl:
        'https://i.ytimg.com/vi/CsF-bpdNJvA/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/rK0PIR7QBUofsDKEY8CCcPujdgvrqoh9wkUsutBYuQ9uDbkrGO7LlkLPEMht9bKtPant03O2uA=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 's9SSx0EYguk',
      title:
        '45 Minute Rhythm Cycling Class - Women of 80s + 90s Pop',
      genre: 'entertainment',
      channelName: 'Gabriella Guevara',
      viewCount: 225668,
      thumbnailUrl:
        'https://i.ytimg.com/vi/s9SSx0EYguk/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/lvp_9J_EsBWuxrW8GpZuS-ejnEnR-BRKY9U0qryc0hSwb7nZ7r2hKxKHUJABCPxVHTKVnp--UQ=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'ogfLJoujY9U',
      title:
        'EDM HIIT CALORIE BURNER | 30 Minute Rhythm Ride Cycling Class',
      genre: 'entertainment',
      channelName: 'Kaleigh Cohen Cycling',
      viewCount: 140391,
      thumbnailUrl:
        'https://i.ytimg.com/vi/ogfLJoujY9U/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/rK0PIR7QBUofsDKEY8CCcPujdgvrqoh9wkUsutBYuQ9uDbkrGO7LlkLPEMht9bKtPant03O2uA=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'sTtY-0Qi7to',
      title:
        'FTP Test That Really HURT! | Blood Sweat And Tears! | Ben Foster - The Cycling GK',
      genre: 'vlog',
      channelName: 'Ben Foster - The Cycling GK',
      viewCount: 168450,
      thumbnailUrl:
        'https://i.ytimg.com/vi/sTtY-0Qi7to/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/FX3XygAbmW27o_b33sOCi_x1AEJcytR2z5sbdFEiLTE9ezPCbPG_0IXvgBzGpIMW1BW36G7R=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'l1uRl-wYjJs',
      title:
        'Overweight Beginner Cyclist Post Christmas Reality Check',
      genre: 'vlog',
      channelName: 'Moderately Motivated',
      viewCount: 1723,
      thumbnailUrl:
        'https://i.ytimg.com/vi/l1uRl-wYjJs/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/Mc4j4lw_TQTUvemT9vyTgx3Uxilp3iWffi6AS8dgFVSfoL4XF-YQ5o8aFTUz8OnrUyEhyRbb=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'AjGZw1XdjBA',
      title:
        '\'Half is Easy\' - 360Cycling Full Gas, Full Recovery sprint session',
      genre: 'vlog',
      channelName: 'Dave Haygarth',
      viewCount: 363,
      thumbnailUrl:
        'https://i.ytimg.com/vi/AjGZw1XdjBA/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ETnsxnEIeAiv9StIejhw7t8mO-xe31BlNyk_PMQSs1h6_VcBVUIJWjTo78S--C2YHcOpjDIqcOQ=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: '-6DhfMJH84E',
      title:
        '#41 - Zone 2 training: why all the talk? With Dr Andrew Coggan',
      genre: 'interview',
      channelName: 'Inside Exercise',
      viewCount: 42206,
      thumbnailUrl:
        'https://i.ytimg.com/vi/-6DhfMJH84E/hqdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/a4NNVllUv3h1dh6a2LwKcKUSpfUi2Db_gtTd21MfAxJVOkKEb4RxOsHIiZRsWo8F13L8pjxqig=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'zerfw5YgNSk',
      title:
        'A Look Inside Cycle House LA: Behind the Scenes Interview',
      genre: 'interview',
      channelName: 'Cycle House',
      viewCount: 9267,
      thumbnailUrl:
        'https://i.ytimg.com/vi/zerfw5YgNSk/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_kKDGV87sx-ZoqK1ozKXFsgNJVadAHNdjd0vNhqf2aCf_s=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'fJ2f_C86yMg',
      title:
        'Benefits of Cycling - Spinning Class - Interview with Spinning Instructor Rob Kyle',
      genre: 'interview',
      channelName: 'DoItandLoseIt',
      viewCount: 3344,
      thumbnailUrl:
        'https://i.ytimg.com/vi/fJ2f_C86yMg/hqdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_lwLnxQQn-5csdY2iN4l9GUWYSgePgszz2FqA2MG6M=s800-c-k-c0x00ffffff-no-rj',
    },
  ],
  // Dance — dance_fitness.yaml
  Dance: [
    {
      videoId: 'hI4b_9h9LtY',
      title:
        'Learn to dance Hip Hop the Ailey way w/ DJ Rubble & Run DMC | Noggin',
      genre: 'educational',
      channelName: 'Nick Jr.',
      viewCount: 1012463,
      thumbnailUrl:
        'https://i.ytimg.com/vi/hI4b_9h9LtY/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/5Oe6GeP0RS7YYXlcSqCoBCyzYYtoxSgmN0K_FXQTBOY9tutzr5G1mXjfSmi76YAE3Q8WZXNByQ=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: '1ilft2HKQrI',
      title:
        'Centre Class Follow Along | Lazy Dancer Tips',
      genre: 'educational',
      channelName: 'Lazy Dancer Tips',
      viewCount: 90354,
      thumbnailUrl:
        'https://i.ytimg.com/vi/1ilft2HKQrI/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/T3-15xU0MzQ2K8GQRnzLk22kGYaAzAWZCXT7DEv1m-E8yYvWw41sekAp-oPr7XiXgYx_u06F=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: '1hC3_-c5XYk',
      title:
        'Things I Wish I Knew Before Becoming a Dance Teacher & Fitness Instructor',
      genre: 'educational',
      channelName: 'Marissa Tonge',
      viewCount: 3889,
      thumbnailUrl:
        'https://i.ytimg.com/vi/1hC3_-c5XYk/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/57Vl2Kog24N1hbvyrmSo1whyhI3VIWjh7lSJY2sgGAV_DGypZKCyOCqZiQuF1ajhGGH8WCa9=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'JWTyO8npkOQ',
      title:
        'Easy Kids Choreography - (Hip Hop Dance Tutorial AGES 4+)  | MihranTV',
      genre: 'educational',
      channelName: 'MihranTV',
      viewCount: 4275054,
      thumbnailUrl:
        'https://i.ytimg.com/vi/JWTyO8npkOQ/hq720.jpg?sqp=-oaymwEnCOgCEMoBSFryq4qpAxkIARUAAIhCGAHYAQHiAQoIGBACGAY4AUAB&rs=AOn4CLBalg1Mr9SJZsD3uVGfOhek4oNKxw',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_nh2ooSofRqRR5dqOeSdIZo_JGB3y15N-Gz2NoxMz1dXkw=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'rIONESd0DBo',
      title:
        'Dua Lipa - Dance The Night (From Barbie The Album) -  DANCE WORKOUT',
      genre: 'entertainment',
      channelName: 'The Fitness Marshall',
      viewCount: 3042844,
      thumbnailUrl:
        'https://i.ytimg.com/vi/rIONESd0DBo/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/w4s_Kjyek1fyKivToAn4DvWnO9tXOC_IF_0yu6sx_vCGWL7M4LsKVRMWOMpqw_fZVgy1Rxsd=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'E6lsGDntAEM',
      title:
        '20 Minute Dance Workout for Seniors | SilverSneakers',
      genre: 'entertainment',
      channelName: 'SilverSneakers',
      viewCount: 2803900,
      thumbnailUrl:
        'https://i.ytimg.com/vi/E6lsGDntAEM/maxresdefault.jpg?sqp=-oaymwEmCIAKENAF8quKqQMa8AEB-AH-CYAC0AWKAgwIABABGBcgTyh_MA8=&rs=AOn4CLDVD7otapUSWjAYde0IWLL-MmoiPg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/D6mZjRLSbYUWMpnRkVcaUgKT8ADnHIF8RR_uDf4FQ0JIzYJNukiqmPUrri4zkdY_0RscqNnWSF0=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'wucZxx-XaVA',
      title:
        '15-Minute GROOVE Dance Follow-Along | Tristan Edpao | STEEZY.CO',
      genre: 'entertainment',
      channelName: 'STEEZY',
      viewCount: 1612933,
      thumbnailUrl:
        'https://i.ytimg.com/vi/wucZxx-XaVA/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_lotDwDe7qoi-uqA7rrB4t4EkRUVcHTodOCQr0pYnESHxk=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: '2VTb1eVw7Cg',
      title:
        'I tried the 20lbs in 2 weeks DANCE WORKOUT... and it WORKED! *no diet*',
      genre: 'vlog',
      channelName: 'Jazz Rose',
      viewCount: 1105959,
      thumbnailUrl:
        'https://i.ytimg.com/vi/2VTb1eVw7Cg/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/E_qX3FAo2629FUFrE1JqQVqMZJfIv4gdYkXPNqWYcQrV77F653DwgJQVVHD2RTBf5yq-LGzSw38=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'nN_PUimGMCE',
      title:
        'Spend the day with me| Turn Up Dance Fitness Instructor Interview',
      genre: 'vlog',
      channelName: 'Ashley Tatianna: My Beautiful Life',
      viewCount: 26,
      thumbnailUrl:
        'https://i.ytimg.com/vi/nN_PUimGMCE/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/3DZKefCHfel3os57VK0YpR97sJCSVC51VUB9aSzLEXnrcjesuA4eyHeu6NYfyZV-T9I1-HExow=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'dBSAURSwuiI',
      title:
        '5AM DAY IN MY LIFE: my 5am-11pm routine as a personal trainer',
      genre: 'vlog',
      channelName: 'Caitie June',
      viewCount: 11995,
      thumbnailUrl:
        'https://i.ytimg.com/vi/dBSAURSwuiI/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/_FveZLOqXQ8M6ghXqF3urhHhtMIKX5gwyFeD7yJs7vcH3e2EwZp93MdhYf2yF9HrPnbsw3sC2g=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'vNyGbguyTO8',
      title:
        'Cardio Dance Instructor Speaks About the Love of her Job and Fitness',
      genre: 'interview',
      channelName: 'Hans Meyer (J2311 YouTube Channel)',
      viewCount: 269,
      thumbnailUrl:
        'https://i.ytimg.com/vi/vNyGbguyTO8/hqdefault.jpg?sqp=-oaymwEmCOADEOgC8quKqQMa8AEB-AHUBoAC4AOKAgwIABABGHIgZCg1MA8=&rs=AOn4CLB5suMviP1kH9sedvSbyzvZckYcVQ',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_nnrL0emNoi6aRHhrsKU3RnMLWG4CEUJQW7EC5ADw4=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'z851PYZPmIo',
      title:
        'Zumba Combo Interview - Caroline Parsons',
      genre: 'interview',
      channelName: 'Lifetime Fitness',
      viewCount: 799,
      thumbnailUrl:
        'https://i.ytimg.com/vi/z851PYZPmIo/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_n00FDSHU6sOdKanw5xIjSgH1oTBIhm0x3xNBAUgHho8A=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'l2Gh06t0EFk',
      title:
        'QUESTIONS Pole Dancers Get All The Time',
      genre: 'interview',
      channelName: 'Poletagonist',
      viewCount: 788,
      thumbnailUrl:
        'https://i.ytimg.com/vi/l2Gh06t0EFk/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/0HgXEh0b6EncCGSwnkMOj93oQyAht43Dhgj8sQyqeJkTA53C_VkQyYcd_AUVpqONTbqzHr-M=s800-c-k-c0x00ffffff-no-rj',
    },
  ],
  // Wellness — breathwork.yaml
  Wellness: [
    {
      videoId: 'JoDKbXEUrvQ',
      title:
        '15 Mins Pranayama Practice | 5 Deep Breathing Exercises you should do Daily',
      genre: 'educational',
      channelName: 'Bharti Yoga',
      viewCount: 7820263,
      thumbnailUrl:
        'https://i.ytimg.com/vi/JoDKbXEUrvQ/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_k1nXnOWy3ZB35GQeH0SGEJMA98VEX1qVXOJLXXPtmM6Q=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'U9YKY7fdwyg',
      title:
        '10-Minute Meditation For Beginners | Goodful',
      genre: 'educational',
      channelName: 'Goodful',
      viewCount: 5759554,
      thumbnailUrl:
        'https://i.ytimg.com/vi/U9YKY7fdwyg/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/36PQfqujlsBI-IssOCmT9-wVdVDEftvezfB3OUKtIK9gctTslsjOfGBeoyYSJdbuAoOQl4Sf=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'jHZPtn15agE',
      title:
        'Gentle, Relaxing, Cozy Flow  |  20-Minute Home Yoga',
      genre: 'educational',
      channelName: 'Yoga With Adriene',
      viewCount: 4195332,
      thumbnailUrl:
        'https://i.ytimg.com/vi/jHZPtn15agE/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_mdu0iCuAlmM7YcPB1yjYaHZrf9H1ytA71saLX1VJnR0NA=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'o_73FeXw3ZI',
      title:
        '10 Minutes That Instantly Loosen Your Whole Body',
      genre: 'educational',
      channelName: 'Breathe and Flow',
      viewCount: 2911255,
      thumbnailUrl:
        'https://i.ytimg.com/vi/o_73FeXw3ZI/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/TCrj85YVr3J9R8l-TFbY6Y4ZECJ82bR2j-YSeiQKp7o4xqWTWsLuc6yeWirAY7pb0eCOGObb=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'JslvBcIVtDg',
      title:
        'How To Meditate For Beginners (Animated)',
      genre: 'educational',
      channelName: 'Mitch Manly',
      viewCount: 2196065,
      thumbnailUrl:
        'https://i.ytimg.com/vi/JslvBcIVtDg/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_kwiB5Ji4n19kCVY4Rtd-fODRSperExvoniNy6YDex5Peo=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: '160f3K7FDyo',
      title:
        'I Did Wim Hof (Breathing Exercises) Every day For 30 Days',
      genre: 'vlog',
      channelName: 'Brett Maverick',
      viewCount: 819005,
      thumbnailUrl:
        'https://i.ytimg.com/vi/160f3K7FDyo/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/QRkQm5eTpF4og0uXzG3iE_kP4nroYTAq6rib1-u4SHAGx98yt7P_1Iigf1UURVMeKN42tDSkLQ=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'PnFKlO-LVW0',
      title:
        'I Did 30 DAYS of Cold Plunges in A Row - Here\'s what I learned.',
      genre: 'vlog',
      channelName: 'Jason Grubb',
      viewCount: 176016,
      thumbnailUrl:
        'https://i.ytimg.com/vi/PnFKlO-LVW0/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/qQ3D-pKkm91YyYYr8tYVm9hgIPxCD2uvoNDx2CEZWaHWaqsbOruXquIc9P9eZII50y-kBFGU4Q=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'AXQvbs_Nd7g',
      title:
        'How Meditation Changed my Life | Every Day for a Year',
      genre: 'vlog',
      channelName: 'Will Grant',
      viewCount: 53886,
      thumbnailUrl:
        'https://i.ytimg.com/vi/AXQvbs_Nd7g/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/urgHVDdeuNf1lBRE7o2CQYm0ExTK8SwxOlmtjmma0iwb6ZlC9nHbh1Wrs0kvFbGByP4XVFc3=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'EwB_xrwnOvE',
      title:
        'Cold vs Hot: Which is Better for Women? | Dr. Stacy Sims & Dr. Andrew Huberman',
      genre: 'interview',
      channelName: 'Huberman Lab Clips',
      viewCount: 31287,
      thumbnailUrl:
        'https://i.ytimg.com/vi/EwB_xrwnOvE/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/QG1pXMniOcWnJhTcGl3etDb9m8pZn5TsISM1qrQklZd6ExIlhArVOJ-MffOB9jgRl78BybHAdQ=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'J4l5W1lCqaU',
      title:
        'Studying Transcendental Meditation with Monks for 6 months - Meghan Williams',
      genre: 'interview',
      channelName: 'Rapid Regeneration',
      viewCount: 22,
      thumbnailUrl:
        'https://i.ytimg.com/vi/J4l5W1lCqaU/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/i44ygJSwQJyf4XGwmT3DBb_Tyr4RIoEaFaGs9kQjkfDGCFLEHD9-T89x1BOHMf6AEQmd5CGt3w=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'TlRcjjQdyXw',
      title:
        'The benefits of sauna | Andrew Huberman and Lex Fridman',
      genre: 'interview',
      channelName: 'Lex Clips',
      viewCount: 828903,
      thumbnailUrl:
        'https://i.ytimg.com/vi/TlRcjjQdyXw/hq720.jpg?sqp=-oaymwEnCOgCEMoBSFryq4qpAxkIARUAAIhCGAHYAQHiAQoIGBACGAY4AUAB&rs=AOn4CLAloHdLZuWIN5-4LjnXVcqbqi9Thw',
      channelAvatarUrl:
        'https://yt3.ggpht.com/ytc/AIdro_mqpG4xlDaXgYX1s4p2YLKke5KfakvFRmhPNXqT1VdpHaM=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'e7wYDk8QbGA',
      title:
        'Ariana Grande - Breathin (Live on Ellen / 2018)',
      genre: 'entertainment',
      channelName: 'Ariana Grande',
      viewCount: 19967803,
      thumbnailUrl:
        'https://i.ytimg.com/vi/e7wYDk8QbGA/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/hK5f1t-mCu2WrNg3WPSrS5rySMl-wT0z3wNZuIWvC3gPtM4glWNszP0LthUxBcZVxgWVs6rq=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'ZGTh1URwW_Y',
      title:
        'Guided Sleep Meditation for Anxiety Relief, Let Go of Worries, Release Your Mind',
      genre: 'entertainment',
      channelName: 'Jason Stephenson - Guided Sleep Meditation ',
      viewCount: 294664,
      thumbnailUrl:
        'https://i.ytimg.com/vi/ZGTh1URwW_Y/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/a2O8Y3JoH7FvwpByzOokUFNiqM9QvG3hbXB6TTzP6omedDuA98bfxvuqN9RPDJkLWFcIYmgf=s800-c-k-c0x00ffffff-no-rj',
    },
    {
      videoId: 'b7ruRVunE-I',
      title:
        'R&B Yoga Mix | Soulful Chill Music for Flow, Breath & Balance',
      genre: 'entertainment',
      channelName: 'Moody DJ Vibes',
      viewCount: 2853,
      thumbnailUrl:
        'https://i.ytimg.com/vi/b7ruRVunE-I/maxresdefault.jpg',
      channelAvatarUrl:
        'https://yt3.ggpht.com/B3BLdq9-5OOWAmyYezZv5-6mcTaCxZQJMkXfNmhxtVQ9Y0iyrfV7mIgq1TUnL0oYCd4-xg5vgA=s800-c-k-c0x00ffffff-no-rj',
    },
  ],
});

/**
 * The bundled feed for `category`, falling back to the default group. Never
 * empty: every group carries a full feed.
 */
export function bundledVideos(category: string | null): readonly ShowcaseVideo[] {
  const key = category ?? DEFAULT_SHOWCASE_GROUP;
  return (
    SHOWCASE_VIDEOS_BY_GROUP[key] ??
    SHOWCASE_VIDEOS_BY_GROUP[DEFAULT_SHOWCASE_GROUP] ??
    []
  );
}
