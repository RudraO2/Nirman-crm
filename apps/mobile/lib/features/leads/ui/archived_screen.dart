// Story 2.8 — Archive screen: caller's Dead/Sold/Future leads with search + restore.
// FR-16: not deleted, retrievable. FR-31: caller-scoped via auth.uid() in the RPC.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../data/lead_repository.dart';
import '../data/models/lead_model.dart';
import '../providers/lead_providers.dart';
import '../../motivation/providers/motivation_providers.dart';
import 'lead_card.dart';

const _pageSize = 50;
const _activeStatuses = ['hot', 'warm', 'cold'];

class ArchivedScreen extends ConsumerStatefulWidget {
  const ArchivedScreen({super.key});

  @override
  ConsumerState<ArchivedScreen> createState() => _ArchivedScreenState();
}

class _ArchivedScreenState extends ConsumerState<ArchivedScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _debounce;
  String _query = '';

  // Paginated list managed locally. The family provider is intentionally NOT
  // watched here — the screen owns the page state — but we still invalidate it
  // on restore so other consumers (if any) re-fetch.
  final List<LeadListItem> _leads = [];
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  // P13: request-id token. _fetch reads the token at start and bails on apply
  // if a newer fetch has begun in the meantime, so stale results never overwrite fresh.
  int _fetchToken = 0;

  @override
  void initState() {
    super.initState();
    _fetch(reset: true);
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _query = value.trim());
      _fetch(reset: true);
    });
  }

  void _onScroll() {
    if (_loading || !_hasMore) return;
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      _fetch();
    }
  }

  Future<void> _fetch({bool reset = false}) async {
    if (_loading) return;
    final token = ++_fetchToken; // claim this fetch
    setState(() {
      _loading = true;
      if (reset) {
        _leads.clear();
        _hasMore = true;
        _error = null;
      }
    });
    try {
      final page = await ref.read(leadRepositoryProvider).getMyArchivedLeads(
            query: _query,
            limit: _pageSize,
            offset: _leads.length,
          );
      if (!mounted || token != _fetchToken) return; // a newer fetch superseded us
      setState(() {
        _leads.addAll(page);
        _hasMore = page.length == _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _fetchToken) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _restore(LeadListItem lead) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _RestorePickerSheet(),
    );
    if (picked == null || !mounted) return;
    try {
      await ref.read(leadRepositoryProvider).restoreLead(lead.id, picked);
      ref.invalidate(myLeadsProvider);
      ref.invalidate(myMotivationStatsProvider);
      ref.invalidate(myMonthlyBestProvider);
      if (!mounted) return;
      // Refetch the page rather than mutating _leads locally. Optimistic removal
      // + offset-based pagination could silently skip a lead from the next page
      // because `offset = _leads.length` shifts after removal.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Restored to ${_capitalize(picked)}.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceRaised,
      ));
      await _fetch(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not restore. Try again.')),
      );
    }
  }

  static String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        title: Text(
          'Archived',
          style: GoogleFonts.fraunces(
            fontSize: 21,
            fontWeight: FontWeight.w500,
            color: AppColors.inkPrimary,
          ),
        ),
        backgroundColor: AppColors.surfaceBase,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.inkSecondary),
      ),
      body: Column(
        children: [
          // Search box
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText: 'Search name or phone',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onQueryChanged('');
                        },
                      ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                filled: true,
                fillColor: AppColors.paper,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.borderStrong, width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.borderStrong, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.brass, width: 1.5),
                ),
              ),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null && _leads.isEmpty) {
      return _ErrorView(text: _error!, onRetry: () => _fetch(reset: true));
    }
    if (_loading && _leads.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_leads.isEmpty) {
      return _EmptyView(query: _query);
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _leads.length + (_hasMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= _leads.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final lead = _leads[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _ArchivedTile(
            lead: lead,
            onTap: () => context.push('/lead/${lead.id}'),
            onRestore: () => _restore(lead),
          ),
        );
      },
    );
  }
}

class _ArchivedTile extends StatelessWidget {
  final LeadListItem lead;
  final VoidCallback onTap;
  final VoidCallback onRestore;
  const _ArchivedTile({required this.lead, required this.onTap, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Archived cards read as dimmed (mockup #s-archived).
        Opacity(opacity: 0.7, child: LeadCard(lead: lead, onTap: onTap)),
        Positioned(
          top: 6,
          right: 6,
          child: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 18),
            color: AppColors.surfaceRaised,
            onSelected: (v) {
              if (v == 'restore') onRestore();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'restore',
                child: Row(
                  children: [
                    Icon(Icons.restart_alt_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('Restore…'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RestorePickerSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Restore to which status?',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.inkPrimary,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: [
                for (final s in _activeStatuses)
                  ChoiceChip(
                    label: Text(_label(s)),
                    selected: false,
                    onSelected: (_) => Navigator.of(context).pop(s),
                    backgroundColor: AppColors.surfaceBase,
                    labelStyle: const TextStyle(color: AppColors.inkPrimary),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.inkSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _label(String s) => '${s[0].toUpperCase()}${s.substring(1)}';
}

class _EmptyView extends StatelessWidget {
  final String query;
  const _EmptyView({required this.query});

  @override
  Widget build(BuildContext context) {
    final hasQuery = query.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.inkDisabled),
            const SizedBox(height: 12),
            Text(
              hasQuery ? "No matches for '$query'." : 'No archived leads yet.',
              style: const TextStyle(fontSize: 15, color: AppColors.inkSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String text;
  final VoidCallback onRetry;
  const _ErrorView({required this.text, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 40),
            const SizedBox(height: 10),
            const Text(
              'Could not load archive',
              style: TextStyle(fontSize: 15, color: AppColors.inkPrimary),
            ),
            const SizedBox(height: 6),
            SelectableText(
              text,
              style: const TextStyle(fontSize: 11, color: AppColors.inkSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
