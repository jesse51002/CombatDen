// dbdiagram.io markup — paste into https://dbdiagram.io/d to visualize.
// Includes the full CRM billing layer: membership_plans, membership_plan_prices,
// gym_discounts, member_memberships, member_membership_applied_discounts,
// member_invoices, member_invoice_line_items, member_invoice_applied_discounts,
// member_charges, stripe_webhook_events. Member
// identity + billing live together on the unified `members` table (billing columns
// are service-role-written, NULL for engagement-only members); `member_billing_profile`
// is a filtered view of it (stripe_customer_id IS NOT NULL). Class scheduling is
// identity (gym_classes) + append-only versioned schedule shape
// (gym_class_schedules, frozen timezone per version); exceptions split into
// instance vs range; occurrences are computed, never stored — attendance and
// sign-ups key an occurrence by its ORIGINAL slot (class_id + original_date +
// original_time, the owning version's slot before exceptions).

Table auth_users {
  id uuid [primary key]
  email varchar
  created_at timestamp
}

Table gyms {
  gym_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_name varchar [not null]
  gym_description varchar
  timezone text [not null, default: 'America/Chicago']
  is_rank_enabled boolean [not null, default: true]
  stripe_account_id text [unique, note: 'nullable; Stripe Connect account id; service-role-only write']
  stripe_onboarding_status stripe_onboarding_status [not null, default: 'not_started', note: 'enum: not_started | pending | complete | disabled']
  theme_design_id text [note: 'nullable; ThemeService design_id; written by presets import']
}

Table gym_employees {
  employee_id uuid [primary key, default: `uuid_generate_v4()`]
  user_id uuid [note: 'FK to auth.users, nullable until onboarding']
  gym_id uuid [not null]
  employee_type varchar [not null, note: 'enum: owner, admin, trainer']
  first_name varchar [not null]
  last_name varchar [not null]
  phone varchar
  email varchar
  employee_pic_url varchar
  employee_public_description varchar
  theme_preference varchar [not null, default: 'system', note: 'enum: system, light, dark']
  created_at timestamptz [not null, default: `now()`]

  indexes {
    (user_id, gym_id) [unique]
    (employee_id, gym_id) [unique]
  }
}

Table rank_presets {
  preset_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_type varchar [not null, note: 'enum: bjj, mma, generic']
  main_rank_num_order integer [not null]
  sub_rank_num_order integer [not null]
  main_name varchar [not null]
  sub_name varchar [not null]
  classes_till_rankup integer [not null]
  image_url varchar
  color varchar [note: 'hex like #1F6FEB, optional']
  created_at timestamptz [not null, default: `now()`]

  indexes {
    (gym_type, main_rank_num_order, sub_rank_num_order) [unique]
  }
}

Table gym_ranks {
  rank_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_id uuid [not null]
  main_rank_num_order integer [not null]
  sub_rank_num_order integer [not null]
  main_name varchar [not null]
  sub_name varchar [not null]
  classes_till_rankup integer [not null]
  image_url varchar
  color varchar [note: 'hex like #1F6FEB, optional']
  created_at timestamptz [not null, default: `now()`]

  indexes {
    (rank_id, gym_id) [unique]
    (gym_id, main_rank_num_order, sub_rank_num_order) [unique]
  }
}

Table members {
  member_id uuid [primary key, default: `uuid_generate_v4()`]
  user_id uuid [note: 'nullable, linked when member joins mobile app']
  gym_id uuid [not null]
  created_at timestamptz [not null, default: `now()`]
  last_class timestamptz
  first_name varchar [not null]
  last_name varchar [not null]
  email varchar
  points_balance integer [not null, default: 0]
  current_rank_id uuid [note: 'nullable, FK to gym_ranks (composite with gym_id)']
  // --- merged billing/contact/Stripe (service_role-written; NULL for engagement-only members) ---
  photo_url varchar
  phone varchar
  address varchar
  emergency_contact_name varchar
  emergency_contact_phone varchar
  emergency_contact_email varchar
  freeze_start_date date [note: 'nullable; must pair with freeze_end_date']
  freeze_end_date date [note: 'nullable']
  stripe_customer_id varchar [note: 'immutable once set (trigger); member_billing_profile view filters WHERE NOT NULL']
  stripe_sub_id_month varchar
  stripe_payment_method_id varchar
  payment_type varchar
  card_brand varchar
  card_last_four varchar(4)
  card_exp_month integer
  card_exp_year integer
  total_monthly_recurring_price integer [not null, default: 0, note: 'CHECK >= 0']

  indexes {
    (user_id, gym_id) [unique, note: 'partial WHERE user_id IS NOT NULL']
    (member_id, gym_id) [unique]
    stripe_customer_id [unique]
  }
}

