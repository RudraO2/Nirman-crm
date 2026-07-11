// Story 10.4 — Pure OEM auto-start logic + onboarding-step ordering.
//
// No plugin imports so it is fully unit-testable. The actual per-OEM `Intent`
// firing lives natively in MainActivity.kt (behind the `nirman/alarm_permissions`
// MethodChannel); this file owns the two pure decisions the Dart/UI side makes:
//   1. Given a device manufacturer, is this an OEM known to gate background
//      alarms behind an "Autostart"/"Auto-launch" toggle, and what brand label
//      do we show the user?  (Auto-start state itself is NOT queryable on
//      Android — we can only guide, not verify.)
//   2. Given the current permission state, what is the ordered list of
//      onboarding steps still needing the user's attention?

/// The guided permission steps, in the order Story 10.4 (AC7) walks the user
/// through them on alarm-enable. `autoStart` is last because it is the most
/// disruptive (an OEM settings page) and cannot be verified afterwards.
enum AlarmOnboardingStep {
  notification,
  exactAlarm,
  overlay,
  batteryOptimization,
  autoStart,
}

/// Human-facing brand label for an OEM known to have an Autostart/Auto-launch
/// manager that can silently stop scheduled alarms. Returns null for
/// manufacturers with no such manager (stock Android, Pixel, Motorola, Nokia,
/// etc.), where the auto-start step should not be shown.
///
/// Matched case-insensitively against `Build.MANUFACTURER` (and callers may also
/// pass `Build.BRAND`). Keep this list in sync with the native component table
/// in MainActivity.kt — the native side does the launching, this decides whether
/// to surface the step at all (so it still shows even when Android package
/// visibility hides the component from `resolveActivity`).
String? autoStartBrandLabel(String manufacturer) {
  final m = manufacturer.trim().toLowerCase();
  if (m.isEmpty) return null;
  const table = <String, String>{
    'xiaomi': 'Xiaomi (MIUI)',
    'redmi': 'Redmi (MIUI)',
    'poco': 'Poco (MIUI)',
    'oppo': 'Oppo (ColorOS)',
    'realme': 'Realme (realme UI)',
    'oneplus': 'OnePlus',
    'vivo': 'Vivo (Funtouch OS)',
    'iqoo': 'iQOO',
    'huawei': 'Huawei (EMUI)',
    'honor': 'Honor',
    'samsung': 'Samsung',
    'asus': 'Asus',
    'letv': 'Letv',
    'leeco': 'LeEco',
    'meizu': 'Meizu',
    'gionee': 'Gionee',
    'tecno': 'Tecno',
    'infinix': 'Infinix',
  };
  // Exact match first, then substring (e.g. "Xiaomi Communications").
  final exact = table[m];
  if (exact != null) return exact;
  for (final entry in table.entries) {
    if (m.contains(entry.key)) return entry.value;
  }
  return null;
}

/// True when [manufacturer] is a known aggressive OEM (has an Autostart manager).
bool isKnownAutoStartOem(String manufacturer) =>
    autoStartBrandLabel(manufacturer) != null;

/// The ordered onboarding steps still needing attention, given the current
/// grant state. Pure so it is unit-testable without any platform plugin.
///
/// - [autoStartRelevant] is true only on a known aggressive OEM (and, ideally,
///   not already visited — the caller decides whether to suppress a repeat).
/// - Battery optimization is always included when not yet exempt (AC8: it is no
///   longer gated behind the overlay branch).
List<AlarmOnboardingStep> plannedOnboardingSteps({
  required bool notificationGranted,
  required bool exactAlarmGranted,
  required bool overlayGranted,
  required bool batteryOptimizationIgnored,
  required bool autoStartRelevant,
}) {
  return [
    if (!notificationGranted) AlarmOnboardingStep.notification,
    if (!exactAlarmGranted) AlarmOnboardingStep.exactAlarm,
    if (!overlayGranted) AlarmOnboardingStep.overlay,
    if (!batteryOptimizationIgnored) AlarmOnboardingStep.batteryOptimization,
    if (autoStartRelevant) AlarmOnboardingStep.autoStart,
  ];
}
