// Story 12.4-mobile — Organization screen (builder-head hierarchy management).
//
// Mirrors the admin /hierarchy page: a partner-agencies card (list + inline create)
// and a user list (name + tier pill + reports-to manager + agency). Tapping a user
// opens the edit sheet → set_user_hierarchy. Head-only entry (gated in you_screen);
// the RPC/RLS re-check server-side so a leaked screen can mutate nothing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../data/hierarchy_repository.dart';
import '../data/models/agency.dart';
import '../data/models/hierarchy_user.dart';
import '../providers/hierarchy_providers.dart';
import 'edit_hierarchy_sheet.dart';
import 'tier_pill.dart';

class OrganizationScreen extends ConsumerWidget {
  const OrganizationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(hierarchyUsersProvider);
    final agenciesAsync = ref.watch(agenciesProvider);
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceBase,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Organization',
          style: AppType.display(
            fontSize: 21,
            fontWeight: FontWeight.w500,
            color: AppColors.inkPrimary,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(hierarchyUsersProvider);
          ref.invalidate(agenciesProvider);
          // Await so the spinner holds until data lands; swallow errors — the
          // `.when` branches render them. An unguarded throw would escape the
          // RefreshIndicator callback as an unhandled async error.
          try {
            await Future.wait([
              ref.read(hierarchyUsersProvider.future),
              ref.read(agenciesProvider.future),
            ]);
          } catch (_) {/* surfaced by the .when error branch */}
        },
        child: usersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(
            children: const [
              SizedBox(height: 120),
              Center(
                child: Text("Couldn't load your team.",
                    style: TextStyle(color: AppColors.inkSecondary)),
              ),
            ],
          ),
          data: (users) {
            final agencyList =
                agenciesAsync.asData?.value ?? const <Agency>[];
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                _AgencyCard(agencies: agencyList),
                const SizedBox(height: 20),
                const Padding(
                  padding: EdgeInsets.fromLTRB(0, 0, 0, 8),
                  child: Text(
                    'PEOPLE',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.26,
                      color: AppColors.inkSecondary,
                    ),
                  ),
                ),
                if (users.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('No users.',
                          style: TextStyle(color: AppColors.inkSecondary)),
                    ),
                  ),
                for (final u in users)
                  _UserRow(
                    user: u,
                    isCurrent: u.id == currentUserId,
                    managerName: _nameOf(users, u.reportsToUserId),
                    agencyName: u.isExternal
                        ? _agencyName(agencyList, u.agencyId)
                        : null,
                    onTap: () async {
                      final saved = await showEditHierarchySheet(
                        context,
                        user: u,
                        users: users,
                        agencies: agencyList,
                      );
                      if (saved == true) {
                        ref.invalidate(hierarchyUsersProvider);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  Text('${u.emailOrUsername} updated'),
                            ),
                          );
                        }
                      }
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _nameOf(List<HierarchyUser> users, String? id) {
    if (id == null) return '—';
    for (final u in users) {
      if (u.id == id) return u.emailOrUsername;
    }
    return '—';
  }

  static String _agencyName(List<Agency> agencies, String? id) {
    if (id == null) return '—';
    for (final a in agencies) {
      if (a.id == id) return a.name;
    }
    return '—';
  }
}

class _UserRow extends StatelessWidget {
  final HierarchyUser user;
  final bool isCurrent;
  final String managerName;
  final String? agencyName;
  final VoidCallback onTap;

  const _UserRow({
    required this.user,
    required this.isCurrent,
    required this.managerName,
    required this.agencyName,
    required this.onTap,
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
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              user.emailOrUsername,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.inkPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isCurrent)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Text('(you)',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.inkDisabled)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          TierPill(tier: user.roleTier),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              agencyName != null
                                  ? 'Agency: $agencyName'
                                  : 'Reports to: $managerName',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.inkSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.edit_outlined,
                    size: 18, color: AppColors.inkDisabled),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AgencyCard extends ConsumerStatefulWidget {
  final List<Agency> agencies;
  const _AgencyCard({required this.agencies});

  @override
  ConsumerState<_AgencyCard> createState() => _AgencyCardState();
}

class _AgencyCardState extends ConsumerState<_AgencyCard> {
  final _controller = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _adding = true);
    try {
      await ref.read(hierarchyRepositoryProvider).createAgency(name);
      _controller.clear();
      ref.invalidate(agenciesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Agency "$name" added')),
        );
      }
    } on HierarchyException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.friendly)));
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Partner agencies',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.inkPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (widget.agencies.isEmpty)
            const Text('No agencies yet.',
                style:
                    TextStyle(fontSize: 13, color: AppColors.inkSecondary))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in widget.agencies)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.line2),
                    ),
                    child: Text(a.name,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.inkPrimary)),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: !_adding,
                  decoration: InputDecoration(
                    hintText: 'New agency name',
                    filled: true,
                    fillColor: AppColors.surfaceSunk,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentStrong,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 14),
                ),
                onPressed: _adding ? null : _add,
                child: _adding
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
