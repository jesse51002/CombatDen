/// Catalog of ``{{placeholder}}`` tokens a waiver body may use.
///
/// This is the single Dart home for the placeholder KEY NAMES — a hand-synced
/// mirror of `Database/python_data/schema/waiver_parameters.py`'s
/// `WaiverParameter` enum (kept in lockstep by hand; Dart can't import the
/// Python module). Render-value builders (`_renderValues()` in the sign-waiver
/// dialogs) MUST key off these constants, never a string literal.
/// The backend fills these at sign time; the CRM waiver editor surfaces them
/// so authors know which tokens are available.
library;

const String kWaiverParamMemberName = 'member_name';
const String kWaiverParamSignerName = 'signer_name';
const String kWaiverParamGymName = 'gym_name';
const String kWaiverParamDate = 'date';
const String kWaiverParamPayeeName = 'payee_name';

/// Token name → human-readable description.
const Map<String, String> kWaiverParameters = {
  kWaiverParamMemberName: "The account holder's full name",
  kWaiverParamSignerName: 'The name typed by the person signing',
  kWaiverParamGymName: "The gym's name",
  kWaiverParamDate: 'The date signed (YYYY-MM-DD)',
  kWaiverParamPayeeName:
      'The member being paid for (authorized-payer waiver only)',
};
