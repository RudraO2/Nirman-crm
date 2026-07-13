/**
 * Story 9.6 — how a locked-out builder reaches the operator to recharge.
 *
 * Collection is OUT-OF-BAND (UPI / cash / bank); there is no in-app payment yet
 * (Razorpay is a later story). Kept in one place (not inlined). `phoneE164` is
 * digits only, no '+', for wa.me links. This number is shown to tenant ADMINS
 * only (the admin web app + the mobile admin paused screen) — employees are
 * told to contact their admin instead.
 */
export const OPERATOR_CONTACT = {
  phoneE164: '919166921692',
  phoneDisplay: '+91 91669 21692',
  whatsappMessage:
    'Hello, my Nirman CRM subscription has ended. I would like to recharge.',
} as const
