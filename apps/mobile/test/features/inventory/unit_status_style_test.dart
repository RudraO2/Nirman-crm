// Story 14.3-mobile — status→colour map is distinct across states; price/area format.
import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/inventory/data/models/unit_model.dart';
import 'package:nirman_crm/features/inventory/ui/unit_status_style.dart';

void main() {
  test('each real status has a distinct foreground+background pair', () {
    const statuses = [
      UnitStatus.available,
      UnitStatus.hold,
      UnitStatus.sold,
      UnitStatus.blocked,
    ];
    final fgs = statuses.map((s) => s.foreground.toARGB32()).toSet();
    final bgs = statuses.map((s) => s.background.toARGB32()).toSet();
    expect(fgs.length, 4, reason: 'foregrounds must be visually distinct');
    expect(bgs.length, 4, reason: 'backgrounds must be visually distinct');
  });

  test('labels are human-readable', () {
    expect(UnitStatus.available.label, 'Available');
    expect(UnitStatus.hold.label, 'On hold');
    expect(UnitStatus.sold.label, 'Sold');
    expect(UnitStatus.blocked.label, 'Blocked');
  });

  test('formatPaise handles null, rupees, lakh, crore', () {
    expect(formatPaise(null), '—');
    expect(formatPaise(5000000), '₹50000'); // 50k rupees
    expect(formatPaise(750000000), '₹75.00 L'); // 75 lakh
    expect(formatPaise(12000000000), '₹12.00 Cr'); // 12 crore = 1.2e9 rupees = 1.2e11 paise... 12 crore rupees = 12e7 rupees = 12e9 paise
  });

  test('formatArea handles null and trims trailing .0', () {
    expect(formatArea(null), '—');
    expect(formatArea(845), '845 sq.ft');
    expect(formatArea(845.5), '845.5 sq.ft');
  });
}
