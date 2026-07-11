// Story 2.4 — Lead detail screen
// Shows lead info (status pill, name, phone, all filled fields).
// Edit FAB → showEditLeadSheet().
// Timeline stub (entries rendered in a future story).
// 404 guard: if lead not found in queue, toast + pop back.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../data/lead_repository.dart';
import '../data/models/lead_model.dart';
import '../providers/lead_providers.dart';
import 'edit_lead_sheet.dart';
import 'reschedule_visit_sheet.dart';
import 'schedule_followup_sheet.dart';
import 'share_lead_sheet.dart';
import 'whatsapp_sheet.dart';

class LeadDetailScreen extends ConsumerWidget {
  final String leadId;
  const LeadDetailScreen({super.key, required this.leadId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leadAsync = ref.watch(leadByIdProvider(leadId));

    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceBase,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.inkPrimary),
        title: Text(
          'Lead',
          style: GoogleFonts.fraunces(
            fontSize: 21,
            fontWeight: FontWeight.w500,
            color: AppColors.inkPrimary,
          ),
        ),
        actions: [
          if (leadAsync.valueOrNull?.visitDate != null)
            IconButton(
              icon: const Icon(Icons.schedule_rounded),
              color: AppColors.inkSecondary,
              tooltip: 'Reschedule visit',
              onPressed: () async {
                final lead = leadAsync.valueOrNull;
                if (lead == null) return;
                final rescheduled = await showRescheduleVisitSheet(
                  context, leadId, lead.visitDate,
                );
                if (rescheduled == true) {
                  ref.invalidate(leadByIdProvider(leadId));
                  ref.invalidate(myLeadsProvider);
                }
              },
            ),
          // Edit moved from a FAB to the AppBar pencil (same showEditLeadSheet).
          if (leadAsync.valueOrNull != null)
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              color: AppColors.inkSecondary,
              tooltip: 'Edit lead',
              onPressed: () async {
                final lead = leadAsync.valueOrNull;
                if (lead == null) return;
                final updated = await showEditLeadSheet(context, lead);
                if (updated == true) {
                  ref.invalidate(leadByIdProvider(leadId));
                }
              },
            ),
        ],
      ),
      body: leadAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accentStrong),
        ),
        error: (_, __) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Lead not found in your queue.')),
              );
              Navigator.of(context).pop();
            }
          });
          return const SizedBox.shrink();
        },
        data: (lead) {
          if (lead == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Lead not found in your queue.')),
                );
                Navigator.of(context).pop();
              }
            });
            return const SizedBox.shrink();
          }
          return _LeadDetailView(lead: lead);
        },
      ),
    );
  }
}

// ── Detail view ────────────────────────────────────────────────────────────

