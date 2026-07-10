import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/operator_contact.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_repository.dart';
import '../data/billing_repository.dart';
import '../providers/billing_providers.dart';

/// Route wrapper for `/paused`. Reads the billing gate and renders the recharge
/// screen when locked out; otherwise shows a brief loader (the router redirect
/// carries a recovered/renewed tenant back to `/home`).
class PausedRouteScreen extends ConsumerWidget {
  const PausedRouteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(billingGateProvider);
    return gate.maybeWhen(
      data: (g) => g.isLockedOut
          ? PausedScreen(gate: g)
          : const Scaffold(
              backgroundColor: AppColors.surfaceBase,
              body: Center(child: CircularProgressIndicator()),
            ),
      orElse: () => const Scaffold(
        backgroundColor: AppColors.surfaceBase,
        body: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

/// Story 9.6 — the friendly "account paused → recharge" face shown when a tenant
/// is locked out. The real lockout is server-side (0056 + 0092); this screen only
/// explains it and offers a way back. Warm amber, Hindi-first.
class PausedScreen extends ConsumerWidget {
  const PausedScreen({super.key, required this.gate});

  final BillingGate gate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = gate.isAdmin;
    return Scaffold(
      backgroundColor: AppColors.surfaceBase,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AmberBadge(),
                  const SizedBox(height: 24),
                  Text(
                    isAdmin
                        ? 'आपका subscription समाप्त हो गया है'
                        : 'यह workspace अभी paused है',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkPrimary,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isAdmin
                        ? 'आपके CRM का access अभी रुका हुआ है। दोबारा शुरू करने के लिए recharge करें।'
                        : 'कृपया अपने admin से संपर्क करें। उनके recharge करते ही यह फिर से चालू हो जाएगा।',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.inkSecondary,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isAdmin
                        ? 'Your subscription has lapsed — recharge to continue.'
                        : 'Workspace paused. Please contact your admin.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.inkDisabled,
                    ),
                  ),
                  if (isAdmin && gate.billing != null) ...[
                    const SizedBox(height: 22),
                    _BillingCard(billing: gate.billing!),
                    const SizedBox(height: 22),
                    _RechargeButtons(),
                  ],
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () => ref.invalidate(billingGateProvider),
                    child: const Text(
                      'मैंने payment कर दी — दोबारा जाँचें',
                      style: TextStyle(
                        color: AppColors.accentStrong,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.read(authRepositoryProvider).signOut(),
                    child: const Text(
                      'Sign out',
                      style: TextStyle(color: AppColors.inkDisabled),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AmberBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 84,
        height: 84,
        decoration: const BoxDecoration(
          color: AppColors.accentSoft,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.lock_clock_outlined,
          size: 40,
          color: AppColors.statusWarm,
        ),
      ),
    );
  }
}

class _BillingCard extends StatelessWidget {
  const _BillingCard({required this.billing});
  final BillingStatus billing;

  String get _windowLine {
    final d = billing.daysRemaining;
    if (d == null) return 'Plan window: —';
    if (d < 0) return 'Overdue by ${-d} ${-d == 1 ? "day" : "days"}';
    return '$d ${d == 1 ? "day" : "days"} remaining';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv('Plan', billing.planName ?? '—'),
          const SizedBox(height: 8),
          _kv('Status', billing.isOverdue ? 'Overdue' : 'Paused',
              valueColor: AppColors.statusWarm),
          const SizedBox(height: 8),
          _kv('Window', _windowLine),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(k,
            style: const TextStyle(
                fontSize: 13, color: AppColors.inkSecondary)),
        Flexible(
          child: Text(
            v,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppColors.inkPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _RechargeButtons extends StatelessWidget {
  Future<void> _launch(BuildContext context, Uri uri) async {
    final ok = await canLaunchUrl(uri);
    if (ok) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    // No app to handle the intent (e.g. no dialer / WhatsApp not installed).
    // Never leave the only way back as a dead tap — show the number to copy.
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'संपर्क नहीं खुल सका। कृपया कॉल करें: ${OperatorContact.phoneDisplay}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final wa = Uri.parse(
      'https://wa.me/${OperatorContact.phoneE164}'
      '?text=${Uri.encodeComponent(OperatorContact.whatsappMessage)}',
    );
    // tel: needs the leading '+' so the country code (91) is not read as a local prefix.
    final tel = Uri.parse('tel:+${OperatorContact.phoneE164}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () => _launch(context, wa),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.statusSold,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.chat_outlined, size: 20),
          label: const Text('WhatsApp पर recharge करें'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _launch(context, tel),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.inkPrimary,
            side: const BorderSide(color: AppColors.borderStrong),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.call_outlined, size: 20),
          label: const Text('Call ${OperatorContact.phoneDisplay}'),
        ),
      ],
    );
  }
}