Table gym_classes {
  class_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_id uuid [not null]
  class_name varchar [not null]
  class_description varchar
  allowed_plan_ids jsonb [note: 'plan_id strings allowed; NULL = all plans (check-in eligibility gate)']
  max_capacity integer [note: 'room capacity; gated at check-in/sign-up time, per-occurrence override on class_instance_exceptions']
  image_url varchar [not null, note: 'every class has an image -- writers fill the platform default (people-in-a-gym photo) when none is provided']
  points_worth integer [not null, default: 50]
  is_active boolean [not null, default: true]
  is_deleted boolean [not null, default: false]
  created_at timestamptz [not null, default: `now()`]
}

Table gym_class_schedules {
  schedule_id uuid [primary key, default: `uuid_generate_v4()`]
  class_id uuid [not null]
  gym_id uuid [not null]
  effective_from timestamptz [not null, note: 'version boundary, server now() at mint; coverage = [effective_from, next version)']
  timezone text [not null, note: 'IANA zone frozen at mint; the version expands with its OWN zone forever']
  duration_minutes integer [not null]
  recurring_unit varchar [not null, note: 'enum: daily, weekly, monthly']
  recurring_interval integer [not null, default: 1]
  weekday_slots jsonb [not null, note: 'day -> ordered slot list [{time, instructor_id}]; weekly = sun..sat keys, daily/monthly = the reserved "all" key; several slots per day allowed; instructor_id app-validated (no FK inside JSONB)']
  start_date date [not null, note: 'recurrence range start (shape), NOT the version boundary']
  end_date date

  indexes {
    (class_id, effective_from) [unique]
  }
}

Table class_instance_exceptions {
  exception_id uuid [primary key, default: `uuid_generate_v4()`]
  class_id uuid [not null]
  gym_id uuid [not null]
  original_date date [not null]
  original_time time [not null, note: 'the bound original slot -- two same-day occurrences are overridden independently']
  is_cancelled boolean [not null, default: false]
  new_class_time time
  new_duration_minutes integer
  new_max_capacity integer
  new_instructor_id uuid
  new_date date
  created_at timestamptz [not null, default: `now()`]

  indexes {
    (class_id, original_date, original_time) [unique]
  }
}

Table class_range_exceptions {
  exception_id uuid [primary key, default: `uuid_generate_v4()`]
  class_id uuid [not null]
  gym_id uuid [not null]
  start_date date [not null]
  end_date date [not null]
  is_cancelled boolean [not null, default: false]
  new_instructor_id uuid
  created_at timestamptz [not null, default: `now()`]
}

Table member_attendance {
  log_id uuid [primary key, default: `uuid_generate_v4()`]
  member_id uuid [not null]
  gym_id uuid [not null]
  class_id uuid [not null]
  original_date date [not null, note: 'occurrence identity: the owning schedule version original slot']
  original_time time [not null, note: 'occurrence identity (part of the unique key -- a class may occur several times per day)']
  occurred_at timestamptz [not null, note: 'denormalized EFFECTIVE start; consumed only by streak/cycle/last_class window SQL']
  plan_id uuid [note: 'FK (plan_id, gym_id) -> membership_plans_unfiltered; billing attribution. NULL together with item_id for a no-membership admin check-in']
  item_id uuid [note: 'FK (item_id, member_id) -> member_memberships_unfiltered; covering membership. NULL together with plan_id for a no-membership admin check-in']

  indexes {
    (member_id, class_id, original_date, original_time) [unique]
    (member_id, gym_id)
    (class_id, original_date, original_time)
    (member_id, occurred_at)
  }
}

Table class_signups {
  signup_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_id uuid [not null]
  class_id uuid [not null]
  member_id uuid [not null]
  original_date date [not null, note: 'occurrence identity: the owning schedule version original slot -- NOT attendance']
  original_time time [not null, note: 'occurrence identity (part of the unique key -- a class may occur several times per day)']
  created_at timestamptz [not null, default: `now()`]

  indexes {
    (class_id, member_id, original_date, original_time) [unique]
    (class_id, original_date, original_time)
    (member_id, gym_id)
  }
}

Table gym_rewards {
  reward_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_id uuid [not null]
  title varchar [not null]
  amount_off varchar
  image_url varchar
  point_cost integer [not null]
  price_label varchar [note: 'nullable; display label for the reward price / value (e.g. "$50 off")']
  is_active boolean [not null, default: true]
  created_at timestamptz [not null, default: `now()`]

  indexes {
    (reward_id, gym_id) [unique]
  }
}

