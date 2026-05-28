// Story 7.2 — full-screen Sold celebration.
// Phase 1 (1.5s): confetti burst + "Closed!" + lead name.
// Phase 2 (3s or tap): earned-moment card (days to close, actions, optional record line).
// Starts immediately (<300ms); earned-moment stats are fetched in parallel and slotted in.

import 'dart:math';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/models/sold_celebration.dart';
import '../data/motivation_repository.dart';

/// Shows the celebration over the current screen. Returns when dismissed.
Future<void> showSoldCelebration(
  BuildContext context,
  WidgetRef ref, {
  required String leadId,
  String? leadName,
}) {
  // Fetch earned-moment stats in parallel — does not block the confetti.
  final statsFuture = ref.read(motivationRepositoryProvider).fetchSoldCelebration(leadId);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.82),
    barrierLabel: 'Sold celebration',
    transitionDuration: const Duration(milliseconds: 180),
    // Use rootNavigator so the dialog isn't tied to the bottom-sheet's Navigator,
    // which can be popped before the auto-dismiss timer fires.
    useRootNavigator: true,
    pageBuilder: (_, __, ___) => _CelebrationView(
      leadName: leadName,
      statsFuture: statsFuture,
    ),
  );
}

class _CelebrationView extends StatefulWidget {
  final String? leadName;
  final Future<SoldCelebration> statsFuture;
  const _CelebrationView({required this.leadName, required this.statsFuture});

  @override
  State<_CelebrationView> createState() => _CelebrationViewState();
}

class _CelebrationViewState extends State<_CelebrationView> {
  late final ConfettiController _confetti;
  bool _showCard = false;
  bool _dismissed = false; // tracks whether the dialog has already been popped
  SoldCelebration _stats = SoldCelebration.empty;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(milliseconds: 1500))..play();
    widget.statsFuture.then((s) {
      if (mounted) setState(() => _stats = s);
    });
    // Phase 1 → Phase 2 after the burst.
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && !_dismissed) setState(() => _showCard = true);
    });
    // Auto-dismiss 3s after the card appears (total ~4.5s) unless already closed.
    Future.delayed(const Duration(milliseconds: 4500), () {
      if (mounted && !_dismissed) _dismiss();
    });
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    if (mounted) Navigator.of(context, rootNavigator: true).maybePop();
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_showCard) _dismiss();
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirection: pi / 2, // downward
              emissionFrequency: 0.05,
              numberOfParticles: 24,
              maxBlastForce: 22,
              minBlastForce: 8,
              gravity: 0.25,
              colors: const [
                AppColors.accentStrong,
                AppColors.accent,
                Color(0xFFFFC107),
                Color(0xFF25D366),
              ],
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: _showCard ? _earnedCard() : _closedBanner(),
          ),
        ],
      ),
    );
  }

  Widget _closedBanner() {
    return Column(
      key: const ValueKey('banner'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('🎉', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 12),
        const Text(
          'Closed!',
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        if (widget.leadName != null && widget.leadName!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            widget.leadName!,
            style: const TextStyle(fontSize: 18, color: Colors.white70),
          ),
        ],
      ],
    );
  }

  Widget _earnedCard() {
    return Padding(
      key: const ValueKey('card'),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderHairline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 36)),
            const SizedBox(height: 4),
            Text(
              widget.leadName == null || widget.leadName!.isEmpty
                  ? 'Closed!'
                  : '${widget.leadName} — Closed!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.inkPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _stat('${_stats.daysToClose}', _stats.daysToClose == 1 ? 'day to close' : 'days to close'),
                _stat('${_stats.actionCount}', 'touchpoints'),
              ],
            ),
            if (_stats.personalRecord != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.accentStrong.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Text(
                  '⭐  ${_stats.personalRecord!}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentStrong,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Tap to dismiss',
              style: TextStyle(fontSize: 11, color: AppColors.inkSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppColors.inkPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.inkSecondary)),
      ],
    );
  }
}
