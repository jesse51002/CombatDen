/// Whether an employee's email grants a usable login.
///
/// Derived by the backend at read time from the `auth.users` join (mirrors no
/// Postgres enum): [active] = a verified Supabase account exists for the email;
/// [pending] = a row exists but no verified account yet; [none] = the row has
/// no email (an email-less instructor — data, never a login principal).
/// [unknown] is a forward-compat fallback so a new backend value never crashes
/// the UI (resilient enum parsing).
enum InviteStatus {
  active('active'),
  pending('pending'),
  none('none'),
  unknown('unknown');

  final String value;
  const InviteStatus(this.value);

  static InviteStatus fromJson(String value) => InviteStatus.values.firstWhere(
        (s) => s.value == value,
        orElse: () => InviteStatus.unknown,
      );
}