Table member_reward_redemptions {
  redemption_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_id uuid [not null]
  member_id uuid [not null]
  reward_id uuid [not null]
  point_cost integer [not null, note: 'snapshot at redemption time']
  redeemed_at timestamptz [not null, default: `now()`]
  status reward_redemption_status [not null, default: 'pending', note: 'backend-written']
  decided_at timestamptz [note: 'backend-written; set when admin approves/rejects']
}

Table gym_waivers {
  waiver_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_id uuid [not null]
  name varchar [not null]
  current_version_id uuid
  is_deleted boolean [not null, default: false]
  waiver_type waiver_type [not null, default: 'custom', note: 'payer_auth = undeletable authorized-payer agreement (<=1 per gym, never plan-attachable); custom = normal gym waiver']
  created_at timestamptz [not null, default: `now()`]
  updated_at timestamptz [not null, default: `now()`]

  indexes {
    (waiver_id, gym_id) [unique]
  }
}

Table gym_waiver_versions {
  version_id uuid [primary key, default: `uuid_generate_v4()`]
  waiver_id uuid [not null]
  gym_id uuid [not null]
  version_number integer [not null]
  body text [not null]
  content_hash varchar [not null]
  requires_resign boolean [not null, default: true]
  created_at timestamptz [not null, default: `now()`]

  indexes {
    (version_id, gym_id) [unique]
    (waiver_id, version_number) [unique]
  }
}

Table member_waiver_signatures {
  signature_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_id uuid [not null]
  member_id uuid [not null]
  waiver_id uuid [not null]
  waiver_version_id uuid [not null]
  signed_at timestamptz [not null, default: `now()`]
  signer_name varchar [not null]
  signature_type waiver_signature_type [not null, default: 'typed']
  consent_acknowledged boolean [not null]
  ip_address inet [not null]
  user_agent varchar [not null]
  rendered_body text [not null]
  content_hash varchar [not null]
  esign_disclosure_version varchar [not null, default: 'esign-v1']
  operator_employee_id uuid
}

Ref: member_waiver_signatures.operator_employee_id > gym_employees.employee_id

Table member_authorized_payers {
  member_id uuid [not null]
  payer_member_id uuid [not null]
  gym_id uuid [not null]
  signature_id uuid [not null]
  created_at timestamptz [not null, default: `now()`]

  indexes {
    (member_id, payer_member_id) [pk]
  }
}

Table member_activities {
  activity_id uuid [primary key, default: `uuid_generate_v4()`]
  member_id uuid [not null]
  gym_id uuid [not null]
  activity_type varchar [not null]
  activity_info jsonb [default: '{}']
  time timestamptz [not null, default: `now()`]
}

Table gym_history {
  gym_id uuid [not null]
  date date [not null]
  total_active integer [not null]
  total_inactive integer [not null]
  went_inactive integer [not null]
  became_active integer [not null]

  indexes {
    (gym_id, date) [pk]
  }
}

// Foreign keys
Ref: gym_employees.user_id > auth_users.id
Ref: gym_employees.gym_id > gyms.gym_id

Ref: members.user_id > auth_users.id
Ref: members.gym_id > gyms.gym_id
Ref: members.current_rank_id > gym_ranks.rank_id

Ref: gym_ranks.gym_id > gyms.gym_id

Ref: gym_classes.gym_id > gyms.gym_id

Ref: gym_class_schedules.class_id > gym_classes.class_id
Ref: gym_class_schedules.gym_id > gyms.gym_id

Ref: class_instance_exceptions.class_id > gym_classes.class_id
Ref: class_instance_exceptions.gym_id > gyms.gym_id
Ref: class_instance_exceptions.new_instructor_id > gym_employees.employee_id

Ref: class_range_exceptions.class_id > gym_classes.class_id
Ref: class_range_exceptions.gym_id > gyms.gym_id
Ref: class_range_exceptions.new_instructor_id > gym_employees.employee_id

Ref: member_attendance.member_id > members.member_id
Ref: member_attendance.gym_id > gyms.gym_id
Ref: member_attendance.class_id > gym_classes.class_id
Ref: member_attendance.plan_id > membership_plans_unfiltered.plan_id
Ref: member_attendance.item_id > member_memberships_unfiltered.item_id

Ref: class_signups.gym_id > gyms.gym_id
Ref: class_signups.class_id > gym_classes.class_id
Ref: class_signups.member_id > members.member_id

