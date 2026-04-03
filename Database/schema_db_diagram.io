
Table auth_users {
  id uuid [primary key]
  email varchar
  created_at timestamp
}

Table gyms {
  gym_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_name varchar [not null]

}

Table user_gym_profiles {
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
  account_linked_to_id uuid [note: 'sub-account linked to primary member, must be same gym']

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
  revenue float [not null]

  indexes {
    (gym_id, date) [pk]
  }
}

Table user_gym_transactions {
  transaction_id uuid [primary key, default: `uuid_generate_v4()`]
  crm_user_id uuid [not null]
  gym_id uuid [not null]
  item_id uuid [not null]
  amount_paid float [not null]
  item_type varchar
  time timestamptz [not null, default: `now()`]
  applied_discounts jsonb
  extra_info jsonb [default: '{}']
}

Table membership_plans {
  plan_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_id uuid [not null]
  plan_name varchar [not null]
  plan_type varchar [not null, note: 'enum: trial, recurring, one_time']
  base_cost float [not null]
  additional_member_discount float [note: 'percentage off base_cost for linked members, e.g. 20 = 20% off']
  class_count integer [note: 'nullable, number of classes included']
  duration_amount integer [not null, note: 'e.g. 1, 3, 6']
  duration_unit varchar [not null, note: 'enum: week, month, year']
  is_public boolean [not null, default: true]
  is_deleted boolean [not null, default: false]
  created_at timestamptz [not null, default: `now()`]
}

Table member_memberships {
  crm_user_id uuid [not null]
  gym_id uuid [not null]
  plan_id uuid [not null]
  end_date date
  cancel_date date
  freeze_start_date date
  freeze_end_date date
  start_date date [not null]
  last_paid_date date
  next_due_date date
  total_price float [not null]
  discount_ids jsonb [note: 'array of gym_discounts discount_id refs, validated by trigger']
  created_at timestamptz [not null, default: `now()`]

  indexes {
    (crm_user_id, gym_id, plan_id) [pk]
  }
}

Table gym_discounts {
  discount_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_id uuid [not null]
  discount_name varchar [not null]
  discount_type varchar [not null, note: 'enum: membership, custom']
  discount_active boolean [not null, default: true]
  percentage_off float [note: 'exactly one of percentage_off or dollar_off must be set']
  dollar_off float [note: 'exactly one of percentage_off or dollar_off must be set']
  start_date date [not null]
  end_date date [not null]
  is_deleted boolean [not null, default: false]
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

// --- Integrity Notes ---
// user_gym_profiles: UNIQUE partial index on (user_id, gym_id) WHERE user_id IS NOT NULL — prevents same auth user linking to multiple profiles in one gym
// user_gym_profiles: self-referencing composite FK on account_linked_to_id ensures linked account belongs to the same gym
// member_memberships: trigger on discount_ids validates all UUIDs exist in gym_discounts for the same gym
// member_memberships: status is derived via member_memberships_with_status view (cancelled > ended > frozen > active)

// --- Relationships ---

// gym_employees
Ref: auth_users.id < gym_employees.user_id
Ref: gyms.gym_id < gym_employees.gym_id

// user_gym_profiles
Ref: auth_users.id < user_gym_profiles.user_id
Ref: gyms.gym_id < user_gym_profiles.gym_id

// user_activities
Ref: user_gym_profiles.crm_user_id < user_activities.crm_user_id
Ref: gyms.gym_id < user_activities.gym_id

// gym_history
Ref: gyms.gym_id < gym_history.gym_id

// user_gym_transactions
Ref: user_gym_profiles.crm_user_id < user_gym_transactions.crm_user_id
Ref: gyms.gym_id < user_gym_transactions.gym_id

// membership_plans
Ref: gyms.gym_id < membership_plans.gym_id

// member_memberships
Ref: user_gym_profiles.crm_user_id < member_memberships.crm_user_id
Ref: gyms.gym_id < member_memberships.gym_id
Ref: membership_plans.plan_id < member_memberships.plan_id
// user_gym_profiles (self-ref for linked accounts)
Ref: user_gym_profiles.crm_user_id < user_gym_profiles.account_linked_to_id

// gym_discounts
Ref: gyms.gym_id < gym_discounts.gym_id

// gym_rewards
Ref: gyms.gym_id < gym_rewards.gym_id
