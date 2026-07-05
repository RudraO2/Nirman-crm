// UI redesign §6.2 — bottom tab shell (Leads / Plan / You).
//
// Hosts the EXISTING screens via StatefulShellRoute.indexedStack: no screen
// logic moves here. indexedStack keeps every branch mounted, so HomeScreen's
// initState alarm-sync listener and resume observer keep firing regardless of
// which tab is active.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../leads/data/models/lead_model.dart';
import '../../leads/providers/lead_providers.dart';

class AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Overdue follow-up count → red badge on the Plan tab. Reads the existing
    // myLeadsProvider (same source FollowupsScreen groups under "OVERDUE"); no
    // new query. Falls back to 0 while loading / on error.
    final overdue = ref.watch(myLeadsProvider).maybeWhen(
          data: _overdueCount,
          orElse: () => 0,
        );

    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      body: navigationShell,
      bottomNavigationBar: _TabBar(
        currentIndex: navigationShell.currentIndex,
        planBadge: overdue,
        onTap: (i) => navigationShell.goBranch(
          i,
          // Re-tapping the active tab pops to its initial location.
          initialLocation: i == navigationShell.currentIndex,
        ),
      ),
    );
  }

  static int _overdueCount(List<LeadListItem> leads) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return leads.where((l) {
      final dt = l.nextFollowupAt;
      if (dt == null) return false;
      final loc = dt.toLocal();
      return DateTime(loc.year, loc.month, loc.day).isBefore(today);
    }).length;
  }
}

class _TabBar extends StatelessWidget {
  final int currentIndex;
  final int planBadge;
  final ValueChanged<int> onTap;

  const _TabBar({
    required this.currentIndex,
    required this.planBadge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceBase,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            children: [
              _TabItem(
                icon: Icons.groups_2_outlined,
                activeIcon: Icons.groups_2_rounded,
                label: 'Leads',
                selected: currentIndex == 0,
                onTap: () => onTap(0),
              ),
              _TabItem(
                icon: Icons.event_note_outlined,
                activeIcon: Icons.event_note_rounded,
                label: 'Plan',
                selected: currentIndex == 1,
                badge: planBadge,
                onTap: () => onTap(1),
              ),
              _TabItem(
                icon: Icons.person_outline_rounded,
                activeIcon: Icons.person_rounded,
                label: 'You',
                selected: currentIndex == 2,
                onTap: () => onTap(2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  const _TabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.evergreen : AppColors.inkDisabled;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44,
                    height: 26,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.brassSoft
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    alignment: Alignment.center,
                    child: Icon(selected ? activeIcon : icon,
                        size: 21, color: color),
                  ),
                  if (badge > 0)
                    Positioned(
                      right: 0,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.statusHot,
                          borderRadius: BorderRadius.circular(9999),
                        ),
                        constraints: const BoxConstraints(minWidth: 16),
                        child: Text(
                          '$badge',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
