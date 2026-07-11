// Story 10.1 — Persists AlarmSettings device-locally.
//
// Uses SharedPreferencesAsync (NOT the legacy cached SharedPreferences): the
// 10.2/10.3 alarm-fire + BOOT_COMPLETED handlers run in a background isolate,
// where a separate-isolate in-memory cache would be stale. Async-always reads
// hit platform storage, so every isolate sees the latest saved value.

import 'dart:developer' as developer;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/alarm_settings.dart';

part 'alarm_settings_repository.g.dart';

const _kEnabledKey = 'alarms.enabled';
const _kOffsetsKey = 'alarms.offsets_minutes';
// Story 10.4 — whether the user has visited the OEM auto-start page at least once
// (auto-start state itself is not queryable, so we track the nudge locally).
const _kAutoStartVisitedKey = 'alarms.autostart_visited';

class AlarmSettingsRepository {
  AlarmSettingsRepository(this._prefs);

  final SharedPreferencesAsync _prefs;

  Future<AlarmSettings> load() async {
    final enabled = await _prefs.getBool(_kEnabledKey) ?? false;
    final offsets = await _prefs.getStringList(_kOffsetsKey);
    return AlarmSettings(
      enabled: enabled,
      offsetsMinutes: AlarmSettings.offsetsFromStrings(offsets),
    );
  }

  Future<void> save(AlarmSettings settings) async {
    await _prefs.setBool(_kEnabledKey, settings.enabled);
    await _prefs.setStringList(_kOffsetsKey, settings.offsetsAsStrings);
    developer.log(
      "{'event':'alarm_settings_saved','enabled':${settings.enabled},"
      "'offsets':${settings.offsetsMinutes}}",
      name: 'alarms',
    );
  }

  /// Story 10.4 — has the user opened the OEM auto-start page at least once?
  Future<bool> loadAutoStartVisited() async =>
      await _prefs.getBool(_kAutoStartVisitedKey) ?? false;

  Future<void> saveAutoStartVisited(bool visited) async =>
      _prefs.setBool(_kAutoStartVisitedKey, visited);
}

@riverpod
AlarmSettingsRepository alarmSettingsRepository(AlarmSettingsRepositoryRef ref) {
  return AlarmSettingsRepository(SharedPreferencesAsync());
}
