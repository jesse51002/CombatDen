
Table auth_users {
  id uuid [primary key]
  email varchar
  created_at timestamp
}

Table gyms_unfiltered {
  gym_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_name varchar [not null]
  gym_description varchar
  timezone text [not null, default: 'America/Chicago', note: 'IANA timezone name, used for local-day comparisons (e.g. membership expiry)']
  stripe_account_id varchar [note: 'Stripe Connect account ID, NULL until onboarded']
  stripe_onboarding_status varchar [not null, default: 'not_started', note: 'enum: not_started, pending, complete, disabled']
}

// View: gyms — SELECT * FROM gyms_unfiltered WHERE stripe_account_id IS NOT NULL; SECURITY INVOKER, so RLS on gyms_unfiltered propagates through

Table user_gym_profiles_unfiltered {
  crm_user_id uuid [primary key, default: `uuid_generate_v4()`]
  user_id uuid [note: 'nullable, linked when member joins mobile app']
  gym_id uuid [not null]
  created_at timestamptz [not null, default: `now()`]
  last_class timestamptz
  first_name varchar [not null]
  last_name varchar [not null]
  photo_url varchar
  phone varchar
  email varchar
  address varchar
  emergency_contact_name varchar
  emergency_contact_phone varchar
  emergency_contact_email varchar
  points_balance integer [not null, default: 0]
  freeze_start_date date [note: 'nullable, account-level freeze start']
  freeze_end_date date [note: 'nullable, account-level freeze end']
  account_linked_to_id uuid [note: 'sub-account linked to primary member, must be same gym']
  linked_discount_id uuid [note: 'FK to gym_discounts, must be type linked']
  stripe_customer_id varchar [note: 'Stripe Customer ID, NULL until Stripe sync completes']
  stripe_sub_id_month varchar [note: 'Stripe Subscription ID for monthly recurring plans']
  stripe_payment_method_id varchar [note: 'Stripe PaymentMethod ID']
  payment_type varchar [note: 'card, us_bank_account, etc.']
  card_brand varchar [note: 'visa, mastercard, etc.']
  card_last_four varchar(4)
  card_exp_month integer
  card_exp_year integer
  total_monthly_recurring_price integer [not null, default: 0, note: 'sum of active recurring memberships (cents)']

  indexes {
    (user_id, gym_id) [unique, note: 'partial index WHERE user_id IS NOT NULL']
  }
}

Table user_activities {
  activity_id uuid [primary key, default: `uuid_generate_v4()`]
  crm_user_id uuid [not null]
  gym_id uuid [not null]
  activity_type varchar [not null]
  activity_info jsonb [default: '{}']
  time timestamptz [not null, default: `now()`]
}

Table gym_history {
  gym_id uuid [not null]
  date date [not null]
  members_total integer [not null]
  members_churned integer [not null]
  members_gained integer [not null]
  members_retained integer [not null]
  revenue integer [not null]

  indexes {
    (gym_id, date) [pk]
  }
}

Table user_gym_invoices {
  invoice_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_id uuid [not null]
  crm_user_id uuid [not null, note: 'the payer']
  status varchar [not null, default: 'open', note: 'enum: open, paid']
  total_amount integer [not null]
  currency char(3) [not null, default: 'usd']
  stripe_invoice_id varchar [unique, note: 'Stripe Invoice ID, nullable for manual/cash']
  stripe_payment_intent_id varchar [unique, note: 'Stripe PaymentIntent ID']
  invoice_time timestamptz [not null, default: `now()`]
  stripe_event_payload jsonb [note: 'raw webhook payload']
}

Table user_gym_invoice_line_items {
  line_item_id varchar [primary key, note: 'Stripe line item id (il_xxx)']
  invoice_id uuid [not null]
  gym_id uuid [not null]
  item_type varchar [not null, note: 'enum: membership, custom']
  name varchar [not null, note: 'frozen historical label']
  amount integer [not null]
  stripe_product_id varchar [note: 'Stripe Product ID']
  item_id uuid [note: 'FK to member_memberships when item_type = membership']
}

Table user_gym_charges {
  charge_id uuid [primary key, default: `uuid_generate_v4()`]
  invoice_id uuid [not null]
  gym_id uuid [not null]
  crm_user_id uuid [not null, note: 'denormalized from invoice for RLS/query speed']
  kind varchar [not null, note: 'enum: payment, refund']
  status varchar [not null, note: 'enum: pending, succeeded, failed']
  amount integer [not null, note: 'signed: payment >= 0, refund <= 0']
  currency char(3) [not null, default: 'usd']
  payment_method_type varchar [note: 'card, us_bank_account, cash, ...']
  stripe_charge_id varchar [unique, note: 'set for payment rows']
  stripe_refund_id varchar [unique, note: 'set for refund rows']
  refunds_charge_id uuid [note: 'set for refund rows, FK to user_gym_charges']
  charge_time timestamptz [not null, default: `now()`]
  stripe_event_payload jsonb [note: 'raw webhook payload']
}

