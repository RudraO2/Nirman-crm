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
          style: GoogleFonts.sourceSerif4(
            fontSize: 20,
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
      floatingActionButton: leadAsync.valueOrNull == null
          ? null
          : FloatingActionButton(
              onPressed: () async {
                final lead = leadAsync.valueOrNull;
                if (lead == null) return;
                final updated = await showEditLeadSheet(context, lead);
                if (updated == true) {
                  ref.invalidate(leadByIdProvider(leadId));
                }
              },
              backgroundColor: AppColors.accentStrong,
              tooltip: 'Edit lead',
              child: const Icon(Icons.edit_rounded, color: Colors.white),
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
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderHairline),
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
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 8, height: 8,
                                  decoration: const BoxDecoration(
                                    color: AppColors.statusIncomplete,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Incomplete',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.statusIncomplete,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Text(
                          lead.name ?? 'No name',
                          style: GoogleFonts.sourceSerif4(
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                            color: AppColors.inkPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (lead.phone != null)
                          GestureDetector(
                            onTap: () => _onCallTap(context, ref),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF25D366),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF25D366).withOpacity(0.35),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.call_rounded, size: 18, color: Colors.white),
                                  const SizedBox(width: 8),
                                  Text(
                                    lead.displayPhone,
                                    style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.22),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: const Text(
                                      'CALL',
                                      style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.6),
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
                  _StatusBadge(status: lead.status),
                ],
              ),
              if (lead.hasPendingOutcome) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.access_time_rounded, size: 14, color: AppColors.accentStrong),
                      const SizedBox(width: 6),
                      Text('Call outcome pending', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.accentStrong)),
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
          ],
        ),

        const SizedBox(height: 12),

        // ── Details grid ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderHairline),
          ),
          child: Column(
            children: [
              if (lead.source != null) _DetailRow(label: 'Source', value: _sourceLabel(lead.source!)),
              if (lead.propertyType != null) _DetailRow(label: 'Property Type', value: lead.propertyType!),
              if (lead.location != null) _DetailRow(label: 'Location', value: lead.location!),
              if (lead.ticketSize != null) _DetailRow(label: 'Ticket Size', value: lead.ticketSize!),
              if (lead.budgetMin != null || lead.budgetMax != null)
                _DetailRow(label: 'Budget', value: _budgetLabel(lead.budgetMin, lead.budgetMax)),
              if (lead.visitDate != null) _DetailRow(label: 'Visit Date', value: _dateLabel(lead.visitDate!)),
              if (lead.nextFollowupAt != null) _DetailRow(label: 'Follow-up', value: _dateLabel(lead.nextFollowupAt!)),
              if (lead.interestType != null) _DetailRow(label: 'Interest Type', value: lead.interestType!),
            ],
          ),
        ),

        if (lead.remarks != null && lead.remarks!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderHairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('REMARKS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: AppColors.inkSecondary)),
                const SizedBox(height: 8),
                Text(lead.remarks!, style: TextStyle(fontSize: 14, color: AppColors.inkPrimary, height: 1.5)),
              ],
            ),
          ),
        ],

        const SizedBox(height: 12),

        // ── Timeline ───────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderHairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TIMELINE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: AppColors.inkSecondary)),
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
                        for (final e in events) _TimelineRow(entry: e),
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
  const _TimelineRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = _eventDisplay(entry.eventType);
    final detail = _eventDetail(entry);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkPrimary)),
                    ),
                    Text(_when(entry.occurredAt), style: TextStyle(fontSize: 11, color: AppColors.inkDisabled)),
                  ],
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(detail, style: TextStyle(fontSize: 12, color: AppColors.inkSecondary, height: 1.35)),
                ],
                if (entry.actorName != null && entry.actorRole != 'system') ...[
                  const SizedBox(height: 2),
                  Text('by ${entry.actorName}', style: TextStyle(fontSize: 11, color: AppColors.inkDisabled)),
                ],
              ],
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
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(fontSize: 13, color: AppColors.inkSecondary)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 13, color: AppColors.inkPrimary, fontWeight: FontWeight.w500)),
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
    final color = status.statusColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        status.statusLabel,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
