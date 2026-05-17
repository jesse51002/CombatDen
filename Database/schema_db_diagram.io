// dbdiagram.io markup — paste into https://dbdiagram.io/d to visualize.
// Reflects the post-payment-pivot schema: no Stripe, no memberships,
// no invoices/charges/discounts. Class scheduling is embedded in
// gym_classes; exceptions split into instance vs range; class_history
// records past occurrences and member_attendance points at them.

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

  indexes {
    (user_id, gym_id) [unique, note: 'partial WHERE user_id IS NOT NULL']
    (member_id, gym_id) [unique]
  }
}

Table member_status {
  status_id uuid [primary key, default: `uuid_generate_v4()`]
  member_id uuid [not null]
  gym_id uuid [not null]
  status_type varchar [not null, note: 'enum: trial, full, disabled']
  start_date date [not null]
  end_date date [note: 'nullable = ongoing (current trial / current full / current disabled)']
  created_at timestamptz [not null, default: `now()`]

  // gist EXCLUDE (member_id =, daterange(start, end, []) &&) prevents overlap
  // No stored "inactive" — derived from absence of a covering row.
}

Table member_active {
  active_id uuid [primary key, default: `uuid_generate_v4()`]
  member_id uuid [not null]
  gym_id uuid [not null]
  active_type varchar [not null, note: 'enum: active, inactive']
  start_date date [not null]
  end_date date [note: 'nullable = ongoing']
  created_at timestamptz [not null, default: `now()`]

  // Same shape as member_status. Class-engagement axis, distinct from
  // membership-tier axis. Surfaced in members_with_status as `active` bool.
}

Table gym_classes {
  class_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_id uuid [not null]
  class_name varchar [not null]
  class_description varchar
  max_capacity integer
  is_active boolean [not null, default: true]
  is_deleted boolean [not null, default: false]
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
  start_date date [not null]
  end_date date
  created_at timestamptz [not null, default: `now()`]
}

Table class_instance_exceptions {
  exception_id uuid [primary key, default: `uuid_generate_v4()`]
  class_id uuid [not null]
  gym_id uuid [not null]
  original_date date [not null]
  is_cancelled boolean [not null, default: false]
  new_class_time time
  new_duration_minutes integer
  new_max_capacity integer
  new_instructor_id uuid
  created_at timestamptz [not null, default: `now()`]

  indexes {
    (class_id, original_date) [unique]
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

Table class_history {
  class_history_id uuid [primary key, default: `uuid_generate_v4()`]
  class_id uuid [not null]
  gym_id uuid [not null]
  instructor_id uuid
  occurred_at timestamptz [not null]
  duration_minutes integer [not null]
  created_at timestamptz [not null, default: `now()`]

  indexes {
    (class_history_id, gym_id) [unique]
    (class_id, occurred_at)
  }
}

Table member_attendance {
  log_id uuid [primary key, default: `uuid_generate_v4()`]
  member_id uuid [not null]
  gym_id uuid [not null]
  class_history_id uuid [not null]

  indexes {
    (member_id, class_history_id) [unique]
    (member_id, gym_id)
    (class_history_id)
  }
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

  indexes {
    (reward_id, gym_id) [unique]
  }
}

Table member_reward_redemptions {
  redemption_id uuid [primary key, default: `uuid_generate_v4()`]
  gym_id uuid [not null]
  member_id uuid [not null]
  reward_id uuid [not null]
  point_cost integer [not null]
  redeemed_at timestamptz [not null, default: `now()`]
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

Ref: member_status.member_id > members.member_id
Ref: member_status.gym_id > gyms.gym_id

Ref: member_active.member_id > members.member_id
Ref: member_active.gym_id > gyms.gym_id

Ref: gym_classes.gym_id > gyms.gym_id
Ref: gym_classes.sun_instructor_id > gym_employees.employee_id
Ref: gym_classes.mon_instructor_id > gym_employees.employee_id
Ref: gym_classes.tue_instructor_id > gym_employees.employee_id
Ref: gym_classes.wed_instructor_id > gym_employees.employee_id
Ref: gym_classes.thu_instructor_id > gym_employees.employee_id
Ref: gym_classes.fri_instructor_id > gym_employees.employee_id
Ref: gym_classes.sat_instructor_id > gym_employees.employee_id

Ref: class_instance_exceptions.class_id > gym_classes.class_id
Ref: class_instance_exceptions.gym_id > gyms.gym_id
Ref: class_instance_exceptions.new_instructor_id > gym_employees.employee_id

Ref: class_range_exceptions.class_id > gym_classes.class_id
Ref: class_range_exceptions.gym_id > gyms.gym_id
Ref: class_range_exceptions.new_instructor_id > gym_employees.employee_id

Ref: class_history.class_id > gym_classes.class_id
Ref: class_history.gym_id > gyms.gym_id
Ref: class_history.instructor_id > gym_employees.employee_id

Ref: member_attendance.member_id > members.member_id
Ref: member_attendance.gym_id > gyms.gym_id
Ref: member_attendance.class_history_id > class_history.class_history_id

Ref: gym_rewards.gym_id > gyms.gym_id

Ref: member_reward_redemptions.gym_id > gyms.gym_id
Ref: member_reward_redemptions.member_id > members.member_id
Ref: member_reward_redemptions.reward_id > gym_rewards.reward_id

Ref: member_activities.member_id > members.member_id
Ref: member_activities.gym_id > gyms.gym_id

Ref: gym_history.gym_id > gyms.gym_id
