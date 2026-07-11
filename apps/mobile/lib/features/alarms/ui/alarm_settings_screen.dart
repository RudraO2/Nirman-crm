// Story 10.1 — Settings → Follow-up Alarms screen.
//
// Master enable toggle (default off), multi-select lead-time offsets (1/5/10/30
// + custom), plain-language permission explainer with a Grant button, and a
// non-blocking warning banner when the OS denies a required permission (AC5).
// Pure Material + AppColors to match existing screens — no freestyle styling.

import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../data/alarm_permissions.dart';
import '../data/alarm_settings_repository.dart';
import '../data/models/alarm_settings.dart';
import '../data/oem_autostart.dart';
import '../providers/alarm_settings_controller.dart';

class AlarmSettingsScreen extends ConsumerStatefulWidget {
  const AlarmSettingsScreen({super.key});

  @override
  ConsumerState<AlarmSettingsScreen> createState() =>
      _AlarmSettingsScreenState();
}

class _AlarmSettingsScreenState extends ConsumerState<AlarmSettingsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the system permission / full-screen-intent settings page —
    // re-read the OS grant state so the banner reflects what the user just did.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(alarmPermissionStatusProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(alarmSettingsControllerProvider);
    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceBase,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.inkPrimary),
        title: Text(
          'Follow-up alarms',
          style: GoogleFonts.fraunces(
            fontSize: 21, fontWeight: FontWeight.w500, color: AppColors.inkPrimary,
          ),
        ),
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load alarm settings.\n$e',
                textAlign: TextAlign.center),
          ),
        ),
        data: (settings) => _Body(settings: settings),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final AlarmSettings settings;
  const _Body({required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(alarmSettingsControllerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Master toggle ──────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderHairline),
          ),
          child: SwitchListTile(
            value: settings.enabled,
            onChanged: (v) => _enableAndOnboard(ref, controller, v),
            activeThumbColor: AppColors.accent,
            title: const Text('Enable alarms',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: AppColors.inkPrimary)),
            subtitle: const Text(
              'Ring a full-screen alarm before each follow-up.',
              style: TextStyle(fontSize: 12, color: AppColors.inkSecondary),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Offsets (only meaningful when enabled) ─────────────────────
        Opacity(
          opacity: settings.enabled ? 1 : 0.5,
          child: IgnorePointer(
            ignoring: !settings.enabled,
            child: _OffsetsSection(settings: settings, controller: controller),
          ),
        ),
        const SizedBox(height: 20),

        // ── Permission status + explainer ──────────────────────────────
        const _PermissionSection(),
      ],
    );
  }
}

class _OffsetsSection extends StatelessWidget {
  final AlarmSettings settings;
  final AlarmSettingsController controller;
  const _OffsetsSection({required this.settings, required this.controller});

  @override
  Widget build(BuildContext context) {
    final selected = settings.offsetsMinutes.toSet();
    final customOffsets =
        settings.offsetsMinutes.where((m) => !kAlarmPresetOffsets.contains(m));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('RING BEFORE EACH FOLLOW-UP'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in kAlarmPresetOffsets)
              _offsetChip(m, selected.contains(m)),
            for (final m in customOffsets) _offsetChip(m, true),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Add custom'),
              backgroundColor: AppColors.surfaceSunk,
              side: const BorderSide(color: AppColors.borderHairline),
              onPressed: () => _addCustom(context),
            ),
          ],
        ),
        if (settings.offsetsMinutes.isEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            'Pick at least one offset to receive alarms.',
            style: TextStyle(fontSize: 12, color: AppColors.inkSecondary),
          ),
        ],
      ],
    );
  }

  Widget _offsetChip(int minutes, bool isSelected) {
    return FilterChip(
      label: Text(_label(minutes)),
      selected: isSelected,
      onSelected: (on) => controller.setOffset(minutes, on),
      selectedColor: AppColors.accentSoft,
      backgroundColor: AppColors.surfaceSunk,
      checkmarkColor: AppColors.inkPrimary,
      side: const BorderSide(color: AppColors.borderHairline),
    );
  }

  static String _label(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  Future<void> _addCustom(BuildContext context) async {
    final minutes = await showDialog<int>(
      context: context,
      builder: (_) => const _CustomOffsetDialog(),
    );
    if (minutes != null) controller.addCustomOffset(minutes);
  }
}

class _CustomOffsetDialog extends StatefulWidget {
  const _CustomOffsetDialog();

  @override
  State<_CustomOffsetDialog> createState() => _CustomOffsetDialogState();
}

