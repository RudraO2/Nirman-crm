// Story 14.3-mobile — live availability grid.
//
// Floor-grouped, colour-coded unit tiles for one project. Owns the `units`
// Realtime channel: an event → debounced `ref.invalidate(projectUnitsProvider)`,
// so the refresh always flows back through the authoritative get_project_units RPC
// (never renders the raw Realtime row → preserves margin/agency scoping). AC2 = ≤5s.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../data/inventory_repository.dart';
import '../data/models/unit_model.dart';
import '../providers/debouncer.dart';
import '../providers/inventory_providers.dart';
import 'unit_detail_sheet.dart';
import 'unit_status_style.dart';

class AvailabilityGridScreen extends ConsumerStatefulWidget {
  final String projectId;
  final String? projectName;

  const AvailabilityGridScreen({
    super.key,
    required this.projectId,
    this.projectName,
  });

  @override
  ConsumerState<AvailabilityGridScreen> createState() =>
      _AvailabilityGridScreenState();
}

class _AvailabilityGridScreenState
    extends ConsumerState<AvailabilityGridScreen> {
  RealtimeChannel? _channel;
  final _debouncer = Debouncer(const Duration(milliseconds: 400));

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    final client = Supabase.instance.client;
    _channel = client
        .channel('units:${widget.projectId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'units',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'project_id',
            value: widget.projectId,
          ),
          callback: (_) => _onRealtimeChange(),
        )
        .subscribe();
  }

  void _onRealtimeChange() {
    // Collapse a burst of row events into one authoritative refetch.
    _debouncer.run(() {
      if (!mounted) return;
      ref.invalidate(projectUnitsProvider(widget.projectId));
    });
  }

  @override
  void dispose() {
    _debouncer.dispose();
    final ch = _channel;
    if (ch != null) {
      Supabase.instance.client.removeChannel(ch);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unitsAsync = ref.watch(projectUnitsProvider(widget.projectId));

    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceBase,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          widget.projectName ?? 'Availability',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.inkPrimary,
          ),
        ),
      ),
      body: unitsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorState(
          error: err,
          onRetry: () => ref.invalidate(projectUnitsProvider(widget.projectId)),
        ),
        data: (units) {
          if (units.isEmpty) {
            return const _EmptyState(
              icon: Icons.grid_off_rounded,
              message: 'No units in this project yet.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(projectUnitsProvider(widget.projectId)),
            child: _GridBody(units: units, projectId: widget.projectId),
          );
        },
      ),
    );
  }
}

class _GridBody extends StatelessWidget {
  final List<ProjectUnit> units;
  final String projectId;
  const _GridBody({required this.units, required this.projectId});

  @override
  Widget build(BuildContext context) {
    // Group by floor, highest floor first; null floors bucket last.
    final byFloor = <int?, List<ProjectUnit>>{};
    for (final u in units) {
      byFloor.putIfAbsent(u.floor, () => []).add(u);
    }
    final floors = byFloor.keys.toList()
      ..sort((a, b) {
        if (a == null) return 1;
        if (b == null) return -1;
        return b.compareTo(a);
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        const _Legend(),
        const SizedBox(height: 12),
        for (final floor in floors) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 0, 8),
            child: Text(
              floor == null ? 'Other' : 'Floor $floor',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: AppColors.inkSecondary,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final u in byFloor[floor]!)
                _UnitTile(unit: u, projectId: projectId),
            ],
          ),
        ],
      ],
    );
  }
}

class _UnitTile extends StatelessWidget {
  final ProjectUnit unit;
  final String projectId;
  const _UnitTile({required this.unit, required this.projectId});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => UnitDetailSheet.show(context, unit, projectId),
      child: Container(
        width: 72,
        height: 60,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: unit.status.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              unit.unitNo,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: unit.status.foreground,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              unit.status.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: unit.status.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    const statuses = [
      UnitStatus.available,
      UnitStatus.hold,
      UnitStatus.sold,
      UnitStatus.blocked,
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final s in statuses)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: s.background,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: s.foreground.withValues(alpha: 0.5)),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                s.label,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.inkSecondary,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    // Partner opening a project not shared to their agency → friendly, not a crash.
    if (error is InventoryAccessException &&
        (error as InventoryAccessException).notShared) {
      return const _EmptyState(
        icon: Icons.lock_outline_rounded,
        message: "This project isn't shared with your agency.",
      );
    }
    if (error is InventoryAccessException &&
        (error as InventoryAccessException).notFound) {
      return const _EmptyState(
        icon: Icons.search_off_rounded,
        message: 'This project no longer exists.',
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.inkDisabled, size: 40),
            const SizedBox(height: 12),
            const Text(
              "Couldn't load availability.",
              style: TextStyle(color: AppColors.inkSecondary),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.inkDisabled, size: 40),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.inkSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
