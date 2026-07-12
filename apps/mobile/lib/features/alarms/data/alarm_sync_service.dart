// Story 10.3 — Keeps device follow-up alarms in sync with the lead lifecycle.
//
// One idempotent operation, [reconcile]: cancel the previously-scheduled
// follow-up alarms and rebuild them from the user's CURRENT active leads. Every
// lifecycle event (create / reschedule / complete / cancel / archive / reassign)
// reduces to "the active-lead list changed -> reconcile", because archived and
// reassigned-away leads fall out of `get_my_leads` server-side and so get no
// alarm after a rebuild. This supersedes Story 10.2's deferred per-lead targeted
// cancel — a cancel-then-rebuild is simpler and self-healing.
//
// Reboot is NOT handled here: the `alarm` package persists alarms and re-arms
// them on Android boot via its own native receiver, and `Alarm.init()` restores
// them on cold start. This service only corrects drift from server-side changes,
// triggered on app open, on alarms-(re)enable, and whenever the active-lead list
// changes (a single `myLeadsProvider` listener in the home screen).

import 'dart:developer' as developer;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../leads/data/lead_repository.dart';
import '../../leads/data/models/lead_model.dart';
import 'alarm_scheduler.dart';
import 'alarm_settings_repository.dart';
import 'models/alarm_settings.dart';

part 'alarm_sync_service.g.dart';

class AlarmSyncService {
  AlarmSyncService({
    required this.scheduler,
    required this.loadSettings,
    required this.loadLeads,
  });

  final AlarmScheduler scheduler;
  final Future<AlarmSettings> Function() loadSettings;
  final Future<List<LeadListItem>> Function() loadLeads;

  /// Serializes overlapping reconciles. Triggers fire from several places (home
  /// lead-list listener, settings enable/offset, app-open); without this guard a
  /// later cancel-then-rebuild could interleave with an earlier one and stop an
  /// alarm it had just scheduled. Chaining runs them strictly in order; the
  /// provider is keepAlive so this state survives across `ref.read`s.
  Future<void>? _running;

  /// Cancel scheduled follow-up alarms and rebuild from the current active leads.
  /// Pass [leads] to reuse an already-loaded list (e.g. from the home provider);
  /// otherwise the current active leads are fetched.
  Future<void> reconcile({required String reason, List<LeadListItem>? leads}) {
    final prev = _running ?? Future<void>.value();
    final next = prev
        .then((_) => _reconcile(reason: reason, leads: leads))
        .catchError((Object e) =>
            _log({'event': 'alarm_error', 'op': 'reconcile', 'reason': reason, 'error': '$e'}));
    _running = next.whenComplete(() {
      if (identical(_running, next)) _running = null;
    });
    return _running!;
  }

  Future<void> _reconcile({required String reason, List<LeadListItem>? leads}) async {
    final settings = await loadSettings();

    if (!settings.enabled) {
      await scheduler.cancelAllAlarms(reason: 'reconcile_disabled:$reason');
      return;
    }

    final source = leads ?? await loadLeads();

    // Cancel previously-scheduled future alarms, preserving any that are
    // currently ringing or snoozed (handled inside cancelScheduledAlarms).
    await scheduler.cancelScheduledAlarms(reason: 'reconcile:$reason');

    var scheduled = 0;
    for (final lead in source) {
      final at = lead.nextFollowupAt;
      if (at == null) continue;
      scheduled += await scheduler.scheduleForFollowUp(
        leadId: lead.id,
        leadName: _displayName(lead.name),
        // next_followup_at is stored UTC; the alarm fires on local wall-clock.
        followUpAt: at.toLocal(),
        settings: settings,
        reason: reason,
      );
    }

    _log({
      'event': 'alarms_reconciled',
      'reason': reason,
      'leads': source.length,
      'scheduled': scheduled,
    });
  }

  // Masked to first name + last-name initial: the payload is persisted as
  // plaintext by the native alarm plugin (audit medium) — keep the stored PII
  // minimal while the ring screen stays human. Full name lives behind the
  // lead-detail tap (authenticated fetch).
  static String _displayName(String? name) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return 'your lead';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first;
    return '${parts.first} ${parts.last[0]}.';
  }
}

void _log(Map<String, Object?> fields) {
  final body = fields.entries
      .map((e) => "'${e.key}':${e.value is num ? e.value : "'${e.value}'"}")
      .join(',');
  developer.log('{$body}', name: 'alarms');
}

// keepAlive: the in-flight reconcile guard ([_running]) must persist across the
// `ref.read`s made from the home listener / settings controller / app-open.
@Riverpod(keepAlive: true)
AlarmSyncService alarmSyncService(AlarmSyncServiceRef ref) => AlarmSyncService(
      scheduler: ref.read(alarmSchedulerProvider),
      loadSettings: () => ref.read(alarmSettingsRepositoryProvider).load(),
      loadLeads: () => ref.read(leadRepositoryProvider).getMyLeads(),
    );