class _LeadDetailView extends ConsumerWidget {
  final LeadDetail lead;
  const _LeadDetailView({required this.lead});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        // ── Hero card ──────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (lead.isIncomplete)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              '● Incomplete',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.statusHot,
                              ),
                            ),
                          ),
                        Text(
                          lead.name ?? 'No name',
                          style: GoogleFonts.fraunces(
                            fontSize: 23,
                            fontWeight: FontWeight.w500,
                            color: AppColors.inkPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (lead.phone != null)
                          GestureDetector(
                            onTap: () => _onCallTap(context, ref),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.waGreen,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.waGreen.withValues(alpha: 0.35),
                                    blurRadius: 18,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.call_rounded, size: 17, color: Colors.white),
                                  const SizedBox(width: 9),
                                  Text(
                                    lead.displayPhone,
                                    style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(width: 9),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.25),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: const Text(
                                      'CALL',
                                      style: TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Text('No phone', style: TextStyle(fontSize: 15, color: AppColors.inkSecondary)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _StatusBadge(status: lead.status),
                ],
              ),
              if (lead.hasPendingOutcome) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.brassSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.access_time_rounded, size: 15, color: Color(0xFF7A5D24)),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          'Call outcome pending — log it when you hang up',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF7A5D24)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 10),

        // ── Quick actions row ──────────────────────────────────────────
        Row(
          children: [
            if (lead.phone != null) ...[
              Expanded(
                child: _ActionButton(
                  icon: Icons.chat_rounded,
                  label: 'WhatsApp',
                  color: const Color(0xFF25D366),
                  onTap: () => showWhatsAppSheet(context, lead),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: _ActionButton(
                icon: Icons.event_rounded,
                label: 'Follow-up',
                color: AppColors.accentStrong,
                onTap: () async {
                  final saved = await showScheduleFollowupSheet(
                    context, lead.id, lead.nextFollowupAt,
                  );
                  if (saved == true) {
                    ref.invalidate(leadByIdProvider(lead.id));
                    ref.invalidate(myLeadsProvider);
                  }
                },
              ),
            ),
            // Share button: only for owned leads (not when caller is recipient)
            if (!lead.isShared) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: Icons.share_rounded,
                  label: 'Share',
                  color: AppColors.evergreen,
                  fgColor: AppColors.brassBright,
                  onTap: () async {
                    final shared = await showShareLeadSheet(context, lead.id);
                    if (shared == true) {
                      ref.invalidate(leadSharesProvider(lead.id));
                    }
                  },
                ),
              ),
            ],
          ],
        ),

        // ── Shared-with chips (owned leads only) ───────────────────────
        if (!lead.isShared)
          Consumer(builder: (context, ref, _) {
            final sharesAsync = ref.watch(leadSharesProvider(lead.id));
            return sharesAsync.maybeWhen(
              data: (shares) {
                if (shares.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final share in shares)
                        _ShareChip(
                          username: share.recipientUsername,
                          onRevoke: () async {
                            try {
                              await ref
                                  .read(leadRepositoryProvider)
                                  .revokeLead(lead.id, share.recipientUserId);
                              ref.invalidate(leadSharesProvider(lead.id));
                              ref.invalidate(myLeadsProvider);
                              ref.invalidate(leadTimelineProvider(lead.id));
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Could not revoke share.')),
                                );
                              }
                            }
                          },
                        ),
                    ],
                  ),
                );
              },
              orElse: () => const SizedBox.shrink(),
            );
          }),

        const SizedBox(height: 12),

        // ── Combined details + remarks card (§6.4) ─────────────────────
        Builder(builder: (context) {
          // "Property · size" combines propertyType + ticketSize when both
          // present, else whichever exists.
          final propSize = [lead.propertyType, lead.ticketSize]
              .where((v) => v != null && v.isNotEmpty)
              .join(' · ');
          final rows = <_DetailEntry>[
            if (lead.source != null)
              _DetailEntry('Source', _sourceLabel(lead.source!)),
            if (propSize.isNotEmpty)
              _DetailEntry('Property · size', propSize),
            if (lead.location != null)
              _DetailEntry('Location', lead.location!),
            if (lead.budgetMin != null || lead.budgetMax != null)
              _DetailEntry('Budget', _budgetLabel(lead.budgetMin, lead.budgetMax)),
            if (lead.visitDate != null)
              _DetailEntry('Visit', _dateLabel(lead.visitDate!)),
            if (lead.nextFollowupAt != null)
              _DetailEntry('Follow-up', _dateLabel(lead.nextFollowupAt!),
                  valueColor: lead.hasOverdueFollowup ? AppColors.statusHot : null),
            if (lead.interestType != null)
              _DetailEntry('Interest', lead.interestType!),
          ];
          // Story 13.8-mobile — surface customer_code + visit ordinal straight off
          // the get_lead_by_id RPC row (0093 added the columns; the old direct-read
          // shim is retired). Appended after the core rows.
          if (lead.customerCode != null) {
            rows.add(_DetailEntry('Visit code', lead.customerCode!));
          }
          if (lead.visitCount > 0) {
            rows.add(_DetailEntry('Visits', _visitLabel(lead.visitCount)));
          }
          final hasRemarks = lead.remarks != null && lead.remarks!.isNotEmpty;
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < rows.length; i++)
                  _DetailRow(
                    label: rows[i].label,
                    value: rows[i].value,
                    valueColor: rows[i].valueColor,
                    // Bottom hairline between rows; none on the last row unless
                    // remarks follow (the remarks block draws its own dashed rule).
                    showBorder: i < rows.length - 1,
                  ),
                if (hasRemarks) ...[
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.only(top: 11),
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AppColors.borderStrong),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('REMARKS', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.26, color: AppColors.inkSecondary)),
                        const SizedBox(height: 5),
                        Text(lead.remarks!, style: TextStyle(fontSize: 13, color: AppColors.inkPrimary, height: 1.55)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        }),

        const SizedBox(height: 12),

        // ── Timeline ───────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TIMELINE', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.26, color: AppColors.inkSecondary)),
              const SizedBox(height: 12),
              Consumer(builder: (context, ref, _) {
                final timelineAsync = ref.watch(leadTimelineProvider(lead.id));
                return timelineAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentStrong))),
                  ),
                  error: (e, _) => Text('Could not load timeline.', style: TextStyle(fontSize: 12, color: AppColors.inkSecondary)),
                  data: (events) {
                    if (events.isEmpty) {
                      return Text('No events yet.', style: TextStyle(fontSize: 13, color: AppColors.inkSecondary));
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < events.length; i++)
                          _TimelineRow(
                            entry: events[i],
                            isFirst: i == 0,
                            isLast: i == events.length - 1,
                          ),
                      ],
                    );
                  },
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _onCallTap(BuildContext context, WidgetRef ref) async {
    final phone = lead.phone;
    if (phone == null) return;
    try {
      await ref.read(leadRepositoryProvider).initiateCall(lead.id);
      ref.invalidate(leadByIdProvider(lead.id));
      ref.invalidate(myLeadsProvider);
      ref.invalidate(leadTimelineProvider(lead.id));
    } catch (_) {
      // Non-fatal: still open dialer even if RPC fails
    }
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  static String _sourceLabel(String s) {
    const m = {'walk_in': 'Walk-in', 'referral': 'Referral', 'associate': 'Associate', 'ad': 'Ad'};
    return m[s] ?? s;
  }

  // Story 13.4-mobile — "3 visits (3rd)" style label for the detail row.
  // Ordinal via the shared `visitOrdinal` helper (lead_model.dart).
  static String _visitLabel(int count) {
    final noun = count == 1 ? 'visit' : 'visits';
    return '$count $noun (${visitOrdinal(count)})';
  }

  static String _budgetLabel(int? min, int? max) {
    String fmt(int n) => '₹${(n / 100).toStringAsFixed(0)}';
    if (min != null && max != null) return '${fmt(min)} – ${fmt(max)}';
    if (min != null) return '${fmt(min)}+';
    if (max != null) return 'Up to ${fmt(max)}';
    return '';
  }

  static String _dateLabel(DateTime dt) {
    final l = dt.toLocal();
    return '${l.day}/${l.month}/${l.year} ${_formatTime(l)}';
  }

  static String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m ${dt.hour >= 12 ? 'pm' : 'am'}';
  }

  static String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays < 1) return 'today';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.toLocal().day}/${dt.toLocal().month}/${dt.toLocal().year}';
  }
}

