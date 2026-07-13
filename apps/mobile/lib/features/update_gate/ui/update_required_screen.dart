import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/update_gate_providers.dart';

const _playStoreId = 'com.nirmanmedia.nirman_crm';

/// Route wrapper for `/update-required`. Reads the update gate and renders the
/// update screen when this build is below the server minimum; otherwise shows a
/// brief loader (the router redirect carries an up-to-date install back in).
class UpdateRequiredRouteScreen extends ConsumerWidget {
  const UpdateRequiredRouteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final required = ref.watch(updateRequiredProvider);
    return required.maybeWhen(
      data: (r) => r
          ? const UpdateRequiredScreen()
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

/// The friendly "new version required" face (migration 0119). Framed as good
/// news — a new version is ready — never as an error. The backend simply stops
/// being compatible with retired builds; this screen is the calm path forward.
/// English copy (product decision 2026-07-13), same warm tone as the 9.6
/// paused screen.
class UpdateRequiredScreen extends ConsumerWidget {
  const UpdateRequiredScreen({super.key});

  Future<void> _openPlayStore(BuildContext context) async {
    // Prefer the Play app (market:) — falls back to the web listing.
    final market = Uri.parse('market://details?id=$_playStoreId');
    final web =
        Uri.parse('https://play.google.com/store/apps/details?id=$_playStoreId');
    if (await canLaunchUrl(market)) {
      await launchUrl(market, mode: LaunchMode.externalApplication);
      return;
    }
    if (await canLaunchUrl(web)) {
      await launchUrl(web, mode: LaunchMode.externalApplication);
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the Play Store. Please search for '
              '"Nirman CRM" on the Play Store to update.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  Center(
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: const BoxDecoration(
                        color: AppColors.accentSoft,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.system_update_alt,
                        size: 40,
                        color: AppColors.accentStrong,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'A new version is available',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkPrimary,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'This version of the app is out of date. Update from the '
                    'Play Store to continue — it only takes a minute, and '
                    'your data is safe.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.inkSecondary,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => _openPlayStore(context),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.shop_outlined, size: 20),
                    label: const Text('Update on Play Store'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => ref.invalidate(updateRequiredProvider),
                    child: const Text(
                      'Updated — check again',
                      style: TextStyle(
                        color: AppColors.accentStrong,
                        fontWeight: FontWeight.w600,
                      ),
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