Table user_gym_invoice_applied_discounts {
  applied_discount_id uuid [primary key, default: `uuid_generate_v4()`]
  invoice_id uuid [not null]
  gym_id uuid [not null]
  discount_id uuid [not null]
  amount_off integer [not null, note: 'snapshot of dollar value applied']
  stripe_coupon_id varchar
}

Table user_gym_reward_redemptions {
  redemption_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_id uuid [not null]
  crm_user_id uuid [not null]
  reward_id uuid [not null]
  point_cost integer [not null, note: 'snapshot at redemption time']
  redeemed_at timestamptz [not null, default: `now()`]
}

Table membership_plans_unfiltered {
  plan_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_id uuid [not null]
  plan_name varchar [not null]
  plan_type varchar [not null, note: 'enum: trial, recurring, one_time']
  class_count integer [note: 'nullable, number of classes included']
  duration_amount integer [note: 'nullable, required unless class_count is set; e.g. 1, 3, 6']
  duration_unit varchar [note: 'nullable, required unless class_count is set; enum: week, month, year']
  is_public boolean [not null, default: true]
  is_deleted boolean [not null, default: false]
  stripe_product_id varchar [note: 'Stripe Product ID']
  created_at timestamptz [not null, default: `now()`]
}

Table membership_plan_prices_unfiltered {
  price_id uuid [primary key, default: `uuid_generate_v4()`]
  plan_id uuid [not null]
  gym_id uuid [not null]
  stripe_price_id varchar [note: 'Stripe Price ID, NULL until Stripe sync completes']
  price integer [not null, note: 'cents']
  is_active boolean [not null, default: true, note: 'partial unique index: at most one active per plan']
  created_at timestamptz [not null, default: `now()`]
}

Table member_memberships_unfiltered {
  item_id uuid [primary key, default: `uuid_generate_v4()`]
  crm_user_id uuid [not null]
  gym_id uuid [not null]
  plan_id uuid [not null]
  price_id uuid [not null]
  end_date date
  cancel_date date
  start_date date [not null]
  last_paid_date date
  next_due_date date
  total_price integer [not null]

  discount_ids jsonb [note: 'array of gym_discounts discount_id refs, validated by trigger']
  stripe_item_id varchar [note: 'Stripe subscription item ID for recurring, invoice ID for one-time; NULL until Stripe sync completes']
  prorate boolean [not null, default: true]
  created_at timestamptz [not null, default: `now()`]

  indexes {
  }
}

Table gym_discounts_unfiltered {
  discount_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_id uuid [not null]
  discount_name varchar [not null]
  discount_type varchar [not null, note: 'enum: preset, custom, linked']
  percentage_off float [note: 'exactly one of percentage_off or dollar_off must be set']
  dollar_off integer [note: 'exactly one of percentage_off or dollar_off must be set']
  membership_plan_id uuid [note: 'only for linked discounts, FK to membership_plans']
  linked_discount_num integer [note: 'sequential position, only for linked discounts']
  duration varchar [not null, note: 'enum: once, repeating, forever']
  duration_in_months integer [note: 'required when duration = repeating']
  is_deleted boolean [not null, default: false]
  stripe_coupon_id varchar [note: 'Stripe Coupon ID']
  created_at timestamptz [not null, default: `now()`]
}

Table gym_employees {
  employee_id uuid [primary key, default: `uuid_generate_v4()`]
  user_id uuid [note: 'nullable, linked when employee has an auth account']
  gym_id uuid [not null]
  employee_type varchar [not null, note: 'enum: owner, admin, trainer']
  first_name varchar [not null]
  last_name varchar [not null]
  phone varchar
  email varchar
  employee_pic_url varchar
  employee_public_description varchar
  created_at timestamptz [not null, default: `now()`]
}

Table gym_rewards {
  reward_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_id uuid [not null]
  title varchar [not null]
  amount_off varchar
  image_url varchar
  point_cost integer [not null]
  is_active boolean [not null, default: true]
  created_at timestamptz [not null, default: `now()`]
}

