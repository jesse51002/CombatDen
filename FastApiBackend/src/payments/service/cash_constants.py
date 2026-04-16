"""Shared constants for cash (out-of-band) invoice payments.

Stripe does not persist the request-only ``paid_out_of_band`` flag on
the Invoice object, so we stamp this metadata key on any invoice paid
via cash. The ``invoice.paid`` webhook reads the key back to tag the
CRM charge row with ``payment_method_type='cash'``.
"""

CRM_PAID_WITH_CASH_METADATA_KEY = "crm_paid_with_cash"
CRM_PAID_WITH_CASH_METADATA_VALUE = "true"
