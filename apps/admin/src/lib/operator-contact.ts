/**
 * Story 9.6 — how a locked-out builder reaches the operator to recharge.
 *
 * Collection is OUT-OF-BAND (UPI / cash / bank); there is no in-app payment yet
 * (Razorpay is a later story). PLACEHOLDER values — set to Nirman's real support
 * number before shipping. Kept in one place (not inlined) so it is obvious it
 * needs a real value. `phoneE164` is digits only, no '+', for wa.me links.
 */
export const OPERATOR_CONTACT = {
  phoneE164: '910000000000',
  phoneDisplay: '+91 00000 00000',
  whatsappMessage: 'नमस्ते, मुझे अपना Nirman CRM subscription recharge करना है।',
} as const
