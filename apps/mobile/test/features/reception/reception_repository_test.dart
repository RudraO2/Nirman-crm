// Story 13.4-mobile — code normalisation + VerifyVisitException mapping/friendly.

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nirman_crm/features/reception/data/reception_repository.dart';

void main() {
  group('normalizeCode', () {
    test('trims + uppercases so nir-44d77 resolves like NIR-44D77', () {
      expect(ReceptionRepository.normalizeCode('  nir-44d77 '), 'NIR-44D77');
      expect(ReceptionRepository.normalizeCode('NIR-6CD66'), 'NIR-6CD66');
    });
  });

  group('VerifyVisitException.fromPostgrest', () {
    VerifyVisitException map(String msg) => VerifyVisitException.fromPostgrest(
        PostgrestException(message: msg));

    test('invalid_customer_code → notFound + friendly', () {
      final e = map('invalid_customer_code');
      expect(e.notFound, isTrue);
      expect(e.friendly, contains('No lead matches'));
    });

    test('permission_denied → notAllowed + friendly', () {
      final e = map('permission_denied');
      expect(e.notAllowed, isTrue);
      expect(e.friendly, contains("don't have access"));
    });

    test('not_authenticated → notAllowed', () {
      expect(map('not_authenticated').notAllowed, isTrue);
    });

    test('unknown token → generic friendly, no raw dump', () {
      final e = map('some_pg_internal_42P01');
      expect(e.notFound, isFalse);
      expect(e.notAllowed, isFalse);
      expect(e.friendly, "Couldn't verify that code. Try again.");
    });
  });
}
