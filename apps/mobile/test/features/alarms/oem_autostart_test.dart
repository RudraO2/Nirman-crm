// Story 10.4 — pure OEM auto-start + onboarding-step ordering tests. No plugin.

import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/alarms/data/oem_autostart.dart';

void main() {
  group('autoStartBrandLabel', () {
    test('maps known aggressive OEMs to a brand label', () {
      expect(autoStartBrandLabel('Xiaomi'), 'Xiaomi (MIUI)');
      expect(autoStartBrandLabel('Redmi'), 'Redmi (MIUI)');
      expect(autoStartBrandLabel('OPPO'), 'Oppo (ColorOS)');
      expect(autoStartBrandLabel('realme'), 'Realme (realme UI)');
      expect(autoStartBrandLabel('vivo'), 'Vivo (Funtouch OS)');
      expect(autoStartBrandLabel('HUAWEI'), 'Huawei (EMUI)');
      expect(autoStartBrandLabel('samsung'), 'Samsung');
    });

    test('is case-insensitive and trims whitespace', () {
      expect(autoStartBrandLabel('  XIAOMI  '), 'Xiaomi (MIUI)');
      expect(autoStartBrandLabel('OnePlus'), 'OnePlus');
    });

    test('matches on substring (vendor-decorated manufacturer strings)', () {
      expect(autoStartBrandLabel('Xiaomi Communications Co Ltd'),
          'Xiaomi (MIUI)');
    });

    test('returns null for stock/non-aggressive OEMs and empty input', () {
      expect(autoStartBrandLabel('Google'), isNull);
      expect(autoStartBrandLabel('motorola'), isNull);
      expect(autoStartBrandLabel('Nokia'), isNull);
      expect(autoStartBrandLabel(''), isNull);
      expect(autoStartBrandLabel('   '), isNull);
    });
  });

  group('isKnownAutoStartOem', () {
    test('true only for OEMs with an autostart manager', () {
      expect(isKnownAutoStartOem('Xiaomi'), isTrue);
      expect(isKnownAutoStartOem('Google'), isFalse);
    });
  });

  group('plannedOnboardingSteps', () {
    test('all granted + no autostart → empty', () {
      expect(
        plannedOnboardingSteps(
          notificationGranted: true,
          exactAlarmGranted: true,
          overlayGranted: true,
          batteryOptimizationIgnored: true,
          autoStartRelevant: false,
        ),
        isEmpty,
      );
    });

    test('nothing granted → strict order notif→exact→overlay→battery→autostart',
        () {
      expect(
        plannedOnboardingSteps(
          notificationGranted: false,
          exactAlarmGranted: false,
          overlayGranted: false,
          batteryOptimizationIgnored: false,
          autoStartRelevant: true,
        ),
        [
          AlarmOnboardingStep.notification,
          AlarmOnboardingStep.exactAlarm,
          AlarmOnboardingStep.overlay,
          AlarmOnboardingStep.batteryOptimization,
          AlarmOnboardingStep.autoStart,
        ],
      );
    });

    test('battery-opt is included whenever not exempt (AC8, not gated by overlay)',
        () {
      final steps = plannedOnboardingSteps(
        notificationGranted: true,
        exactAlarmGranted: true,
        overlayGranted: true, // overlay already granted
        batteryOptimizationIgnored: false, // but battery not exempt
        autoStartRelevant: false,
      );
      expect(steps, [AlarmOnboardingStep.batteryOptimization]);
    });

    test('auto-start only when relevant, and always last', () {
      final withAuto = plannedOnboardingSteps(
        notificationGranted: false,
        exactAlarmGranted: true,
        overlayGranted: true,
        batteryOptimizationIgnored: true,
        autoStartRelevant: true,
      );
      expect(withAuto, [
        AlarmOnboardingStep.notification,
        AlarmOnboardingStep.autoStart,
      ]);
      expect(withAuto.last, AlarmOnboardingStep.autoStart);

      final withoutAuto = plannedOnboardingSteps(
        notificationGranted: false,
        exactAlarmGranted: true,
        overlayGranted: true,
        batteryOptimizationIgnored: true,
        autoStartRelevant: false,
      );
      expect(withoutAuto, [AlarmOnboardingStep.notification]);
    });
  });
}
