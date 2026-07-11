// Story 15.5-mobile — BookingAccessException mapping/friendly.

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nirman_crm/features/booking/data/booking_repository.dart';

void main() {
  BookingAccessException map(String msg) =>
      BookingAccessException.fromPostgrest(PostgrestException(message: msg));

  test('not_authenticated → notAuthenticated + friendly', () {
    final e = map('not_authenticated');
    expect(e.notAuthenticated, isTrue);
    expect(e.friendly, contains('sign in again'));
  });

  test('other errors → generic friendly, not a raw dump', () {
    final e = map('permission_denied');
    expect(e.notAuthenticated, isFalse);
    expect(e.friendly, contains('Pull to refresh'));
  });
}
