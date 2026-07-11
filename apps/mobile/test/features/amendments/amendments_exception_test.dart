// Story 16.2-mobile — exception mapping to calm messages (no raw dumps).

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nirman_crm/features/amendments/data/amendments_repository.dart';

void main() {
  group('LogAmendmentException.fromPostgrest', () {
    LogAmendmentException map(String m) =>
        LogAmendmentException.fromPostgrest(PostgrestException(message: m));

    test('partner forbidden', () {
      final e = map('forbidden_role: partner_agency cannot log amendments');
      expect(e.forbidden, isTrue);
      expect(e.friendly, contains("can't log"));
    });
    test('unit_not_amendable', () {
      expect(map('unit_not_amendable: ...').notAmendable, isTrue);
    });
    test('lead_not_linked_to_unit (0084)', () {
      final e = map('lead_not_linked_to_unit: this lead does not hold or own that unit');
      expect(e.notLinked, isTrue);
      expect(e.friendly, contains("doesn't hold or own"));
    });
    test('lead_not_visible', () {
      expect(map('lead_not_visible').notVisible, isTrue);
    });
    test('description_required', () {
      final e = map('description_required');
      expect(e.descriptionRequired, isTrue);
      expect(e.friendly, contains('description'));
    });
    test('unknown → generic', () {
      final e = map('boom');
      expect(e.friendly, "Couldn't log the amendment. Try again.");
    });
  });

  group('ExecutionException.fromPostgrest', () {
    ExecutionException map(String m) =>
        ExecutionException.fromPostgrest(PostgrestException(message: m));

    test('not_execution_member', () {
      final e = map('not_execution_member');
      expect(e.notMember, isTrue);
      expect(e.friendly, contains('execution team'));
    });
    test('invalid_transition', () {
      final e = map('invalid_transition: requested -> done');
      expect(e.invalidTransition, isTrue);
      expect(e.friendly, contains("isn't allowed"));
    });
    test('permission_denied → notHead', () {
      expect(map('permission_denied: builder_head only').notHead, isTrue);
    });
    test('unknown → generic', () {
      expect(map('boom').friendly, contains('Pull to refresh'));
    });
  });
}