Ref: gym_rewards.gym_id > gyms.gym_id

Ref: member_reward_redemptions.gym_id > gyms.gym_id
Ref: member_reward_redemptions.member_id > members.member_id
Ref: member_reward_redemptions.reward_id > gym_rewards.reward_id

Ref: gym_waivers.gym_id > gyms.gym_id
Ref: gym_waivers.current_version_id > gym_waiver_versions.version_id
Ref: gym_waiver_versions.waiver_id > gym_waivers.waiver_id
Ref: gym_waiver_versions.gym_id > gyms.gym_id
Ref: member_waiver_signatures.gym_id > gyms.gym_id
Ref: member_waiver_signatures.member_id > members.member_id
Ref: member_waiver_signatures.waiver_id > gym_waivers.waiver_id
Ref: member_waiver_signatures.waiver_version_id > gym_waiver_versions.version_id

Ref: member_authorized_payers.member_id > members.member_id
Ref: member_authorized_payers.payer_member_id > members.member_id
Ref: member_authorized_payers.gym_id > gyms.gym_id
Ref: member_authorized_payers.signature_id > member_waiver_signatures.signature_id

Ref: member_activities.member_id > members.member_id
Ref: member_activities.gym_id > gyms.gym_id

Ref: gym_history.gym_id > gyms.gym_id

// ============================================================
// CRM billing layer
// _unfiltered base tables exist in DB; the filtered views (stripe_*_id IS NOT
// NULL) are exposed to the app. Diagram shows the underlying table shapes.
// ============================================================

Table membership_plans_unfiltered {
  plan_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_id uuid [not null]
  plan_name varchar [not null]
  plan_type varchar [not null, note: 'CHECK: trial | recurring | one_time']
  class_count integer [note: 'nullable; required for class-count plans']
  duration_amount integer [note: 'nullable; must pair with duration_unit']
  duration_unit varchar [note: 'nullable; CHECK: week | month | year']
  is_public boolean [not null, default: true]
  is_deleted boolean [not null, default: false]
  stripe_product_id varchar [note: 'set by backend; view filters WHERE NOT NULL']
  waiver_ids jsonb [not null, default: `'[]'`, note: 'array of waiver_id strings (multi-select; no FK)']
  created_at timestamptz [not null, default: `now()`]

  indexes {
    (plan_id, gym_id) [unique]
  }
}

Table membership_plan_prices_unfiltered {
  price_id uuid [primary key, default: `uuid_generate_v4()`]
  plan_id uuid [not null]
  gym_id uuid [not null]
  stripe_price_id varchar [note: 'set by backend; view filters WHERE NOT NULL']
  price integer [not null, note: 'CHECK >= 0']
  is_active boolean [not null, default: true]
  created_at timestamptz [not null, default: `now()`]

  indexes {
    (price_id, plan_id) [unique]
    plan_id [unique, note: 'partial WHERE is_active = TRUE (max one active price per plan)']
  }
}

Table gym_discounts_unfiltered {
  discount_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_id uuid [not null]
  discount_name varchar [not null, note: 'editable identity']
  discount_type discount_type [not null, note: 'enum: preset | custom']
  is_deleted boolean [not null, default: false]
  created_at timestamptz [not null, default: `now()`]
  // IDENTITY only. The percent/dollar + lifetime live on gym_discount_values (versioned).

  indexes {
    (discount_id, gym_id) [unique]
  }
}

// Versioned, immutable discount VALUE rows (mirrors membership_plan_prices).
// Editing a discount's value inserts a NEW active version + deactivates the old
// one (permanent paper trail). Applied snapshots reference value_id, freezing
// the member's discount to that exact version. Plain gym config — the coupon is
// computed at sync and written onto the applied snapshot, not stored here.
Table gym_discount_values_unfiltered {
  value_id uuid [primary key, default: `uuid_generate_v4()`]
  discount_id uuid [not null, note: 'FK (discount_id, gym_id) -> gym_discounts_unfiltered']
  gym_id uuid [not null]
  percentage_off float [note: 'nullable; exactly one of percentage_off/dollar_off set']
  dollar_off integer [note: 'nullable']
  duration_amount integer [note: 'nullable; pairs with duration_unit']
  duration_unit discount_duration_unit [note: 'nullable; enum: day | week | month | cycle (plan-relative)']
  end_date date [note: 'nullable; explicit absolute end; XOR with duration span']
  is_active boolean [not null, default: true, note: 'the one mutable column']
  created_at timestamptz [not null, default: `now()`]
  // lifetime: (duration_amount+duration_unit) XOR end_date; neither = forever. 1 cycle = the single-invoice discount (replaced once mode).

  indexes {
    (value_id, gym_id) [unique]
    discount_id [note: 'partial unique WHERE is_active: <=1 active version per discount']
  }
}

