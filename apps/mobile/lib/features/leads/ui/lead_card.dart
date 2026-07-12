// Story 2.5 — Lead card widget · rep-home v2 (2026-07-13).
// ONE-SIGNAL rule: name + status pill, a single grey meta line
// (phone · location · code · visit), and AT MOST ONE flag line in at most
// one color. The old card wore four signal systems at once (red incomplete
// dot, blue Untouched, red Overdue, brass side stripe) — Rudra: "some red
// things, some blue things, not organized." Side-stripe accents are also a
// design-system ban.

import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../data/models/lead_model.dart';

class LeadCard extends StatelessWidget {
  final LeadListItem lead;
  final VoidCallback? onTap;

  const LeadCard({super.key, required this.lead, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${lead.name ?? 'No name'}, ${lead.status.statusLabel} status',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
            child: _CardBody(lead: lead),
          ),
        ),
      ),
    );
  }
}

// ── Card body ──────────────────────────────────────────────────────────────

class _CardBody extends StatelessWidget {
  final LeadListItem lead;
  const _CardBody({required this.lead});

  @override
  Widget build(BuildContext context) {
    final dim = lead.isStale;
    final nameColor = dim ? AppColors.inkDisabled : AppColors.inkPrimary;
    final metaColor = dim ? AppColors.inkDisabled : AppColors.inkSecondary;

    final flag = _flag(lead);
    final metaBits = <String>[
      lead.displayPhone,
      if (lead.location != null && lead.location!.isNotEmpty) lead.location!,
      if (lead.customerCode != null) lead.customerCode!,
      if (lead.visitCount > 0) '${visitOrdinal(lead.visitCount)} visit',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Row 1: name | status pill ──────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                lead.name ?? 'No name',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: nameColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _StatusPill(status: lead.status),
          ],
        ),

        // ── ONE meta line: phone · location · code · visit ─────────────────
        const SizedBox(height: 3),
        Text(
          metaBits.join(' · '),
          style: TextStyle(fontSize: 12.5, color: metaColor),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        // ── ONE flag, one color, most-actionable wins ───────────────────────
        if (flag != null) ...[
          const SizedBox(height: 5),
          Text(
            flag.text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: flag.color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  // THE flag — single most-actionable thing about this lead, one color.
  // Red is reserved for overdue (a real fire). Everything else is amber
  // (needs you) or grey (context). Priority: call outcome > overdue >
  // follow-up today > untouched > incomplete > upcoming date > shared > stale.
  static _Flag? _flag(LeadListItem lead) {
    if (lead.hasPendingOutcome) {
      return const _Flag('Log your call outcome', AppColors.statusWarm);
    }
    if (lead.nextFollowupAt != null && lead.hasOverdueFollowup) {
      return _Flag(_followupLabel(lead.nextFollowupAt!), AppColors.error);
    }
    if (lead.nextFollowupAt != null && _isToday(lead.nextFollowupAt!)) {
      return _Flag(
          'Follow-up ${_followupLabel(lead.nextFollowupAt!)}', AppColors.statusWarm);
    }
    if (lead.isUntouched) {
      return const _Flag('New — not contacted yet', AppColors.inkSecondary);
    }
    if (lead.isIncomplete) {
      return const _Flag('Details missing', AppColors.statusIncomplete);
    }
    if (lead.nextFollowupAt != null) {
      return _Flag('Follow-up ${_followupLabel(lead.nextFollowupAt!)}',
          AppColors.inkSecondary);
    }
    if (lead.visitDate != null) {
      return _Flag(
          'Visit ${_dateLabel(lead.visitDate!)}', AppColors.inkSecondary);
    }
    if (lead.isShared) {
      return const _Flag('Shared with you', AppColors.inkSecondary);
    }
    if (lead.isStale) {
      return const _Flag('No activity for a while', AppColors.inkDisabled);
    }
    return null;
  }

  static bool _isToday(DateTime dt) {
    final l = dt.toLocal();
    final now = DateTime.now();
    return l.year == now.year && l.month == now.month && l.day == now.day;
  }

  static String _followupLabel(DateTime dt) {
    final now   = DateTime.now();
    final local = dt.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final dDay  = DateTime(local.year, local.month, local.day);
    final diff  = dDay.difference(today).inDays;
    final t     = _formatTime(local);
    if (diff < 0)  return 'Overdue ${-diff}d';
    if (diff == 0) return 'Today $t';
    if (diff == 1) return 'Tomorrow $t';
    return '${local.day}/${local.month} $t';
  }

  static String _dateLabel(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day}/${local.month} ${_formatTime(local)}';
  }

  static String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m ${dt.hour >= 12 ? 'pm' : 'am'}';
  }
}

class _Flag {
  final String text;
  final Color color;
  const _Flag(this.text, this.color);
}

// ── Status pill ───────────────────────────────────────────────────────────
// UI redesign: colored dot + capitalized word on a tinted pill background.

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final fg = status.statusColor;
    final bg = status.statusBgColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
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
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
