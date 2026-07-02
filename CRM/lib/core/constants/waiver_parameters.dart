/// Catalog of ``{{placeholder}}`` tokens a waiver body may use.
///
/// Mirrors `Database/python_data/schema/waiver_parameters.py`.
/// The backend fills these at sign time; the CRM waiver editor surfaces them
/// so authors know which tokens are available.
library;

/// Token name → human-readable description.
const Map<String, String> kWaiverParameters = {
  'member_name': "The account holder's full name",
  'signer_name': 'The name typed by the person signing',
  'gym_name': "The gym's name",
  'date': 'The date signed (YYYY-MM-DD)',
  'payee_name':
      'The member being paid for (authorized-payer waiver only)',
};
