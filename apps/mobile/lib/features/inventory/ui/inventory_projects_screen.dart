// Story 14.3-mobile — project picker for the availability grid.
//
// Reuses the existing availableProjectsProvider (lead form's project fetch) — no
// new query. Tapping a project opens its live grid. Every tier lands here; the
// grid RPC scopes what each caller can actually see (a partner with no shared
// projects opens a grid and gets the friendly "not shared" state).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../leads/data/models/lead_model.dart';
import '../../leads/providers/lead_providers.dart';

class InventoryProjectsScreen extends ConsumerWidget {
  const InventoryProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(availableProjectsProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceBase,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Availability',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.inkPrimary,
          ),
        ),
      ),
      body: projectsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Couldn't load projects.",
                  style: TextStyle(color: AppColors.inkSecondary),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(availableProjectsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (projects) {
          if (projects.isEmpty) {
            return const Center(
              child: Text(
                'No active projects.',
                style: TextStyle(color: AppColors.inkSecondary),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              for (final p in projects) _ProjectRow(project: p),
            ],
          );
        },
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  final ProjectRef project;
  const _ProjectRow({required this.project});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push(
            '/inventory/${project.id}?name=${Uri.encodeComponent(project.name)}',
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                    color: AppColors.mist,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.apartment_rounded,
                      size: 18, color: AppColors.inkSecondary),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    project.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkPrimary,
                    ),
                  ),
                ),
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
