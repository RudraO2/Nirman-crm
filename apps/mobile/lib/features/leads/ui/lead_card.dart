// Story 2.5 — Lead card widget
// UX spec: DESIGN.md §Lead Card: surface-raised bg, 1px hairline border, rounded/md 12px,
//   16px padding, pending-outcome 3px gold-soft left border, stale dims to ink-secondary.
// EXPERIENCE.md: name (body w500) + red dot if incomplete; phone + location (meta);
//   status pill top-right; last-action bottom-right; follow-up date with overdue callout.

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
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderHairline),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 3px pending-outcome left accent (gold-soft)
                if (lead.hasPendingOutcome)
                  Container(width: 3, color: AppColors.pendingOutcome),

                // Card body
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
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
    final nameColor = dim ? AppColors.inkSecondary : AppColors.inkPrimary;
    final metaColor = dim ? AppColors.inkDisabled  : AppColors.inkSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Row 1: name + incomplete dot | status pill ─────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (lead.isIncomplete) ...[
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.statusIncomplete,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                lead.name ?? 'No name',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: nameColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _StatusPill(status: lead.status),
          ],
        ),

        // ── Incomplete eyebrow ─────────────────────────────────────────────
        if (lead.isIncomplete) ...[
          const SizedBox(height: 2),
          const Text(
            'Incomplete',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.statusIncomplete,
            ),
          ),
        ],

        // ── Untouched badge — never actioned since creation (e.g. imported) ──
        if (lead.isUntouched) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.navy.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.navy.withValues(alpha: 0.30)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fiber_new_rounded, size: 11, color: AppColors.navy),
                const SizedBox(width: 3),
                Text(
                  'Untouched',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
          ),
        ],

        // ── Shared badge (Story 4.4 — lead shared with caller) ────────
        if (lead.isShared) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.navy.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.navy.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.share_rounded, size: 10, color: AppColors.navy),
                const SizedBox(width: 3),
                Text(
                  'Shared',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
          ),
        ],

        // ── Stale badge (urgency_score == 50 means 7+ days no action) ────
        if (lead.isStale && !lead.hasPendingOutcome) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF5A623).withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'Stale',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF5A623),
              ),
            ),
          ),
        ],

        // ── Pending outcome badge ──────────────────────────────────────────
        if (lead.hasPendingOutcome) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.accentSoft.withOpacity(0.35),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Awaiting outcome',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.accentStrong,
              ),
            ),
          ),
        ],

        const SizedBox(height: 6),

        // ── Row 2: phone + location ────────────────────────────────────────
        Row(
          children: [
            Text(
              lead.displayPhone,
              style: TextStyle(fontSize: 13, color: metaColor),
            ),
            if (lead.location != null && lead.location!.isNotEmpty) ...[
              Text(' · ', style: TextStyle(color: AppColors.inkDisabled, fontSize: 13)),
              Expanded(
                child: Text(
                  lead.location!,
                  style: TextStyle(fontSize: 13, color: metaColor),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),

        // ── Row 3: follow-up info | last action ───────────────────────────
        const SizedBox(height: 8),
        Row(
          children: [
            if (lead.nextFollowupAt != null)
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 12,
                      color: lead.hasOverdueFollowup ? AppColors.error : metaColor,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _followupLabel(lead.nextFollowupAt!),
                      style: TextStyle(
                        fontSize: 12,
                        color: lead.hasOverdueFollowup ? AppColors.error : metaColor,
                        fontWeight: lead.hasOverdueFollowup
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              )
            else
              const Expanded(child: SizedBox.shrink()),

            Text(
              _relativeTime(lead.lastActionAt),
              style: const TextStyle(fontSize: 11, color: AppColors.inkDisabled),
            ),
          ],
        ),
      ],
    );
  }

  static String _relativeTime(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)  return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    if (diff.inDays < 7)     return '${diff.inDays}d ago';
    return '${dt.toLocal().day}/${dt.toLocal().month}';
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

  static String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m ${dt.hour >= 12 ? 'pm' : 'am'}';
  }
}

// ── Status pill ───────────────────────────────────────────────────────────
// DESIGN.md: Hot = white/accentStrong · Warm = inkPrimary/accent ·
//   Cold = outlined only · Future = surfaceBase/navySoft ·
//   Sold = inkPrimary/accentBright · Dead = outlined (dimmed)

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'hot':
        return _solid(status.statusLabel,
            bg: AppColors.accentStrong, fg: Colors.white);
      case 'warm':
        return _solid(status.statusLabel,
            bg: AppColors.accent, fg: AppColors.inkPrimary);
      case 'future':
        return _solid(status.statusLabel,
            bg: AppColors.navySoft, fg: AppColors.surfaceBase);
      case 'sold':
        return _solid(status.statusLabel,
            bg: AppColors.accentBright, fg: AppColors.inkPrimary);
      case 'cold':
        return _outlined(status.statusLabel, color: AppColors.inkSecondary);
      case 'dead':
        return _outlined(status.statusLabel, color: AppColors.inkDisabled);
      default:
        return _outlined(status.statusLabel, color: AppColors.inkSecondary);
    }
  }

  static Widget _solid(String label, {required Color bg, required Color fg}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(9999),
        ),
        child: _pillText(label, fg),
      );

  static Widget _outlined(String label, {required Color color}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(color: color),
        ),
        child: _pillText(label, color),
      );

  static Widget _pillText(String label, Color color) => Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.3,
        ),
      );
}