Table gym_classes {
  class_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_id uuid [not null]
  class_name varchar [not null]
  class_description varchar
  allowed_plan_ids jsonb [note: 'array of membership_plans plan_id refs, validated by trigger; NULL = any plan']
  max_capacity integer
  is_active boolean [not null, default: true]
  is_deleted boolean [not null, default: false]
  created_at timestamptz [not null, default: `now()`]
}

Table gym_class_schedules {
  schedule_id uuid [primary key, default: `uuid_generate_v4()`]
  class_id uuid [not null]
  gym_id uuid [not null]
  class_time time [not null]
  duration_minutes integer [not null]
  recurring_unit varchar [not null, note: 'enum: daily, weekly, monthly']
  recurring_interval integer [not null, default: 1]
  sun boolean [not null, default: false]
  mon boolean [not null, default: false]
  tue boolean [not null, default: false]
  wed boolean [not null, default: false]
  thu boolean [not null, default: false]
  fri boolean [not null, default: false]
  sat boolean [not null, default: false]
  sun_instructor_id uuid
  mon_instructor_id uuid
  tue_instructor_id uuid
  wed_instructor_id uuid
  thu_instructor_id uuid
  fri_instructor_id uuid
  sat_instructor_id uuid
  is_cancelled boolean [not null, default: false]
  start_date date [not null]
  end_date date [note: 'NULL = ongoing; exclusion constraint prevents overlaps']
  created_at timestamptz [not null, default: `now()`]
}

Table gym_class_exceptions {
  exception_id uuid [primary key, default: `uuid_generate_v4()`]
  schedule_id uuid [not null]
  gym_id uuid [not null]
  original_date date [not null]
  is_cancelled boolean
  new_class_time time
  new_duration_minutes integer
  new_max_capacity integer
  new_instructor_id uuid
  created_at timestamptz [not null, default: `now()`]
}

Table gym_classes_log {
  log_id uuid [primary key, default: `uuid_generate_v4()`]
  crm_user_id uuid [not null]
  gym_id uuid [not null]
  class_id uuid [not null]
  plan_id uuid [not null]
  item_id uuid [not null]
  instructor_id uuid
  time timestamptz [not null, default: `now()`]
}

Table stripe_webhook_events {
  event_id varchar [primary key, note: 'Stripe event ID (evt_xxx)']
  gym_id uuid [not null]
  event_type varchar [not null, note: 'e.g. invoice.paid']
  processed_at timestamptz [not null, default: `now()`]
}

// --- Integrity Notes ---
// user_gym_profiles: UNIQUE partial index on (user_id, gym_id) WHERE user_id IS NOT NULL — prevents same auth user linking to multiple profiles in one gym
// user_gym_profiles: self-referencing composite FK on account_linked_to_id ensures linked account belongs to the same gym
// membership_plan_prices: partial unique index on (plan_id) WHERE is_active = TRUE — at most one active price per plan
// member_memberships: composite FK ensures price_id belongs to the same plan_id
// member_memberships: trigger on discount_ids validates all UUIDs exist in gym_discounts for the same gym
// member_memberships: trigger rejects end_date on recurring plans (plan_type looked up from membership_plans)
// member_memberships: status is derived via member_memberships_status view; frozen status comes from user_gym_profiles freeze window (cancelled > ended > account-frozen > active)
// gym_classes: trigger on allowed_plan_ids validates all UUIDs exist in membership_plans for the same gym
// gym_class_schedules: composite FKs on each day's instructor_id ensure instructor belongs to the same gym
// gym_class_schedules: exclusion constraint prevents overlapping date ranges for the same class
// gym_class_schedules: trigger enforces no gaps between schedule segments (contiguous history)
// gym_class_schedules: CHECK only enforces day booleans when recurring_unit = 'weekly'
// gym_class_exceptions: UNIQUE (schedule_id, original_date) — one exception per date per schedule
// gym_discounts: trigger enforces sequential linked_discount_num per (gym_id, membership_plan_id); rejects gaps on delete
// gym_classes_log: denormalizes class_name/time/duration/instructor for historical snapshot

// --- Relationships ---

// gym_employees
Ref: auth_users.id < gym_employees.user_id
Ref: gyms_unfiltered.gym_id < gym_employees.gym_id

// user_gym_profiles
Ref: auth_users.id < user_gym_profiles_unfiltered.user_id
Ref: gyms_unfiltered.gym_id < user_gym_profiles_unfiltered.gym_id

// user_activities
Ref: user_gym_profiles_unfiltered.crm_user_id < user_activities.crm_user_id
Ref: gyms_unfiltered.gym_id < user_activities.gym_id