// member_billing_profile was merged into the unified `members` table above;
// `member_billing_profile` is now a filtered view (stripe_customer_id IS NOT NULL).

Table member_memberships_unfiltered {
  item_id uuid [primary key, default: `uuid_generate_v4()`]
  member_id uuid [not null]
  paid_by_member_id uuid [not null, note: 'who PAYS this row: the resolved parent or a self-paying linked member; the sync groups by this (one subscription per payer); immutable (trigger) — payer change = cancel-old + insert-new; FK (paid_by_member_id, gym_id) -> members(member_id, gym_id)']
  gym_id uuid [not null]
  plan_id uuid [not null, note: 'immutable (trigger)']
  price_id uuid [not null]
  start_date date [not null]
  end_date date [note: 'nullable; forbidden for recurring plans']
  cancel_date date [note: 'nullable; locks only once removed from Stripe (stripe_sync_status=deleted); clearable while unconfirmed (the cancel revert)']
  last_paid_date date [note: 'gym-local']
  next_due_date date [note: 'gym-local']
  stripe_item_id varchar [note: 'immutable once set EXCEPT while migrating (price migration moves the line); never nulled (historical line record)']
  stripe_one_time_invoice_id varchar [note: 'ONE-TIME only: the consolidated invoice (in_) this membership was billed on; stripe_item_id holds the per-membership LINE id, this holds the shared invoice id; NULL for recurring; immutable once set']
  total_price integer [not null, note: 'CHECK >= 0']
  quantity integer [not null, default: 1, note: 'CHECK > 0; how many units this row bills as. one_time/trial packs stack as ONE row with quantity = N (one Stripe line with that quantity, $-coupon applies once, class_count*quantity classes); recurring forced = 1 (trigger); set at INSERT, immutable after']
  stripe_sync_status stripe_sync_status [not null, default: 'not_added', note: 'not_added = pending; sync stamps applied/deleted; migrating = price migration ONLY (unlocks the stripe_item_id move); client view hides not_added/preview_*; orthogonal to lifecycle status view']
  idempotency_key uuid [note: 'nullable; set once at INSERT (service_role); partial unique WHERE NOT NULL; one-time/trial start dedup key (C-086) — retried start reproduces same key, collides, INSERT DO NOTHING drops duplicate rows; NULL for recurring + preview rows']
  created_at timestamptz [not null, default: `now()`]

  indexes {
    (item_id, member_id) [unique]
    (item_id, gym_id) [unique]
    idempotency_key [note: 'partial unique WHERE idempotency_key IS NOT NULL']
  }
}

// Applied-discount snapshots (slim, version model): one row = one discount
// frozen onto one membership (item_id), referencing the immutable
// gym_discount_values version (value_id = the provenance / version tag). Apply =
// INSERT, remove = DELETE, never an edit. end_date + stripe_coupon_id are sync
// writebacks. The view exposes only rows with stripe_coupon_id written back.
Table member_membership_applied_discounts_unfiltered {
  applied_discount_id uuid [primary key, default: `uuid_generate_v4()`]
  item_id uuid [not null, note: 'FK (item_id, gym_id) -> member_memberships_unfiltered']
  member_id uuid [not null]
  gym_id uuid [not null]
  value_id uuid [not null, note: 'FK (value_id, gym_id) -> gym_discount_values_unfiltered; the version tag']
  end_date date [note: 'nullable; resolved absolute end / once-consumption stamp (sync)']
  stripe_coupon_id varchar [note: 'nullable; SYSTEM writeback; view filters WHERE NOT NULL']
  stripe_sync_status stripe_sync_status [not null, default: 'not_added', note: 'not_added = pending; sync stamps applied/deleted']
  created_at timestamptz [not null, default: `now()`]

  indexes {
    item_id
    (member_id, gym_id)
    value_id
  }
}

Table member_invoices {
  invoice_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_id uuid [not null]
  paid_by_member_id uuid [not null, note: 'the payer (billed customer)']
  paid_for jsonb [not null, default: '[]', note: 'beneficiary member_id list']
  status varchar [not null, default: 'open', note: 'enum: open | paid']
  total_amount integer [not null, note: 'CHECK >= 0']
  currency char(3) [not null, default: 'usd']
  stripe_invoice_id varchar [unique, note: 'nullable']
  stripe_payment_intent_id varchar [unique, note: 'nullable']
  invoice_time timestamptz [not null, default: `now()`]
  stripe_event_payload jsonb

  indexes {
    (invoice_id, gym_id) [unique]
    (paid_by_member_id, gym_id, invoice_time)
    (gym_id, invoice_time)
    paid_for [type: gin]
  }
}

