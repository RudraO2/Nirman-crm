// Story 2.5 — Lead card widget · UI redesign §6.3
// White card, hairline border, 16px radius. Row 1 = red dot (incomplete) + name
// + tinted status pill. Meta line = phone · location. ONE flag line replacing
// the old stacked badges: a state span (pending > incomplete > untouched >
// shared > stale, by priority) optionally paired with the next follow-up / visit
// date span (red when overdue). Pending-outcome keeps the 3px brass left edge;
// stale keeps dimming.

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
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 3px pending-outcome left accent (brass-bright).
                if (lead.hasPendingOutcome)
                  Container(width: 3, color: AppColors.brassBright),

                // Card body
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
                    child: _CardBody(lead: lead),
                  ),
                ),
              ],
            ),
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

    final state = _stateFlag(lead);
    final date = _dateFlag(lead);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Row 1: red dot (incomplete) + name | status pill ───────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (lead.isIncomplete) ...[
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.statusHot,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
            ],
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

        // ── Meta line: phone · location ────────────────────────────────────
        const SizedBox(height: 3),
        Row(
          children: [
            Text(
              lead.displayPhone,
              style: TextStyle(fontSize: 12.5, color: metaColor),
            ),
            if (lead.location != null && lead.location!.isNotEmpty) ...[
              Text(' · ',
                  style: TextStyle(color: AppColors.inkDisabled, fontSize: 12.5)),
              Expanded(
                child: Text(
                  lead.location!,
                  style: TextStyle(fontSize: 12.5, color: metaColor),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),

        // ── Single flag line: state span (· date span) ─────────────────────
        if (state != null || date != null) ...[
          const SizedBox(height: 5),
          Row(
            children: [
              if (state != null)
                Flexible(
                  child: Text(
                    state.text,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: state.color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (state != null && date != null)
                Text(' · ',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkDisabled)),
              if (date != null)
                Flexible(
                  child: Text(
                    date.text,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: date.color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  // Primary state flag — mockup priority (pending > incomplete > untouched >
  // shared > stale). Overdue / upcoming dates ride in the separate date span.
  static _Flag? _stateFlag(LeadListItem lead) {
    if (lead.hasPendingOutcome) {
      return const _Flag('Awaiting outcome', Color(0xFF7A5D24));
    }
    if (lead.isIncomplete) {
      return const _Flag('Incomplete', AppColors.statusIncomplete);
    }
    if (lead.isUntouched) {
      return const _Flag('Untouched', AppColors.statusCold);
    }
    if (lead.isShared) {
      return const _Flag('Shared', AppColors.statusFuture);
    }
    if (lead.isStale) {
      return const _Flag('Stale', AppColors.statusWarm);
    }
    return null;
  }

  static _Flag? _dateFlag(LeadListItem lead) {
    if (lead.nextFollowupAt != null) {
      return _Flag(
        _followupLabel(lead.nextFollowupAt!),
        lead.hasOverdueFollowup ? AppColors.error : AppColors.inkSecondary,
      );
    }
    if (lead.visitDate != null) {
      return _Flag('Visit ${_dateLabel(lead.visitDate!)}', AppColors.inkSecondary);
    }
    return null;
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
