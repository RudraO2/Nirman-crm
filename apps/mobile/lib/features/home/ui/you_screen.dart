// UI redesign §6.2 — "You" tab.
//
// Pure rearrangement of EXISTING widgets and existing navigation targets:
// profile header (from the current session), the existing PersonalStatsCard and
// MonthlyBestSection, then rows linking to the existing Archived / Alarms /
// Change-password screens and the existing signOut() call. No new data.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_repository.dart';
import '../../motivation/ui/personal_stats_card.dart';
import '../../motivation/ui/monthly_best.dart';

class YouScreen extends ConsumerWidget {
  const YouScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.read(authRepositoryProvider).currentSession;
    final email = session?.user.email ?? '';
    final role = session?.user.appMetadata['role'] as String?;
    // Best-effort only — role_tier may be ABSENT from the JWT (12.3 backfill not
    // run in prod). Used solely to decide whether to surface the Team-leads entry;
    // get_team_leads scopes correctly server-side regardless. [Story 12.6-mobile]
    final roleTier = session?.user.appMetadata['role_tier'] as String?;
    final showTeamLeads = role == 'admin' ||
        roleTier == 'team_leader' ||
        roleTier == 'partner_agency';
    final displayName = email.contains('@') ? email.split('@').first : email;
    final roleLabel = _roleLabel(role);
    final initials = _initials(displayName);

    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceBase,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'You',
          style: GoogleFonts.fraunces(
            fontSize: 21,
            fontWeight: FontWeight.w500,
            color: AppColors.inkPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // Profile header (evergreen card)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.evergreen,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.brassSoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Color(0xFF6E5423),
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName.isEmpty ? 'Signed in' : displayName,
                        style: const TextStyle(
                          color: Color(0xFFF2EEE2),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (roleLabel != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          roleLabel,
                          style: TextStyle(
                            color: const Color(0xFFE9E4D6).withValues(alpha: 0.55),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Existing motivation widgets (unchanged, same providers)
          const PersonalStatsCard(),
          const MonthlyBestSection(),

          // Workspace rows (builder-ops)
          const Padding(
            padding: EdgeInsets.fromLTRB(0, 20, 0, 8),
            child: Text(
              'WORKSPACE',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.26,
                color: AppColors.inkSecondary,
              ),
            ),
          ),
          _RowItem(
            icon: Icons.grid_view_rounded,
            title: 'Availability',
            subtitle: 'Live unit grid · hold status',
            onTap: () => context.push('/inventory'),
          ),
          // Story 12.6-mobile — team-scoped lead visibility (leader/head/partner).
          // Best-effort entry gate; get_team_leads scopes per tier server-side.
          if (showTeamLeads)
            _RowItem(
              icon: Icons.groups_rounded,
              title: 'Team leads',
              subtitle: 'Leads across your team · agency',
              onTap: () => context.push('/team-leads'),
            ),
          // Story 15.5-mobile — booking dashboard (head/leader management view).
          // get_active_holds/get_booking_stats scope by visible_user_ids() server-side.
          if (role == 'admin' || roleTier == 'team_leader')
            _RowItem(
              icon: Icons.event_available_rounded,
              title: 'Booking dashboard',
              subtitle: 'Active holds · countdown · conversion',
              onTap: () => context.push('/booking'),
            ),
          // Story 16.2-mobile — execution-team amendment surface. Membership is a
          // table (not a JWT claim), so gate cosmetically to head; the screen shows a
          // calm state + self-join for a non-member head. RPCs re-check server-side.
          if (role == 'admin')
            _RowItem(
              icon: Icons.build_circle_outlined,
              title: 'Amendments',
              subtitle: 'Execution team · change requests',
              onTap: () => context.push('/amendments'),
            ),
          // Story 13.4-mobile — reception check-in (receptionist, or head).
          // Best-effort cosmetic gate; verify_visit re-checks the tier server-side.
          if (roleTier == 'receptionist' || role == 'admin')
            _RowItem(
              icon: Icons.how_to_reg_rounded,
              title: 'Reception check-in',
              subtitle: 'Verify a walk-in by visit code',
              onTap: () => context.push('/reception/verify'),
            ),
          // Story 12.4-mobile — builder-head only. `role == 'admin'` ≡ builder-head;
          // best-effort cosmetic gate (set_user_hierarchy re-checks server-side).
          if (role == 'admin')
            _RowItem(
              icon: Icons.account_tree_rounded,
              title: 'Organization',
              subtitle: 'Roles, reporting lines & agencies',
              onTap: () => context.push('/organization'),
            ),

          // Settings rows
          const Padding(
            padding: EdgeInsets.fromLTRB(0, 20, 0, 8),
            child: Text(
              'SETTINGS',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.26,
                color: AppColors.inkSecondary,
              ),
            ),
          ),
          _RowItem(
            icon: Icons.inventory_2_outlined,
            title: 'Archived leads',
            subtitle: 'Dead & closed · restore from here',
            onTap: () => context.push('/archived'),
          ),
          _RowItem(
            icon: Icons.alarm_rounded,
            title: 'Follow-up alarms',
            subtitle: 'Ring & reminder settings',
            onTap: () => context.push('/settings/alarms'),
          ),
          _RowItem(
            icon: Icons.lock_outline_rounded,
            title: 'Change password',
            subtitle: 'Update your login credentials',
            // Query param survives OS route restoration; in-memory extra does not.
            onTap: () => context.go('/password-change?forced=false'),
          ),
          _RowItem(
            icon: Icons.logout_rounded,
            iconBg: AppColors.statusHotBg,
            iconColor: AppColors.danger,
            title: 'Log out',
            titleColor: AppColors.danger,
            subtitle: 'Sign out of this device',
            showChevron: false,
            onTap: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final letters = name.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (letters.isEmpty) return '·';
    if (letters.length == 1) return letters.toUpperCase();
    return letters.substring(0, 2).toUpperCase();
  }

  static String? _roleLabel(String? role) {
    if (role == null || role.isEmpty) return null;
    return role[0].toUpperCase() + role.substring(1);
  }
}

class _RowItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconBg;
  final Color? iconColor;
  final Color? titleColor;
  final bool showChevron;

  const _RowItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconBg,
    this.iconColor,
    this.titleColor,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconBg ?? AppColors.mist,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon,
                      size: 18, color: iconColor ?? AppColors.inkSecondary),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: titleColor ?? AppColors.inkPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.inkSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (showChevron)
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.inkDisabled),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