class _TimelineRow extends StatelessWidget {
  final TimelineEntry entry;
  final bool isFirst;
  final bool isLast;
  const _TimelineRow({required this.entry, this.isFirst = false, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    final label = _eventDisplay(entry.eventType).$1;
    final detail = _eventDetail(entry);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Brass dot rail.
          SizedBox(
            width: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 2,
                  height: 4,
                  child: ColoredBox(
                    color: isFirst ? Colors.transparent : AppColors.line,
                  ),
                ),
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceRaised,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.brass, width: 2.5),
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    width: 2,
                    child: ColoredBox(
                      color: isLast ? Colors.transparent : AppColors.line,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkPrimary)),
                  if (detail != null) ...[
                    const SizedBox(height: 2),
                    Text(detail, style: TextStyle(fontSize: 12, color: AppColors.inkSecondary, height: 1.35)),
                  ],
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(_when(entry.occurredAt), style: TextStyle(fontSize: 11, color: AppColors.inkDisabled)),
                      if (entry.actorName != null && entry.actorRole != 'system') ...[
                        Text(' · ', style: TextStyle(fontSize: 11, color: AppColors.inkDisabled)),
                        Flexible(
                          child: Text('by ${entry.actorName}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: AppColors.inkDisabled)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static (String, IconData, Color) _eventDisplay(String type) {
    switch (type) {
      case 'lead_created':         return ('Lead created',          Icons.person_add_alt_1_rounded, AppColors.accentStrong);
      case 'field_updated':        return ('Field updated',         Icons.edit_rounded,             AppColors.inkSecondary);
      case 'status_changed':       return ('Status changed',        Icons.swap_horiz_rounded,       AppColors.accentStrong);
      case 'call_initiated':       return ('Called',                Icons.call_rounded,             const Color(0xFF25D366));
      case 'call_outcome_cleared': return ('Marked not called',     Icons.phone_disabled_rounded,   AppColors.inkSecondary);
      case 'whatsapp_sent':        return ('WhatsApp sent',         Icons.chat_rounded,             const Color(0xFF25D366));
      case 'followup_set':         return ('Follow-up scheduled',   Icons.event_rounded,            AppColors.accentStrong);
      case 'followup_rescheduled': return ('Follow-up rescheduled', Icons.event_repeat_rounded,     AppColors.accentStrong);
      case 'followup_overdue':     return ('Follow-up overdue',     Icons.warning_amber_rounded,    AppColors.error);
      case 'followup_completed':   return ('Follow-up completed',   Icons.check_circle_rounded,     const Color(0xFF1B7E3F));
      case 'visit_date_set':       return ('Visit scheduled',       Icons.location_on_rounded,      AppColors.accentStrong);
      case 'visit_rescheduled':    return ('Visit rescheduled',     Icons.schedule_rounded,         AppColors.accentStrong);
      case 'assigned':             return ('Assigned',              Icons.assignment_ind_rounded,   AppColors.accentStrong);
      case 'reassigned':           return ('Reassigned',            Icons.assignment_ind_rounded,   AppColors.accentStrong);
      case 'shared':               return ('Shared',                Icons.share_rounded,            AppColors.accentStrong);
      case 'share_revoked':        return ('Share revoked',         Icons.link_off_rounded,         AppColors.inkSecondary);
      case 'archived':             return ('Archived',              Icons.archive_rounded,          AppColors.inkSecondary);
      case 'restored':             return ('Restored',              Icons.unarchive_rounded,        AppColors.accentStrong);
      case 'duplicate_override':   return ('Duplicate override',    Icons.warning_amber_rounded,    AppColors.error);
      case 'remark_added':         return ('Remark added',          Icons.sticky_note_2_rounded,    AppColors.accentStrong);
      case 'imported':             return ('Imported',              Icons.file_upload_rounded,      AppColors.inkSecondary);
      // Epic 13 (lead reg v2) + Epic 16 (amendments) timeline events.
      case 'code_generated':       return ('Visit code generated',  Icons.qr_code_2_rounded,        AppColors.accentStrong);
      case 'visit_verified':       return ('Visit verified',        Icons.how_to_reg_rounded,       const Color(0xFF1B7E3F));
      case 'visit_logged':         return ('Visit logged',          Icons.location_on_rounded,      AppColors.accentStrong);
      case 'lead_reclaimed':       return ('Lead reclaimed',        Icons.assignment_ind_rounded,   AppColors.accentStrong);
      case 'amendment_logged':     return ('Amendment logged',      Icons.build_circle_rounded,     AppColors.accentStrong);
      default:                     return (type,                    Icons.history_rounded,          AppColors.inkSecondary);
    }
  }

  static String? _eventDetail(TimelineEntry e) {
    final p = e.payload;
    switch (e.eventType) {
      case 'status_changed':
        final f = p['from'] ?? p['old_status']; final t = p['to'] ?? p['new_status'];
        if (f != null && t != null) return '$f → $t';
        if (t != null) return 'New: $t';
        return null;
      case 'remark_added':
        return p['remarks'] as String? ?? p['remark'] as String?;
      case 'field_updated':
        final field = p['field'] as String?;
        if (field == null) return null;
        return 'Field: $field';
      case 'followup_set':
      case 'followup_rescheduled':
        final at = p['at'] as String? ?? p['to'] as String?;
        if (at == null) return null;
        try { return 'For ${_fmtDate(DateTime.parse(at))}'; } catch (_) { return null; }
      case 'visit_rescheduled':
        final from = p['from'] as String?; final to = p['to'] as String?;
        if (to == null) return null;
        try {
          final t = _fmtDate(DateTime.parse(to));
          if (from != null) {
            try { return '${_fmtDate(DateTime.parse(from))} → $t'; } catch (_) { return 'To $t'; }
          }
          return 'To $t';
        } catch (_) { return null; }
      case 'whatsapp_sent':
        return p['template_name'] as String?;
      case 'visit_verified':
      case 'visit_logged':
        final ord = p['visit_ordinal'];
        if (ord is int) return '${visitOrdinal(ord)} visit';
        return null;
      case 'amendment_logged':
        return p['description'] as String?;
      default:
        return null;
    }
  }

  static String _fmtDate(DateTime dt) {
    final l = dt.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final m = l.minute.toString().padLeft(2, '0');
    return '${l.day}/${l.month}/${l.year} $h:$m ${l.hour >= 12 ? 'pm' : 'am'}';
  }

  static String _when(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)  return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24)   return '${diff.inHours}h';
    if (diff.inDays < 7)     return '${diff.inDays}d';
    final l = dt.toLocal();
    return '${l.day}/${l.month}';
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color fgColor;
  final VoidCallback onTap;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.fgColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: fgColor),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fgColor)),
          ],
        ),
      ),
    );
  }
}

class _DetailEntry {
  final String label;
  final String value;
  final Color? valueColor;
  const _DetailEntry(this.label, this.value, {this.valueColor});
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool showBorder;
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: showBorder
          ? const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line)),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13.5, color: AppColors.inkSecondary)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13.5,
                color: valueColor ?? AppColors.inkPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Share chip (owned-lead shared-with row) ────────────────────────────────

class _ShareChip extends StatelessWidget {
  final String username;
  final VoidCallback onRevoke;
  const _ShareChip({required this.username, required this.onRevoke});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
      decoration: BoxDecoration(
        color: AppColors.statusFutureBg,
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: AppColors.statusFuture.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.swap_horiz_rounded, size: 13, color: AppColors.statusFuture),
          const SizedBox(width: 5),
          Text(
            username,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.statusFuture),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRevoke,
            child: Icon(Icons.close_rounded, size: 14, color: AppColors.statusFuture.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final fg = status.statusColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: status.statusBgColor,
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            status.statusLabel,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}
