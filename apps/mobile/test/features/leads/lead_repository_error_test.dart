// Story 2.4 / 2.7 — Lead repository error-path contracts.
// Mirrors the _throwFromEdgeError logic from LeadRepository.
// Tests the key bug fix: FunctionException on 4xx → DuplicateLeadError or Exception.
// Run with: flutter test test/features/leads/lead_repository_error_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:nirman_crm/features/leads/data/lead_repository.dart';

// Mirror of LeadRepository._throwFromEdgeError for unit testing.
// Keep in sync with the production method.
Never _throwFromEdgeError(dynamic details, String fallback) {
  final body = details is Map ? Map<String, dynamic>.from(details as Map) : null;
  final err  = body?['error'] as Map<String, dynamic>?;
  final code = err?['code'] as String? ?? 'internal_error';
  final msg  = err?['message'] as String? ?? fallback;
  if (code == 'duplicate_lead') {
    final d = err?['details'] as Map<String, dynamic>?;
    throw DuplicateLeadError(
      message: msg,
      existingLeadId: d?['existing_lead_id'] as String? ?? '',
      ownerName: d?['owner'] as String? ?? 'another employee',
    );
  }
  throw Exception(msg);
}

void main() {
  group('_throwFromEdgeError — duplicate_lead code', () {
    test('throws DuplicateLeadError with message and owner', () {
      final details = {
        'error': {
          'code': 'duplicate_lead',
          'message': 'Phone already linked to Meena',
          'details': {
            'existing_lead_id': 'lead-uuid-1',
            'owner': 'Meena',
          },
        },
      };
      expect(
        () => _throwFromEdgeError(details, 'fallback'),
        throwsA(isA<DuplicateLeadError>()
            .having((e) => e.message, 'message', contains('Meena'))
            .having((e) => e.existingLeadId, 'existingLeadId', 'lead-uuid-1')
            .having((e) => e.ownerName, 'ownerName', 'Meena')),
      );
    });

    test('uses fallback owner name when details is null', () {
      final details = {
        'error': {
          'code': 'duplicate_lead',
          'message': 'Duplicate',
          'details': null,
        },
      };
      expect(
        () => _throwFromEdgeError(details, 'fallback'),
        throwsA(isA<DuplicateLeadError>()
            .having((e) => e.ownerName, 'ownerName', 'another employee')
            .having((e) => e.existingLeadId, 'existingLeadId', '')),
      );
    });
  });

  group('_throwFromEdgeError — non-duplicate codes', () {
    test('validation_error throws plain Exception with message', () {
      final details = {
        'error': {
          'code': 'validation_error',
          'message': 'Phone is required',
        },
      };
      expect(
        () => _throwFromEdgeError(details, 'fallback'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('Phone is required'),
        )),
      );
    });

    test('internal_error throws Exception with message', () {
      final details = {
        'error': {'code': 'internal_error', 'message': 'Server error'},
      };
      expect(
        () => _throwFromEdgeError(details, 'fallback'),
        throwsA(isA<Exception>()),
      );
    });

    test('not_found throws Exception with message', () {
      final details = {
        'error': {'code': 'not_found', 'message': 'Lead not found in your queue'},
      };
      expect(
        () => _throwFromEdgeError(details, 'fallback'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'msg', contains('Lead not found'),
        )),
      );
    });
  });

  group('_throwFromEdgeError — malformed / unexpected details', () {
    test('null details throws Exception with fallback message', () {
      expect(
        () => _throwFromEdgeError(null, 'Failed to create lead'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'msg', contains('Failed to create lead'),
        )),
      );
    });

    test('empty map throws Exception with fallback message', () {
      expect(
        () => _throwFromEdgeError({}, 'Failed to update lead'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'msg', contains('Failed to update lead'),
        )),
      );
    });

    test('non-map details (e.g. String) throws Exception with fallback', () {
      expect(
        () => _throwFromEdgeError('raw error string', 'fallback msg'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'msg', contains('fallback msg'),
        )),
      );
    });

    test('error block without code defaults to internal_error (throws Exception)', () {
      final details = {
        'error': {'message': 'Something went wrong'},
      };
      expect(
        () => _throwFromEdgeError(details, 'fallback'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'msg', contains('Something went wrong'),
        )),
      );
    });
  });

  group('DuplicateLeadError.toString', () {
    test('returns message field', () {
      const err = DuplicateLeadError(
        message: 'Duplicate phone',
        existingLeadId: 'abc',
        ownerName: 'Ravi',
      );
      expect(err.toString(), 'Duplicate phone');
    });
  });
}