// gym_history
Ref: gyms_unfiltered.gym_id < gym_history.gym_id

// user_gym_invoices
Ref: user_gym_profiles_unfiltered.crm_user_id < user_gym_invoices.crm_user_id
Ref: gyms_unfiltered.gym_id < user_gym_invoices.gym_id

// user_gym_invoice_line_items
Ref: user_gym_invoices.invoice_id < user_gym_invoice_line_items.invoice_id
Ref: gyms_unfiltered.gym_id < user_gym_invoice_line_items.gym_id
Ref: member_memberships_unfiltered.item_id < user_gym_invoice_line_items.item_id

// user_gym_charges
Ref: user_gym_invoices.invoice_id < user_gym_charges.invoice_id
Ref: gyms_unfiltered.gym_id < user_gym_charges.gym_id
Ref: user_gym_profiles_unfiltered.crm_user_id < user_gym_charges.crm_user_id
Ref: user_gym_charges.charge_id < user_gym_charges.refunds_charge_id

// user_gym_invoice_applied_discounts
Ref: user_gym_invoices.invoice_id < user_gym_invoice_applied_discounts.invoice_id
Ref: gyms_unfiltered.gym_id < user_gym_invoice_applied_discounts.gym_id
Ref: gym_discounts_unfiltered.discount_id < user_gym_invoice_applied_discounts.discount_id

// user_gym_reward_redemptions
Ref: gyms_unfiltered.gym_id < user_gym_reward_redemptions.gym_id
Ref: user_gym_profiles_unfiltered.crm_user_id < user_gym_reward_redemptions.crm_user_id
Ref: gym_rewards.reward_id < user_gym_reward_redemptions.reward_id

// membership_plans
Ref: gyms_unfiltered.gym_id < membership_plans_unfiltered.gym_id

// membership_plan_prices
Ref: membership_plans_unfiltered.plan_id < membership_plan_prices_unfiltered.plan_id
Ref: gyms_unfiltered.gym_id < membership_plan_prices_unfiltered.gym_id

// member_memberships
Ref: user_gym_profiles_unfiltered.crm_user_id < member_memberships_unfiltered.crm_user_id
Ref: gyms_unfiltered.gym_id < member_memberships_unfiltered.gym_id
Ref: membership_plans_unfiltered.plan_id < member_memberships_unfiltered.plan_id
Ref: membership_plan_prices_unfiltered.price_id < member_memberships_unfiltered.price_id
// user_gym_profiles (self-ref for linked accounts)
Ref: user_gym_profiles_unfiltered.crm_user_id < user_gym_profiles_unfiltered.account_linked_to_id

// gym_discounts
Ref: gyms_unfiltered.gym_id < gym_discounts_unfiltered.gym_id
Ref: membership_plans_unfiltered.plan_id < gym_discounts_unfiltered.membership_plan_id

// gym_classes
Ref: gyms_unfiltered.gym_id < gym_classes.gym_id

// gym_class_schedules
Ref: gym_classes.class_id < gym_class_schedules.class_id
Ref: gyms_unfiltered.gym_id < gym_class_schedules.gym_id
Ref: gym_employees.employee_id < gym_class_schedules.sun_instructor_id
Ref: gym_employees.employee_id < gym_class_schedules.mon_instructor_id
Ref: gym_employees.employee_id < gym_class_schedules.tue_instructor_id
Ref: gym_employees.employee_id < gym_class_schedules.wed_instructor_id
Ref: gym_employees.employee_id < gym_class_schedules.thu_instructor_id
Ref: gym_employees.employee_id < gym_class_schedules.fri_instructor_id
Ref: gym_employees.employee_id < gym_class_schedules.sat_instructor_id

// gym_class_exceptions
Ref: gym_class_schedules.schedule_id < gym_class_exceptions.schedule_id
Ref: gyms_unfiltered.gym_id < gym_class_exceptions.gym_id
Ref: gym_employees.employee_id < gym_class_exceptions.new_instructor_id

// gym_classes_log
Ref: user_gym_profiles_unfiltered.crm_user_id < gym_classes_log.crm_user_id
Ref: gyms_unfiltered.gym_id < gym_classes_log.gym_id
Ref: gym_classes.class_id < gym_classes_log.class_id
Ref: membership_plans_unfiltered.plan_id < gym_classes_log.plan_id
Ref: gym_employees.employee_id < gym_classes_log.instructor_id

// stripe_webhook_events
Ref: gyms_unfiltered.gym_id < stripe_webhook_events.gym_id

// gym_rewards
Ref: gyms_unfiltered.gym_id < gym_rewards.gym_id
