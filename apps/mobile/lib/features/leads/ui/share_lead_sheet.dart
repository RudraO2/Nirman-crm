// Story 4.4 — Share Lead bottom sheet.
// Lists active employees in the tenant (self filtered out).
// Tapping an employee calls share_lead RPC and pops with true.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../data/lead_repository.dart';
import '../providers/lead_providers.dart';

Future<bool?> showShareLeadSheet(BuildContext context, String leadId) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ShareLeadSheet(leadId: leadId),
  );
}

class _ShareLeadSheet extends ConsumerStatefulWidget {
  final String leadId;
  const _ShareLeadSheet({required this.leadId});

  @override
  ConsumerState<_ShareLeadSheet> createState() => _ShareLeadSheetState();
}

class _ShareLeadSheetState extends ConsumerState<_ShareLeadSheet> {
  String? _loadingId;

  Future<void> _onTap(String recipientId) async {
    setState(() => _loadingId = recipientId);
    try {
      await ref.read(leadRepositoryProvider).shareLead(widget.leadId, recipientId);
      ref.invalidate(leadSharesProvider(widget.leadId));
      ref.invalidate(myLeadsProvider);
      ref.invalidate(leadTimelineProvider(widget.leadId));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _loadingId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not share lead. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final employeesAsync = ref.watch(employeesForShareProvider);
    final selfId = Supabase.instance.client.auth.currentUser?.id;

    if (selfId == null) {
      return Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.borderHairline),
        ),
        child: Text(
          'Session expired. Please log in again.',
          style: TextStyle(color: AppColors.inkSecondary, fontSize: 14),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderHairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: 42, height: 4.5,
                decoration: BoxDecoration(
                  color: AppColors.borderStrong,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Text(
              'Share with',
              style: GoogleFonts.fraunces(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: AppColors.inkPrimary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'Select a teammate to share this lead with.',
              style: TextStyle(fontSize: 13, color: AppColors.inkSecondary),
            ),
          ),
          const Divider(height: 1, color: AppColors.borderHairline),
          employeesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.accentStrong,
                ),
              ),
            ),
            error: (_, __) => Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Could not load teammates.',
                style: TextStyle(color: AppColors.inkSecondary, fontSize: 13),
              ),
            ),
            data: (employees) {
              final filtered = employees.where((e) => e.id != selfId).toList();
              if (filtered.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'No other active employees in your team.',
                    style: TextStyle(color: AppColors.inkSecondary, fontSize: 13),
                  ),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: filtered.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 20, color: AppColors.borderHairline),
                itemBuilder: (_, i) {
                  final emp = filtered[i];
                  final isLoading = _loadingId == emp.id;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    leading: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.accentSoft.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          emp.username.isNotEmpty
                              ? emp.username[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accentStrong,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      emp.username,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.inkPrimary,
                      ),
                    ),
                    trailing: isLoading
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.accentStrong,
                            ),
                          )
                        : Icon(
                            Icons.share_rounded,
                            size: 18,
                            color: AppColors.inkDisabled,
                          ),
                    onTap: isLoading ? null : () => _onTap(emp.id),
                  );
                },
              );
            },
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}
