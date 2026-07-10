/// Story 9.6 — how a locked-out builder reaches the operator to recharge.
///
/// Collection is OUT-OF-BAND (UPI / cash / bank) — there is no in-app payment
/// yet (Razorpay is a later story). These values drive the "contact us to
/// recharge" affordances on the paused screen.
///
/// PLACEHOLDER — set to Nirman's real support number before shipping. Kept as a
/// single const (not hardcoded inline) so it is trivial to change and obvious it
/// needs a real value. Format: E.164 digits WITHOUT '+' for wa.me (e.g. 9198...).
class OperatorContact {
  /// Support phone in E.164 without '+' (India country code 91). PLACEHOLDER.
  static const phoneE164 = '910000000000';

  /// Human-readable form shown in the UI. PLACEHOLDER.
  static const phoneDisplay = '+91 00000 00000';

  /// Prefilled WhatsApp message (Hindi-first) when a builder taps "recharge".
  static const whatsappMessage =
      'नमस्ते, मुझे अपना Nirman CRM subscription recharge करना है।';
}