class _CustomOffsetDialogState extends State<_CustomOffsetDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value <= 0) {
      setState(() => _error = 'Enter a number of minutes (1 or more).');
      return;
    }
    if (value > kMaxAlarmOffsetMinutes) {
      setState(() => _error = 'Maximum is $kMaxAlarmOffsetMinutes minutes (24h).');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom offset'),
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Minutes before follow-up',
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

class _PermissionSection extends ConsumerWidget {
  const _PermissionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(alarmPermissionStatusProvider);
    final explainer = Platform.isIOS
        ? 'On iPhone, a clock-style alarm is not possible. Follow-up reminders '
            'arrive as time-sensitive notifications with sound instead.'
        : 'Android needs permission to schedule exact alarms and show a '
            'full-screen reminder over the lock screen. Grant these so alarms '
            'ring on time, with sound, even when the app is closed.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('PERMISSIONS'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderHairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                explainer,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.inkSecondary, height: 1.35),
              ),
              const SizedBox(height: 12),
              statusAsync.when(
                loading: () => const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (status) => _WarningAndButton(status: status),
              ),
            ],
          ),
        ),
        // Story 10.4 — OEM auto-start guidance (self-hides on non-aggressive OEMs
        // and iOS). Auto-start state is not queryable, so this is guidance only.
        const SizedBox(height: 12),
        const _AutoStartCard(),
      ],
    );
  }
}

/// Story 10.4 — "Allow auto-start" guided step. Shown only on OEMs known to gate
/// background alarms behind an Autostart/Auto-launch toggle (Xiaomi/Oppo/Vivo/
/// etc.). Tapping deep-links to the OEM page (native falls back to app settings)
/// and records the visit locally so a future proactive nudge doesn't repeat.
class _AutoStartCard extends ConsumerStatefulWidget {
  const _AutoStartCard();

  @override
  ConsumerState<_AutoStartCard> createState() => _AutoStartCardState();
}

class _AutoStartCardState extends ConsumerState<_AutoStartCard> {
  AutoStartInfo? _info;
  bool _visited = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await ref.read(alarmPermissionsProvider).autoStartInfo();
    final visited =
        await ref.read(alarmSettingsRepositoryProvider).loadAutoStartVisited();
    if (!mounted) return;
    setState(() {
      _info = info;
      _visited = visited;
      _loaded = true;
    });
  }

  bool get _relevant {
    final info = _info;
    if (info == null) return false;
    // Some skins report the aggressive brand in BRAND, not MANUFACTURER.
    return isKnownAutoStartOem(info.manufacturer) ||
        isKnownAutoStartOem(info.brand) ||
        info.componentResolved;
  }

  Future<void> _open() async {
    // Read providers BEFORE the await so a disposal during openAutoStartSettings()
    // never leaves us using `ref` after the element is gone.
    final perms = ref.read(alarmPermissionsProvider);
    final repo = ref.read(alarmSettingsRepositoryProvider);
    await perms.openAutoStartSettings();
    await repo.saveAutoStartVisited(true);
    if (!mounted) return;
    setState(() => _visited = true);
    ref.invalidate(alarmPermissionStatusProvider);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || !_relevant) return const SizedBox.shrink();
    final brand = autoStartBrandLabel(_info!.manufacturer) ??
        autoStartBrandLabel(_info!.brand) ??
        'your phone';
    // AC3 — after the first visit the prominent nudge downgrades to a quiet
    // "re-open" affordance so it doesn't keep pushing the user every time.
    final button = _visited
        ? OutlinedButton.icon(
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Re-open auto-start settings'),
            onPressed: _open,
          )
        : ElevatedButton.icon(
            icon: const Icon(Icons.rocket_launch_outlined, size: 18),
            label: const Text('Allow auto-start'),
            onPressed: _open,
          );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // Vendor-neutral copy: the lever is "Auto-start"/"Auto-launch" on
            // Xiaomi/Oppo/Vivo/Huawei but "battery"/"app power" on Samsung/OnePlus,
            // so we point the user at both rather than naming one that may not exist.
            '$brand can stop alarms in the background. Let Nirman CRM keep running '
            '— look for "Auto-start", "Auto-launch", or the battery / app-power '
            'settings on the page that opens — so follow-up alarms still ring after '
            'you close the app or restart the phone.',
            style: const TextStyle(
                fontSize: 13, color: AppColors.inkSecondary, height: 1.35),
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: button),
        ],
      ),
    );
  }
}

/// Story 10.4 — turn alarms on/off, and on enable run the guided permission
/// sequence (AC7) so the user isn't left to hunt through system settings.
Future<void> _enableAndOnboard(
    WidgetRef ref, AlarmSettingsController controller, bool enabled) async {
  try {
    await controller.setEnabled(enabled);
    if (!enabled) return;
    await _runGuidedOnboarding(ref);
  } catch (e) {
    // Onboarding is best-effort and non-blocking: a permission-plugin error
    // (e.g. permission_handler's "a request is already running" if a card button
    // is tapped mid-flow), a disposed `ref` if the user leaves the screen during
    // a system dialog, or a reconcile failure must NOT crash the toggle or leak an
    // unhandled async error. The banner/card re-sync on the next lifecycle-resume.
    developer.log("{'event':'alarm_error','op':'onboarding','error':'$e'}",
        name: 'alarms');
  }
}