Table member_invoice_line_items {
  line_item_id varchar [primary key, note: 'Stripe line item id (il_xxx)']
  invoice_id uuid [not null]
  gym_id uuid [not null]
  item_type varchar [not null, note: 'enum: membership | custom']
  name varchar [not null]
  amount integer [not null, note: 'CHECK >= 0 (line total, post-qty)']
  quantity integer [not null, note: 'default 1; CHECK > 0']
  stripe_product_id varchar
  item_id uuid [note: 'nullable; required when item_type = membership']

  indexes {
    invoice_id
    item_id [note: 'partial WHERE item_id IS NOT NULL']
  }
}

Table member_invoice_applied_discounts {
  applied_discount_id uuid [primary key, default: `uuid_generate_v4()`]
  invoice_id uuid [not null]
  gym_id uuid [not null]
  discount_id uuid [note: 'nullable; not resolved to a CRM discount']
  line_item_id varchar [not null, note: 'Stripe invoice line id (il_...); audit value, not FK-enforced; one row per coupon per line']
  amount_off integer [not null, note: 'snapshot at invoice time; CHECK >= 0']
  stripe_coupon_id varchar [not null, note: 'the identifier; captured at invoice time']

  indexes {
    invoice_id
    (invoice_id, stripe_coupon_id, line_item_id) [unique, note: 'idempotent on webhook re-delivery; one row per coupon per invoice line']
  }
}

Table member_charges {
  charge_id uuid [primary key, default: `uuid_generate_v4()`]
  invoice_id uuid [not null]
  gym_id uuid [not null]
  paid_by_member_id uuid [not null, note: 'the payer (billed customer)']
  kind varchar [not null, note: 'enum: payment | refund']
  status varchar [not null, note: 'enum: pending | succeeded | failed']
  amount integer [not null, note: 'signed: payment >= 0, refund <= 0']
  currency char(3) [not null, default: 'usd']
  payment_method_type varchar
  card_last_four varchar [note: 'last 4 of the card, when on a card']
  stripe_charge_id varchar [unique, note: 'nullable']
  stripe_refund_id varchar [unique, note: 'nullable']
  refunds_charge_id uuid [note: 'nullable; self-FK to member_charges(charge_id)']
  charge_time timestamptz [not null, default: `now()`]
  stripe_event_payload jsonb

  indexes {
    invoice_id
    (paid_by_member_id, gym_id, charge_time)
    (gym_id, charge_time)
  }
}

Table stripe_webhook_events {
  event_id varchar [primary key, note: 'Stripe event id']
  gym_id uuid [not null]
  event_type varchar [not null]
  processed_at timestamptz [not null, default: `now()`]

  indexes {
    (gym_id, processed_at)
  }
}

// Billing layer refs
Ref: membership_plans_unfiltered.gym_id > gyms.gym_id
Ref: membership_plan_prices_unfiltered.plan_id > membership_plans_unfiltered.plan_id
Ref: membership_plan_prices_unfiltered.gym_id > gyms.gym_id
Ref: gym_discounts_unfiltered.gym_id > gyms.gym_id

// member_billing_profile_unfiltered FKs merged into `members` (see members refs above).

Ref: member_memberships_unfiltered.member_id > members.member_id
Ref: member_memberships_unfiltered.paid_by_member_id > members.member_id
Ref: member_memberships_unfiltered.gym_id > gyms.gym_id
Ref: member_memberships_unfiltered.plan_id > membership_plans_unfiltered.plan_id
Ref: member_memberships_unfiltered.price_id > membership_plan_prices_unfiltered.price_id

Ref: member_membership_applied_discounts_unfiltered.item_id > member_memberships_unfiltered.item_id
Ref: member_membership_applied_discounts_unfiltered.member_id > members.member_id
Ref: member_membership_applied_discounts_unfiltered.gym_id > gyms.gym_id
Ref: member_membership_applied_discounts_unfiltered.value_id > gym_discount_values_unfiltered.value_id
Ref: gym_discount_values_unfiltered.discount_id > gym_discounts_unfiltered.discount_id
Ref: gym_discount_values_unfiltered.gym_id > gyms.gym_id

