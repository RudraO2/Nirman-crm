/// Story 9.6 — how a locked-out builder reaches the operator to recharge.
///
/// Collection is OUT-OF-BAND (UPI / cash / bank) — there is no in-app payment
/// yet (Razorpay is a later story). These values drive the "contact us to
/// recharge" affordances on the paused screen.
///
/// The real number is injected at build time (the build-apk.ps1 --dart-define
/// flow), e.g.:
///   --dart-define=OPERATOR_PHONE_E164=9198XXXXXXXX
///   --dart-define=OPERATOR_PHONE_DISPLAY="+91 98XXX XXXXX"
/// Until then [isPlaceholder] is true and the paused screen hides the dead
/// call/WhatsApp buttons instead of pointing builders at 00000 00000
/// (audit medium: placeholder number had no build-time check).
class OperatorContact {
  /// Support phone in E.164 without '+' (India country code 91) for wa.me.
  static const phoneE164 = String.fromEnvironment(
    'OPERATOR_PHONE_E164',
    defaultValue: '910000000000',
  );

  /// Human-readable form shown in the UI.
  static const phoneDisplay = String.fromEnvironment(
    'OPERATOR_PHONE_DISPLAY',
    defaultValue: '+91 00000 00000',
  );

  /// True while the build carries the placeholder number — UI must not render
  /// call/WhatsApp affordances that would dial a dead line.
  static const isPlaceholder = phoneE164 == '910000000000';

  /// Prefilled WhatsApp message (Hindi-first) when a builder taps "recharge".
  static const whatsappMessage =
      'नमस्ते, मुझे अपना Nirman CRM subscription recharge करना है।';
}