/// Non-blocking, ordered permission walkthrough driven by the pure
/// [plannedOnboardingSteps] planner: notification → exact-alarm → overlay →
/// battery-opt → auto-start. Runtime dialogs fire automatically; the auto-start
/// step is surfaced by the persistent [_AutoStartCard] rather than force-opening
/// an OEM page the user didn't ask for (it is also unverifiable afterwards).
Future<void> _runGuidedOnboarding(WidgetRef ref) async {
  final perms = ref.read(alarmPermissionsProvider);
  final status = await perms.status();
  final info = await perms.autoStartInfo();
  final autoStartRelevant = info != null &&
      (isKnownAutoStartOem(info.manufacturer) ||
          isKnownAutoStartOem(info.brand) ||
          info.componentResolved);

  final steps = plannedOnboardingSteps(
    notificationGranted: status.notificationGranted,
    exactAlarmGranted: status.exactAlarmGranted,
    overlayGranted: status.systemAlertWindowGranted,
    batteryOptimizationIgnored: status.batteryOptimizationIgnored,
    autoStartRelevant: autoStartRelevant,
  );

  // Runtime permission dialogs (notification + exact alarm are requested together).
  if (steps.contains(AlarmOnboardingStep.notification) ||
      steps.contains(AlarmOnboardingStep.exactAlarm)) {
    await perms.request();
  }
  // AC7 order — overlay (the background-display lever) BEFORE battery-opt.
  if (steps.contains(AlarmOnboardingStep.overlay)) {
    await perms.requestOverlay();
  }
  if (steps.contains(AlarmOnboardingStep.batteryOptimization)) {
    await perms.requestIgnoreBatteryOptimizations();
  }
  // AlarmOnboardingStep.autoStart → handled by the persistent _AutoStartCard.
  ref.invalidate(alarmPermissionStatusProvider);
}

class _WarningAndButton extends ConsumerWidget {
  final AlarmPermissionStatus status;
  const _WarningAndButton({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (status.hasBlocker) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.accentStrong),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 18, color: AppColors.accentStrong),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _warningText(status),
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.accentStrong),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        // Background full-screen display is the reason a backgrounded alarm only
        // plays sound. When notif + exact are already granted, surface the
        // "Display over other apps" action — the reliable cross-OEM lever.
        if (status.notificationGranted &&
            status.exactAlarmGranted &&
            !status.backgroundDisplayGranted) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.open_in_full, size: 18),
              label: const Text('Allow full-screen alarms'),
              onPressed: () => _onBackgroundDisplay(ref),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Opens "Display over other apps" — turn it on for Nirman CRM. On some '
            'phones also disable battery optimization for reliable alarms.',
            style: TextStyle(fontSize: 11.5, color: AppColors.inkSecondary),
          ),
        ] else
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.lock_open, size: 18),
              label: Text(status.needsSystemSettings
                  ? 'Open system settings'
                  : 'Grant permissions'),
              onPressed: () => _onGrant(ref),
            ),
          ),
      ],
    );
  }

  static String _warningText(AlarmPermissionStatus status) {
    if (!status.notificationGranted || !status.exactAlarmGranted) {
      return 'Alarms may be delayed or silent until you allow this in system '
          'settings.';
    }
    // Only background full-screen display missing.
    return 'Alarms will ring with sound, but won\'t take over the screen while '
        'the app is in the background until you allow full-screen alarms.';
  }

  Future<void> _onGrant(WidgetRef ref) async {
    final perms = ref.read(alarmPermissionsProvider);
    try {
      if (status.needsSystemSettings) {
        await perms.openSystemSettings();
      } else {
        final after = await perms.request();
        // Story 10.4 (AC8) — always request the battery-optimization exemption when
        // not already granted, decoupled from the overlay branch below (previously
        // it only fired when overlay was the remaining blocker, so overlay-granted
        // devices stayed Doze/OEM-killable).
        if (!after.batteryOptimizationIgnored) {
          await perms.requestIgnoreBatteryOptimizations();
        }
        // Runtime grants don't cover background full-screen display — route to the
        // overlay page (reliable lever) if it's the remaining blocker.
        if (after.notificationGranted &&
            after.exactAlarmGranted &&
            !after.backgroundDisplayGranted) {
          await perms.requestOverlay();
        }
      }
    } catch (e) {
      // Guard against permission_handler's "a request is already running" if this
      // button is tapped while the enable-onboarding flow is mid-request.
      developer.log("{'event':'alarm_error','op':'grant','error':'$e'}",
          name: 'alarms');
    }
    ref.invalidate(alarmPermissionStatusProvider);
  }

  Future<void> _onBackgroundDisplay(WidgetRef ref) async {
    final perms = ref.read(alarmPermissionsProvider);
    // Overlay is the reliable cross-OEM lever; also nudge battery-opt + try the
    // stock full-screen-intent page as best-effort.
    try {
      await perms.requestOverlay();
      await perms.requestIgnoreBatteryOptimizations();
    } catch (e) {
      developer.log("{'event':'alarm_error','op':'bg_display','error':'$e'}",
          name: 'alarms');
    }
    ref.invalidate(alarmPermissionStatusProvider);
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.88,
        color: AppColors.inkSecondary,
      ),
    );
  }
}