Ref: member_invoices.paid_by_member_id > members.member_id
Ref: member_invoices.gym_id > gyms.gym_id

Ref: member_invoice_line_items.invoice_id > member_invoices.invoice_id
Ref: member_invoice_line_items.gym_id > gyms.gym_id
Ref: member_invoice_line_items.item_id > member_memberships_unfiltered.item_id

Ref: member_invoice_applied_discounts.invoice_id > member_invoices.invoice_id
Ref: member_invoice_applied_discounts.gym_id > gyms.gym_id
Ref: member_invoice_applied_discounts.discount_id > gym_discounts_unfiltered.discount_id

Ref: member_charges.invoice_id > member_invoices.invoice_id
Ref: member_charges.gym_id > gyms.gym_id
Ref: member_charges.paid_by_member_id > members.member_id
Ref: member_charges.refunds_charge_id > member_charges.charge_id

Ref: stripe_webhook_events.gym_id > gyms.gym_id

// Backend-executed tracked operations (background ops the CRM polls).
Table tasks {
  task_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_id uuid [not null]
  task_type task_type [not null, note: 'enum: membership_reprice']
  status task_status [not null, default: 'pending', note: 'enum: pending | running | completed | failed']
  created_at timestamptz [not null, default: `now()`]
  started_at timestamptz
  finished_at timestamptz

  indexes {
    (gym_id, status)
    status [note: 'partial: pending/running (crash-recovery sweep)']
  }
}

Table task_items {
  task_item_id uuid [primary key, default: `uuid_generate_v4()`]
  task_id uuid [not null]
  gym_id uuid [not null]
  member_id uuid [not null]
  status task_status [not null, default: 'pending']
  attempt_count integer [not null, default: 0]
  error_message text
  old_item_id uuid [note: 'membership row the op acts on']
  new_item_id uuid [note: 'successor row; stamped in the op transaction = DB phase done']
  target_price_id uuid [note: 'membership_reprice param']
  proration_behavior proration_behavior [note: 'membership_reprice param']
  created_at timestamptz [not null, default: `now()`]
  started_at timestamptz
  finished_at timestamptz

  indexes {
    task_id
    old_item_id [note: 'partial: NOT NULL (in-task guard)']
    new_item_id [note: 'partial: NOT NULL (in-task guard + orphan-sweep exclusion)']
  }
}

Ref: tasks.gym_id > gyms.gym_id
Ref: task_items.task_id > tasks.task_id
Ref: task_items.gym_id > gyms.gym_id
Ref: task_items.member_id > members.member_id
Ref: task_items.old_item_id > member_memberships_unfiltered.item_id
Ref: task_items.new_item_id > member_memberships_unfiltered.item_id
Ref: task_items.target_price_id > membership_plan_prices_unfiltered.price_id

// ============================================================
// VideoService demo content (video_* tables). The gym here is a gym-TYPE
// template keyed by a text id (e.g. 'boxing') — NOT the customer `gyms` table.
// ============================================================

Table video_gym {
  gym_id text [primary key, note: 'text id == YAML filename stem']
  gym_type jsonb [not null, note: 'JSONB array of disciplines; [0] = primary (drives parent_gym_type)']
  theme varchar [not null, note: 'ThemeService design id']
  short_videos_desc text
  short_avoid_desc text
  videos_desc text [not null]
  avoid_desc text [not null]
  has_classes boolean [not null, default: false]
  has_rewards boolean [not null, default: false]
}

Table video_gym_query {
  query_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_id text [not null]
  query text [not null]
}

Table video_gym_class {
  class_id uuid [primary key, default: `uuid_generate_v4()`, note: 'serve ORDER BY name']
  gym_id text [not null]
  name text [not null]
  image_url text [not null]
  description text [not null]
  instructor_name text [not null]
  instructor_bio text [not null]
  instructor_image_url text [not null]
}

Table video_gym_reward {
  reward_id uuid [primary key, default: `uuid_generate_v4()`, note: 'serve ORDER BY points_cost']
  gym_id text [not null]
  title text [not null]
  image_url text [not null]
  price_label text [not null]
  points_cost integer [not null]
}

