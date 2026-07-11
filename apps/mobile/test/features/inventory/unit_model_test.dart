// Story 14.3-mobile — ProjectUnit.fromJson + UnitStatus.fromDb.
import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/inventory/data/models/unit_model.dart';

void main() {
  Map<String, dynamic> row({
    String status = 'available',
    Object? costPaise = 4000000000,
    Object? floor = 3,
  }) => {
        'unit_id': 'a1b2c3d4-0000-0000-0000-000000000001',
        'tower_id': 'a1b2c3d4-0000-0000-0000-0000000000aa',
        'tower_name': 'Tower A',
        'unit_no': 'A-301',
        'floor': floor,
        'configuration': '2BHK',
        'carpet_area_sqft': 845.5,
        'status': status,
        'list_price_paise': 7500000000,
        'cost_paise': costPaise,
        'status_version': 2,
      };

  test('maps every column for a head row (margin present)', () {
    final u = ProjectUnit.fromJson(row());
    expect(u.unitId, 'a1b2c3d4-0000-0000-0000-000000000001');
    expect(u.towerName, 'Tower A');
    expect(u.unitNo, 'A-301');
    expect(u.floor, 3);
    expect(u.configuration, '2BHK');
    expect(u.carpetAreaSqft, 845.5);
    expect(u.status, UnitStatus.available);
    expect(u.listPricePaise, 7500000000);
    expect(u.costPaise, 4000000000);
    expect(u.hasMargin, isTrue);
    expect(u.statusVersion, 2);
  });

  test('null cost_paise (non-head) → hasMargin false, not zero', () {
    final u = ProjectUnit.fromJson(row(costPaise: null));
    expect(u.costPaise, isNull);
    expect(u.hasMargin, isFalse);
  });

  test('null floor is tolerated', () {
    final u = ProjectUnit.fromJson(row(floor: null));
    expect(u.floor, isNull);
  });

  test('UnitStatus.fromDb maps all four states + unknown fallback', () {
    expect(UnitStatus.fromDb('available'), UnitStatus.available);
    expect(UnitStatus.fromDb('hold'), UnitStatus.hold);
    expect(UnitStatus.fromDb('sold'), UnitStatus.sold);
    expect(UnitStatus.fromDb('blocked'), UnitStatus.blocked);
    expect(UnitStatus.fromDb('something_new'), UnitStatus.unknown);
    expect(UnitStatus.fromDb(null), UnitStatus.unknown);
  });
}