Table video {
  video_id text [primary key, note: 'YouTube id']
  url text [not null]
  title text [not null]
  description text [not null, default: '']
  thumbnail_url text [not null]
  channel_name text [not null]
  channel_url text [not null]
  channel_avatar_url text [not null, default: '', note: 'empty post-scrape; backfilled at serve']
  view_count integer
  like_count integer
  duration_seconds integer
  tag video_genre [note: 'enum: single content genre; null until classified']
  disciplines jsonb [not null, default: '[]', note: 'JSONB array of disciplines (GIN-indexed for the scan slice)']
  source_queries jsonb [not null, default: '[]', note: 'JSONB array; tracing only']
  relevance_index integer [not null]
  transcript_error text
  transcript text
  gym_id uuid [note: 'owning gym for a custom owner-added video (private); NULL = shared web-query/scraped']
  added_via video_source [not null, default: 'web_query', note: 'enum: web_query | manual — how it entered + whether deletable (web_query = reject only, manual = hard delete)']
}

Ref: video.gym_id > gyms.gym_id

Table video_gym_feed {
  gym_id text [not null]
  video_id text [not null]
  status video_gym_feed_status [not null, note: 'enum: good | rejected']

  indexes {
    (gym_id, video_id) [pk]
    (gym_id, status)
  }
}

Table video_cost_log {
  entry_id uuid [primary key, default: `uuid_generate_v4()`, note: 'append-only']
  execution_type video_execution_type [not null, note: 'enum: search|transcript|tag|scan']
  gym_id text [note: 'set on scan entries; NULL for pool-wide search/tag runs']
  at timestamptz [not null]
  breakdown jsonb [not null, default: '{}', note: 'USD component map']
  note text
}

Ref: video_gym_query.gym_id > video_gym.gym_id
Ref: video_gym_class.gym_id > video_gym.gym_id
Ref: video_gym_reward.gym_id > video_gym.gym_id

Ref: video_gym_feed.gym_id > video_gym.gym_id
Ref: video_gym_feed.video_id > video.video_id
Ref: video_cost_log.gym_id > video_gym.gym_id

// ============================================================
// Real-gym video content (gym_video_* tables). These reference the
// customer `gyms` table (UUID gym_id) and the shared `video` pool.
// Written by the presets import (PresetsService); read by FastApiBackend
// videos domain (VideosService). Separate from the template video_gym* tables.
// ============================================================

// gym_video_spec is APPEND-ONLY VERSIONED. Rows are never UPDATE'd.
// The gym_video_spec_latest VIEW surfaces the most-recent version per gym;
// all read paths use that view, not the table directly.
// Three writers stamp distinct source values: admin_update (videos agent/save — src/videos/service/video_agent/),
// system_update (presets import — src/presets/), feed_update (VideoFeedRefiner — src/videos/service/).
Table gym_video_spec {
  spec_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_id uuid [not null, note: 'FK to gyms.gym_id (real customer gym); NOT unique — multiple version rows per gym']
  videos_desc text [not null]
  avoid_desc text [not null]
  short_videos_desc text
  short_avoid_desc text
  queries jsonb [not null, default: `'[]'`, note: 'array of search query strings (was gym_video_query table — now folded in)']
  source gym_video_spec_source [not null, note: 'enum: admin_update | system_update | feed_update']
  created_at timestamptz [not null, default: `now()`]

  indexes {
    gym_id [note: 'non-unique — multiple versions per gym; order by created_at DESC to get latest']
  }
}

Table video_run {
  run_id uuid [primary key, default: `gen_random_uuid()`]
  gym_id uuid [not null, note: 'FK to gyms.gym_id']
  created_at timestamptz [not null, default: `now()`]
}

Table gym_video_feed {
  feed_id uuid [primary key, default: `gen_random_uuid()`, note: 'surrogate PK']
  gym_id uuid [not null, note: 'FK to gyms.gym_id']
  video_id text [not null, note: 'FK to video.video_id']
  video_run_id uuid [note: 'NULL = owner "Your videos" section (always served); set = a scan run (served only while latest)']
  scan_status gym_video_scan_status [not null, default: 'accepted', note: 'enum: accepted | rejected']
  curation_type gym_video_curation_type [not null, default: 'automatic', note: 'enum: automatic | manual; how the current scan_status was set']
  curation_reason text [note: 'nullable; owner free-text reason for the latest manual curation; NULL for automatic rows']
  rejected_at timestamptz [note: 'last rejection time; retained across re-acceptance (history)']
  curated_at timestamptz [note: 'nullable; when the owner last manually curated this row (reject/keep/re-add)']
}

// gym_video_query was DROPPED — queries now live in gym_video_spec.queries JSONB.

Ref: gym_video_spec.gym_id > gyms.gym_id
Ref: video_run.gym_id > gyms.gym_id
Ref: gym_video_feed.gym_id > gyms.gym_id
Ref: gym_video_feed.video_id > video.video_id
Ref: gym_video_feed.video_run_id > video_run.run_id
